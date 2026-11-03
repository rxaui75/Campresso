// cart_page.dart
import 'package:flutter/material.dart';
import 'cart_controller.dart';
import 'checkout_page.dart';

class CartPage extends StatelessWidget {
  final String cafeId;
  final double distanceKm;
  final String crowdLevel;

  const CartPage({
    super.key,
    required this.cafeId,
    required this.distanceKm,
    required this.crowdLevel,
  });

  // تقدير بسيط جداً للوقت (مبدئي):
  // travelMinutes = distanceKm * 3.2 (تقريباً 3 دقائق لكل 1 كم)
  int _estimateTravelMinutes(double km) {
    final m = (km * 3.2).round();
    return m < 1 ? 1 : m;
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartController.instance;

    return AnimatedBuilder(
      animation: cart,
      builder: (_, __) {
        // ✅ سلة هذا الكافيه فقط
        final items = cart.itemsFor(cafeId);
        final prep = cart.prepTimeMinutesFor(cafeId);
        final travel = _estimateTravelMinutes(distanceKm);
        final estimatedTotal = prep + travel;

        final totalPrice = cart.totalPriceFor(cafeId);
        final itemsCount = cart.itemsCountFor(cafeId);

        return Scaffold(
          appBar: AppBar(
            title: const Text("Cart"),
            centerTitle: true,
          ),
          body: items.isEmpty
              ? Center(
            child: Text(
              "Your cart is empty",
              style: TextStyle(color: Colors.black.withOpacity(0.6)),
            ),
          )
              : ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
            children: [
              _EstimateBox(
                crowdLevel: crowdLevel,
                distanceKm: distanceKm,
                prepMinutes: prep,
                travelMinutes: travel,
                totalMinutes: estimatedTotal,
              ),
              const SizedBox(height: 12),

              for (final item in items)
                _CartItemCard(
                  cafeId: cafeId,
                  itemKey: item.key,
                ),

              const SizedBox(height: 14),
              _SummaryBox(
                total: totalPrice,
                itemsCount: itemsCount,
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    color: Colors.black.withOpacity(0.08),
                    offset: const Offset(0, -6),
                  )
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E6F73),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: items.isEmpty
                    ? null
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CheckoutPage(
                        cafeId: cafeId,
                        distanceKm: distanceKm,
                        crowdLevel: crowdLevel,
                      ),
                    ),
                  );
                },
                child: Text(
                  "Checkout • ${totalPrice.toStringAsFixed(2)} SAR",
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EstimateBox extends StatelessWidget {
  final String crowdLevel;
  final double distanceKm;
  final int prepMinutes;
  final int travelMinutes;
  final int totalMinutes;

  const _EstimateBox({
    required this.crowdLevel,
    required this.distanceKm,
    required this.prepMinutes,
    required this.travelMinutes,
    required this.totalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    Color badgeColor() {
      switch (crowdLevel.toLowerCase()) {
        case 'high':
          return Colors.red.withOpacity(0.12);
        case 'medium':
          return Colors.orange.withOpacity(0.14);
        default:
          return Colors.green.withOpacity(0.12);
      }
    }

    Color badgeTextColor() {
      switch (crowdLevel.toLowerCase()) {
        case 'high':
          return Colors.red.shade700;
        case 'medium':
          return Colors.orange.shade800;
        default:
          return Colors.green.shade700;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Estimated time (initial)",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor(),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Crowd: $crowdLevel",
                  style: TextStyle(fontWeight: FontWeight.w900, color: badgeTextColor()),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "${distanceKm.toStringAsFixed(1)} km",
                style: TextStyle(color: Colors.black.withOpacity(0.6), fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniStat("Prep", "$prepMinutes min")),
              const SizedBox(width: 10),
              Expanded(child: _miniStat("Travel", "$travelMinutes min")),
              const SizedBox(width: 10),
              Expanded(child: _miniStat("Total", "$totalMinutes min", strong: true)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Later we will calculate this using pickup time + movement type + delivery + crowd prediction.",
            style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {bool strong = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              fontSize: strong ? 15.5 : 14.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final String cafeId;
  final String itemKey;

  const _CartItemCard({
    required this.cafeId,
    required this.itemKey,
  });

  @override
  Widget build(BuildContext context) {
    final cart = CartController.instance;

    // ✅ اقرأ من سلة نفس الكافيه
    final items = cart.itemsFor(cafeId);
    final idx = items.indexWhere((e) => e.key == itemKey);
    if (idx < 0) return const SizedBox.shrink();

    final item = items[idx];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 72,
              height: 72,
              color: Colors.black.withOpacity(0.04),
              child: item.imageAsset.isNotEmpty
                  ? Image.asset(item.imageAsset, fit: BoxFit.contain)
                  : const Icon(Icons.local_cafe),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 6),
                if (item.selectedOptions.isNotEmpty)
                  ...item.selectedOptions.map((o) {
                    final qtyTxt = o.qty > 1 ? " x${o.qty}" : "";
                    final priceTxt = o.priceDelta > 0 ? " (+${o.priceDelta.toStringAsFixed(2)})" : "";
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        "• ${o.optionName}$qtyTxt$priceTxt",
                        style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12.5),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  "Unit: ${item.unitPrice.toStringAsFixed(2)} SAR",
                  style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  "Line: ${item.lineTotal.toStringAsFixed(2)} SAR",
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                // ✅ صار لازم cafeId
                onPressed: () => cart.removeByKey(cafeId, item.key),
                icon: const Icon(Icons.delete_outline),
              ),
              Row(
                children: [
                  _MiniBtn(icon: Icons.remove, onTap: () => cart.dec(cafeId, item.key)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text("${item.qty}", style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  _MiniBtn(icon: Icons.add, onTap: () => cart.inc(cafeId, item.key)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final double total;
  final int itemsCount;

  const _SummaryBox({required this.total, required this.itemsCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Items: $itemsCount",
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            "Total: ${total.toStringAsFixed(2)} SAR",
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
