const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

// v2 Firestore triggers
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");

// ✅ NEW: HTTPS function for stress testing
const { onRequest } = require("firebase-functions/v2/https");

// Helper: chunk tokens to max 500 per multicast request
function chunkArray(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

function collectTokens(userData) {
  let tokens = [];

  const fcmTokens = userData.fcmTokens;

  if (fcmTokens && typeof fcmTokens === "object" && !Array.isArray(fcmTokens)) {
    tokens = Object.entries(fcmTokens)
      .filter((pair) => !!pair[1])
      .map((pair) => String(pair[0]));
  } else if (Array.isArray(fcmTokens)) {
    tokens = fcmTokens.map((t) => String(t));
  }

  if (userData.fcmToken) tokens.push(String(userData.fcmToken));

  return Array.from(new Set(tokens)).filter((t) => !!t && t.trim().length > 0);
}

function isCustomerByEmailDomain(userData) {
  const email = String(userData.email || "").toLowerCase().trim();
  return email.endsWith("@pnu.edu.sa");
}

function getAdVisibleValue(ad) {
  const hasVisible = ad && Object.prototype.hasOwnProperty.call(ad, "visible");
  const hasIsActive = ad && Object.prototype.hasOwnProperty.call(ad, "isActive");

  const v1 = hasVisible ? ad.visible : undefined;
  const v2 = hasIsActive ? ad.isActive : undefined;

  const visible = (v1 !== undefined) ? v1 : v2;
  return !!visible;
}

async function forEachCustomerUser(callback) {
  let lastDoc = null;
  const baseQuery = db.collection("users").orderBy(admin.firestore.FieldPath.documentId());

  while (true) {
    let page = baseQuery.limit(300);
    if (lastDoc) page = page.startAfter(lastDoc);

    const usersSnap = await page.get();
    if (usersSnap.empty) break;

    for (const userDoc of usersSnap.docs) {
      const u = userDoc.data() || {};
      if (!isCustomerByEmailDomain(u)) continue;
      await callback(userDoc, u);
    }

    lastDoc = usersSnap.docs[usersSnap.docs.length - 1];
  }
}

async function deleteAdNotificationFromAllCustomers(adId) {
  const notifDocId = "ad_" + String(adId).trim();

  let batch = db.batch();
  let ops = 0;

  await forEachCustomerUser(async (userDoc) => {
    const notifRef = userDoc.ref.collection("notifications").doc(notifDocId);
    batch.delete(notifRef);
    ops++;

    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  });

  if (ops > 0) {
    await batch.commit();
  }
}

async function cleanupBadTokens(userRef, badTokens) {
  if (!badTokens || !badTokens.length) return;

  const updates = {};
  badTokens.forEach((t) => {
    updates["fcmTokens." + t] = admin.firestore.FieldValue.delete();
  });

  try {
    await userRef.set(updates, { merge: true });
  } catch (e) {
    // ignore
  }
}

async function sendPushAndCollectBadTokens(tokens, payload) {
  if (!tokens.length) return [];

  const chunks = chunkArray(tokens, 500);
  const bad = [];

  for (const chunk of chunks) {
    const res = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      ...payload,
    });

    res.responses.forEach((r, idx) => {
      if (!r.success) {
        const err = r.error || null;
        const code = err && err.code ? String(err.code) : "";

        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token" ||
          code === "messaging/invalid-argument"
        ) {
          bad.push(chunk[idx]);
        }
      }
    });
  }

  return bad;
}



/**
 * ✅ NEW:
 * Delivery order created -> notify all available delivery girls
 */
exports.onDeliveryOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data.data() || {};
  const orderId = String(event.params.orderId);

  const fulfillment = String(order.fulfillment || "").toLowerCase().trim();
  const deliveryStatus = String(order.deliveryStatus || "").toLowerCase().trim();

  if (fulfillment !== "delivery") return;
  if (deliveryStatus !== "waiting") return;

  const orderNumber = String(order.orderNumber || "");
  const cafeId = String(order.cafeId || "").trim();
  const cafeName = String(order.cafeName || cafeId || "Cafe");
  const customerId = String(order.customerId || order.userId || "").trim();

  const snap = await db
    .collection("users")
    .where("availableForDelivery", "==", true)
    .limit(100)
    .get();

  if (snap.empty) return;

  const title = "New delivery request";
  const body = orderNumber
    ? `Order #${orderNumber} from ${cafeName} is waiting for delivery.`
    : `A new order from ${cafeName} is waiting for delivery.`;

  let batch = db.batch();
  let ops = 0;

  for (const userDoc of snap.docs) {
    if (customerId && userDoc.id === customerId) continue;

    const userData = userDoc.data() || {};
    const tokens = collectTokens(userData);

    const notifRef = userDoc.ref
      .collection("notifications")
      .doc(`delivery_request_${orderId}`);

    batch.set(
      notifRef,
      {
        type: "delivery_request",
        title: title,
        body: body,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: {
          orderId: orderId,
          orderNumber: String(orderNumber),
          cafeId: cafeId,
          cafeName: cafeName,
          deliveryStatus: deliveryStatus,
          fulfillment: fulfillment,
        },
      },
      { merge: true }
    );

    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }

    if (tokens.length) {
      const badTokens = await sendPushAndCollectBadTokens(tokens, {
        notification: { title, body },
        data: {
          type: "delivery_request",
          orderId: orderId,
          orderNumber: String(orderNumber),
          cafeId: cafeId,
          cafeName: cafeName,
          deliveryStatus: deliveryStatus,
        },
      });

      await cleanupBadTokens(userDoc.ref, badTokens);
    }
  }

  if (ops > 0) {
    await batch.commit();
  }

  return;
});

/**
 * ✅ 1) Order status change -> save in-app notification + send push to that customer
 */
exports.onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data() || {};
  const after = event.data.after.data() || {};

  const beforeStatus = String(before.status || "").toLowerCase().trim();
  const afterStatus = String(after.status || "").toLowerCase().trim();

  if (beforeStatus === afterStatus) return;

  const orderId = String(event.params.orderId);

  const customerId = String(after.customerId || after.userId || "").trim();
  if (!customerId) return;

  const orderNumber = after.orderNumber || after.orderNum || "";
  const cafeName = String(after.cafeName || after.cafeId || "");
  const cafeId = String(after.cafeId || "");

  let title = "Order updated";
  let body = "Order #" + orderNumber + " status: " + afterStatus;

  if (afterStatus === "preparing") {
    title = "Order is preparing";
    body = "Your order #" + orderNumber + " is being prepared.";
  } else if (afterStatus === "ready") {
    title = "Order is ready";
    body = "Your order #" + orderNumber + " is ready to pick up.";
  } else if (afterStatus === "completed") {
    title = "Order completed";
    body = "Order #" + orderNumber + " has been completed.";
  } else if (afterStatus === "cancelled") {
    title = "Order cancelled";
    body = "Order #" + orderNumber + " has been cancelled.";
  }

  await db
    .collection("users")
    .doc(customerId)
    .collection("notifications")
    .add({
      type: "order",
      title: title,
      body: body,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      data: {
        orderId: orderId,
        status: String(afterStatus),
        cafeId: cafeId,
        cafeName: cafeName,
        orderNumber: String(orderNumber),
      },
    });

  const userDoc = await db.collection("users").doc(customerId).get();
  if (!userDoc.exists) return;

  const userData = userDoc.data() || {};
  const tokens = collectTokens(userData);
  if (!tokens.length) return;

  const bad = await sendPushAndCollectBadTokens(tokens, {
    notification: { title: title, body: body },
    data: {
      type: "order",
      orderId: orderId,
      status: String(afterStatus),
    },
  });

  await cleanupBadTokens(db.collection("users").doc(customerId), bad);

  return;
});

/**
 * ✅ 2) Cafe Ad publish / hide / delete
 */
exports.onCafeAdWritten = onDocumentWritten("cafes/{cafeId}/ads/{adId}", async (event) => {
  const cafeId = String(event.params.cafeId);
  const adId = String(event.params.adId);
  const notifDocId = "ad_" + adId;

  const afterSnap = event.data.after;
  const beforeSnap = event.data.before;

  const beforeData = beforeSnap ? (beforeSnap.data() || {}) : {};
  const afterData = afterSnap ? (afterSnap.data() || {}) : {};

  const beforeVisible = getAdVisibleValue(beforeData);
  const afterVisible = afterSnap ? getAdVisibleValue(afterData) : false;

  if (!afterSnap) {
    await deleteAdNotificationFromAllCustomers(adId);
    return;
  }

  if (beforeVisible === true && afterVisible !== true) {
    await deleteAdNotificationFromAllCustomers(adId);
    return;
  }

  if (afterVisible !== true) return;

  const justBecameVisible = beforeVisible !== true && afterVisible === true;

  const title = String(afterData.title || "New Offer");
  const body = String(afterData.body || "Check out the latest offer!");
  const imageUrl = String(afterData.imageUrl || "");
  const imagePath = String(afterData.imagePath || "");

  let cafeName = "";
  try {
    const cafeSnap = await db.collection("cafes").doc(cafeId).get();
    if (cafeSnap.exists) {
      const c = cafeSnap.data() || {};
      cafeName = String(c.name || c.cafeName || c.name_en || "");
    }
  } catch (e) {
    // ignore
  }

  const tokensSet = new Set();
  let batch = db.batch();
  let ops = 0;

  await forEachCustomerUser(async (userDoc, u) => {
    const userTokens = collectTokens(u);
    userTokens.forEach((t) => tokensSet.add(t));

    const notifRef = userDoc.ref.collection("notifications").doc(notifDocId);
    batch.set(
      notifRef,
      {
        type: "ad",
        adId: adId,
        cafeId: cafeId,
        title: title,
        body: body,
        read: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        data: {
          adId: adId,
          cafeId: cafeId,
          cafeName: cafeName,
          imageUrl: imageUrl,
          imagePath: imagePath,
          path: "cafes/" + cafeId + "/ads/" + adId,
        },
      },
      { merge: true }
    );

    ops++;
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  });

  if (ops > 0) {
    await batch.commit();
  }

  if (!justBecameVisible) return;

  const tokens = Array.from(tokensSet).filter((t) => !!t && t.trim().length > 0);
  if (!tokens.length) return;

  const chunks = chunkArray(tokens, 500);
  for (const chunk of chunks) {
    await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      notification: { title: title, body: body },
      data: {
        type: "ad",
        adId: adId,
        cafeId: cafeId,
        title: title,
        body: body,
      },
    });
  }

  return;
});