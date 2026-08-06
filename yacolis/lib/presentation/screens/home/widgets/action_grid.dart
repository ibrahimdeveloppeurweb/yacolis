import 'package:flutter/material.dart';
import '../../delivery/delivery_screen.dart';

class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildLargeActionCard('Livraison', 'assets/images/livraison-yacolis.png', context, null, onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const DeliveryScreen()));
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildLargeActionCard('Expéditions', 'assets/images/expedition-yacolis.png', context, null)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildLargeActionCard('Transport', 'assets/images/transport-yacolis.png', context, null)),
              const SizedBox(width: 12),
              Expanded(child: _buildLargeActionCard('Voyage course', 'assets/images/voyage-course-yacolis.png', context, null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeActionCard(String title, String? imagePath, BuildContext context, String? badgeText, {IconData? icon, bool subtitle = false, Color iconColor = Colors.black54, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 100, // Hauteur légèrement ajustée pour être belle partout
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: subtitle
                ? Center(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87, fontSize: 13)),
                          TextSpan(text: '• $badgeText', style: const TextStyle(color: Colors.black54, fontSize: 11)),
                        ],
                      ),
                    ),
                  )
                : Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
                  ),
          ),
          if (imagePath != null)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              bottom: 30,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            )
          else if (icon != null)
            Positioned(
              top: 15,
              left: 0,
              right: 0,
              child: Icon(icon, size: 42, color: iconColor),
            ),
          if (badgeText != null && !subtitle)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildSmallActionCard(String title, IconData? icon, Color iconColor, BuildContext context, {String? imagePath}) {
    double width = (MediaQuery.of(context).size.width - 64) / 4;
    return Column(
      children: [
        Container(
          width: width,
          height: width,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: imagePath != null
                ? Image.asset(imagePath, width: 35, height: 35, fit: BoxFit.contain)
                : Icon(icon, color: iconColor, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
        ),
      ],
    );
  }
}
