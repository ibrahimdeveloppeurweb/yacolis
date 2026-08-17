import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class OrderDetailsSheet extends StatefulWidget {
  final String offerName;
  final String vehicleName;
  final int negotiatedPrice;
  final String pickupAddress;
  final List<String> dropoffAddresses;
  final int etaMinutes;
  final String? scheduledTimeStr;

  const OrderDetailsSheet({
    super.key,
    required this.offerName,
    required this.vehicleName,
    required this.negotiatedPrice,
    required this.pickupAddress,
    required this.dropoffAddresses,
    required this.etaMinutes,
    this.scheduledTimeStr,
  });

  @override
  State<OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<OrderDetailsSheet> {
  String _deliveryPreference = 'entrance'; // 'door' or 'entrance'
  final int _doorToDoorFee = 200; // Frais supplémentaire
  final Map<int, String> _contacts = {}; // -1 for pickup, 0..n for dropoffs

  Future<void> _updateContact(int index) async {
    String currentContact = _contacts[index] ?? (index == -1 ? '+2250555568405' : 'Ajouter un contact');
    TextEditingController controller = TextEditingController(
      text: currentContact == 'Ajouter un contact' ? '' : currentContact
    );

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Numéro de contact', style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: 'Ex: 0102030405',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Valider', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _contacts[index] = result;
      });
    }
  }

  int get _finalPrice {
    return widget.negotiatedPrice + (_deliveryPreference == 'door' ? _doorToDoorFee : 0);
  }

  bool get _areAllContactsFilled {
    // Vérifie que pour chaque arrêt (0 à n-1), le contact est renseigné
    for (int i = 0; i < widget.dropoffAddresses.length; i++) {
      if (_contacts[i] == null || _contacts[i]!.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height, // 100% height
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.offerName,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                      Text(
                        widget.scheduledTimeStr != null 
                            ? 'En ${widget.vehicleName.toLowerCase()} • Prévu à ${widget.scheduledTimeStr}'
                            : 'En ${widget.vehicleName.toLowerCase()}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 48), // Pour équilibrer le titre au centre
              ],
            ),
          ),
          
          const Divider(height: 24, color: Color(0xFFEEEEEE)),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Comment préférez-vous ?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  
                  // Préférences de livraison
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        _buildPreferenceOption(
                          id: 'door',
                          title: 'Porte-à-porte',
                          subtitle: 'Le coursier se rendra à votre étage',
                          icon: Icons.door_front_door_outlined,
                          price: widget.negotiatedPrice + _doorToDoorFee,
                        ),
                        const Divider(height: 1, indent: 56),
                        _buildPreferenceOption(
                          id: 'entrance',
                          title: 'À l\'entrée',
                          subtitle: 'Vous rejoignez le coursier à l\'extérieur',
                          icon: Icons.directions_walk,
                          price: widget.negotiatedPrice,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Adresses et champs
                  _buildAddressSection(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // Footer
          Container(
            padding: EdgeInsets.only(
              top: 16,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.scheduledTimeStr != null 
                              ? 'Enlèvement à ${widget.scheduledTimeStr}'
                              : 'Enlèvement dans ${widget.etaMinutes} min',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Livraison estimée sous peu',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    Text(
                      '$_finalPrice F',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    // Bouton Espèces
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.payments, color: Colors.green),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Paiement', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                              Text('Espèces', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Bouton Commander
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _areAllContactsFilled ? () {
                          // Action pour confirmer la commande finale
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          disabledBackgroundColor: Colors.grey.shade300,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Commander',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildPreferenceOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required int price,
  }) {
    bool isSelected = _deliveryPreference == id;
    return InkWell(
      onTap: () {
        setState(() {
          _deliveryPreference = id;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: AppColors.primary, width: 1.5) : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '$price F',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne visuelle
          Column(
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.inventory_2, color: AppColors.primary, size: 20),
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: AppColors.secondary, // Ligne orange Yacolis
                ),
              ),
              const Icon(Icons.sports_score, color: AppColors.primary, size: 20),
              const SizedBox(height: 24), // Espacement pour aligner
            ],
          ),
          const SizedBox(width: 16),
          // Contenu
          Expanded(
            child: Column(
              children: [
                _buildAddressBlock('D\'où', widget.pickupAddress, -1),
                const SizedBox(height: 32),
                for (int i = 0; i < widget.dropoffAddresses.length; i++) ...[
                  _buildAddressBlock(
                    widget.dropoffAddresses.length > 1 ? 'Où (Arrêt ${i + 1})' : 'Où',
                    widget.dropoffAddresses[i],
                    i
                  ),
                  if (i < widget.dropoffAddresses.length - 1)
                    const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBlock(String title, String address, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
        const SizedBox(height: 4),
        // Champ Commentaire
        TextField(
          decoration: InputDecoration(
            hintText: 'Commentaire',
            hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEEEEEE))),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFEEEEEE))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            isDense: true,
            suffixIcon: Container(
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.attach_file, color: AppColors.textSecondary, size: 16),
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          style: const TextStyle(fontSize: 14),
        ),
        // Champ Contact
        InkWell(
          onTap: () => _updateContact(index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Contact', style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Text(_contacts[index] ?? (index == -1 ? '+2250555568405' : 'Ajouter un contact'), style: TextStyle(fontSize: 14, color: (_contacts[index] == null && index != -1) ? AppColors.secondary : AppColors.textSecondary)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
