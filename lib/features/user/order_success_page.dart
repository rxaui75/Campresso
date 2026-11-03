// order_success_page.dart
import 'package:flutter/material.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

import 'order_tracking_page.dart';

class OrderSuccessPage extends StatelessWidget {
  final String orderId;
  final int estimatedMinutes;
  final double amountPaid;
  final int orderNumber;

  const OrderSuccessPage({
    super.key,
    required this.orderId,
    required this.estimatedMinutes,
    required this.amountPaid,
    required this.orderNumber,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    const teal = Color(0xFF0E6F73);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(" "),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: teal.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.check, color: teal, size: 28),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      t.orderSuccessTitle, // "Yay! Your order\nhas been placed."
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 26),

                    _infoRow(
                      icon: Icons.schedule,
                      left: t.orderSuccessEstimatedTime,
                      right: t.minutesCount(estimatedMinutes),
                    ),

                    const SizedBox(height: 12),

                    _infoRow(
                      icon: Icons.payments_outlined,
                      left: t.orderSuccessAmountPaid,
                      right: t.amountSar(amountPaid.toStringAsFixed(2)),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderTrackingPage(
                            orderId: orderId,
                            orderNumber: orderNumber,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      t.orderSuccessTrackMyOrder,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _infoRow({
    required IconData icon,
    required String left,
    required String right,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            left,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          right,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
