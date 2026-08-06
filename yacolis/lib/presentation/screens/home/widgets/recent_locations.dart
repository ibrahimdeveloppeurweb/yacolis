import 'package:flutter/material.dart';

class RecentLocations extends StatelessWidget {
  const RecentLocations({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildLocationItem(
            'Rue De L\'Organisation, 158',
            'La commune Adjamé, Abidjan',
            Icons.location_on,
          ),
          const Divider(height: 24, thickness: 1, color: Color(0xFFEEEEEE)),
          _buildLocationItem(
            'Cocovico',
            'Quartier de la Angré, Cocody, Abidjan',
            Icons.shopping_basket,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationItem(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.grey.shade500, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
