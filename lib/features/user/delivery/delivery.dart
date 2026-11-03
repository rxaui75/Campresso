import 'package:cloud_firestore/cloud_firestore.dart';

Future<String> createDeliveryOrder({
  required String customerId,
  required String customerName,
  required GeoPoint customerLocation,
  required String cafeId,
  required String cafeName,
  required Map<String, dynamic> cartData, // items, totals...
}) async {
  final ref = FirebaseFirestore.instance.collection('orders').doc();

  final now = Timestamp.now();
  final expireAt = Timestamp.fromDate(now.toDate().add(const Duration(minutes: 5)));

  await ref.set({
    // ✅ your existing order fields
    ...cartData,
    'customerId': customerId,
    'customerName': customerName,
    'customerLocation': customerLocation,
    'cafeId': cafeId,
    'cafeName': cafeName,

    // ✅ NEW delivery fields
    'fulfillment': 'delivery',
    'deliveryStatus': 'waiting',
    'deliveryClaimedBy': null,
    'deliveryClaimedAt': null,
    'deliveryExpireAt': expireAt,

    // ✅ common fields
    'status': 'pending_delivery', // أو خليها 'placed' بس أنا أفضل pending_delivery
    'createdAt': FieldValue.serverTimestamp(),
  });

  return ref.id;
}
