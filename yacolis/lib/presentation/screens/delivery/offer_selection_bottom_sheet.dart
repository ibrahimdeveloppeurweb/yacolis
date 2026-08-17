import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'order_details_sheet.dart';
import 'address_selection_screen.dart';

class OfferSelectionBottomSheet extends StatefulWidget {
  final String selectedVehicle;
  final int tripMinutes;
  final String pickupAddress;
  final List<String> dropoffAddresses;
  final Function(String, double?, double?) onAddStop;
  final Function(int) onRemoveStop;

  const OfferSelectionBottomSheet({
    super.key,
    required this.selectedVehicle,
    required this.tripMinutes,
    required this.pickupAddress,
    required this.dropoffAddresses,
    required this.onAddStop,
    required this.onRemoveStop,
  });

  @override
  State<OfferSelectionBottomSheet> createState() => _OfferSelectionBottomSheetState();
}

class _OfferSelectionBottomSheetState extends State<OfferSelectionBottomSheet> {
  late int basePriceASAP;
  late int basePriceScheduled;
  late int priceUrgent;
  
  late int userPriceASAP;
  late int userPriceScheduled;
  
  String _selectedOfferId = 'ASAP'; // 'ASAP', 'Scheduled', 'Urgent'
  
  TimeOfDay? scheduledTime;

  @override
  void initState() {
    super.initState();
    _calculatePrices();
  }

  void _calculatePrices() {
    // Calcul de base (Mockup réaliste pour la Côte d'Ivoire)
    int baseAmount = widget.selectedVehicle == 'Moto' 
        ? (widget.tripMinutes * 75) + 500
        : (widget.tripMinutes * 150) + 1000;
        
    // Arrondir à la cinquantaine la plus proche
    baseAmount = (baseAmount / 50).round() * 50;

    basePriceASAP = baseAmount;
    basePriceScheduled = baseAmount; // Souvent le même prix de base ou légèrement plus cher
    priceUrgent = baseAmount + (widget.selectedVehicle == 'Moto' ? 1000 : 2500);

    userPriceASAP = basePriceASAP;
    userPriceScheduled = basePriceScheduled;
  }

  void _incrementPrice(String offerType) {
    setState(() {
      if (offerType == 'ASAP') {
        userPriceASAP += 100;
      } else if (offerType == 'Scheduled') {
        userPriceScheduled += 100;
      }
    });
  }

  void _decrementPrice(String offerType) {
    setState(() {
      if (offerType == 'ASAP' && userPriceASAP > 500) {
        userPriceASAP -= 100;
      } else if (offerType == 'Scheduled' && userPriceScheduled > 500) {
        userPriceScheduled -= 100;
      }
    });
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.secondary, // Orange Yacolis
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != scheduledTime) {
      setState(() {
        scheduledTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Colors.white, // Fond blanc demandé
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
            top: 16,
            left: 16,
            right: 16,
            bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF002259),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.selectedVehicle == 'Moto' ? Icons.motorcycle : Icons.local_shipping, 
                      color: Colors.white, 
                      size: 20
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.selectedVehicle == 'Moto' ? 'Express' : 'Express Cargo',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 16, color: Colors.black54),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address Block
                  _buildAddressBlock(),
                  
                  // Buttons + Adresse / Itinéraire
                  Padding(
                    padding: const EdgeInsets.only(left: 40, top: 12, bottom: 24),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddressSelectionScreen(
                                  isSelectingDestination: true,
                                  initialPickupAddress: widget.pickupAddress,
                                ),
                              ),
                            );

                            if (result != null && result is Map<String, dynamic>) {
                              String newDropoff = result['dropoff']?.toString() ?? '';
                              if (newDropoff.contains(',')) {
                                newDropoff = newDropoff.split(',').first.trim();
                              }
                              
                              if (newDropoff.isNotEmpty && newDropoff != 'Adresse de livraison') {
                                widget.onAddStop(
                                  newDropoff, 
                                  result['dropoffLat'], 
                                  result['dropoffLng']
                                );
                                // Fermer la modale pour laisser l'utilisateur voir le recalcul sur la carte
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Calcul du nouvel itinéraire et des tarifs...'),
                                    backgroundColor: AppColors.secondary,
                                  )
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.add, size: 16),
                                SizedBox(width: 4),
                                Text('Adresse', style: TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.map, size: 16),
                                SizedBox(width: 4),
                                Text('Itinéraire', style: TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Icone du véhicule retirée
                  
                  Divider(color: Colors.grey.shade200, thickness: 1, height: 1),
                  const SizedBox(height: 16),

                  // 1. Offre : Dès que possible (Négociable)
                  _buildNegotiableOffer(
                    title: 'Dès que possible',
                    subtitle: 'Le livreur vient immédiatement',
                    icon: Icons.timer,
                    currentPrice: userPriceASAP,
                    basePrice: basePriceASAP,
                    isSelected: _selectedOfferId == 'ASAP',
                    onTap: () => setState(() => _selectedOfferId = 'ASAP'),
                    onIncrement: () => _incrementPrice('ASAP'),
                    onDecrement: () => _decrementPrice('ASAP'),
                  ),

                  const SizedBox(height: 16),

                  // 2. Offre : Programmer (Négociable)
                  _buildNegotiableOffer(
                    title: 'Programmer la livraison',
                    subtitle: scheduledTime == null 
                        ? 'Choisissez l\'heure exacte' 
                        : 'Prévu pour ${scheduledTime!.format(context)}',
                    icon: Icons.calendar_month,
                    currentPrice: userPriceScheduled,
                    basePrice: basePriceScheduled,
                    isSelected: _selectedOfferId == 'Scheduled',
                    onTap: () => setState(() => _selectedOfferId = 'Scheduled'),
                    onIncrement: () => _incrementPrice('Scheduled'),
                    onDecrement: () => _decrementPrice('Scheduled'),
                    actionWidget: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: InkWell(
                        onTap: () => _selectTime(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.access_time, size: 16, color: AppColors.secondary),
                              const SizedBox(width: 8),
                              Text(
                                scheduledTime == null ? 'Définir l\'heure' : 'Changer l\'heure',
                                style: const TextStyle(color: AppColors.secondary, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Offre : Urgent (Non négociable)
                  GestureDetector(
                    onTap: () => setState(() => _selectedOfferId = 'Urgent'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: _selectedOfferId == 'Urgent' ? Colors.white : Colors.grey.shade50,
                        border: _selectedOfferId == 'Urgent' 
                            ? Border.all(color: AppColors.secondary, width: 2) 
                            : Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.bolt, color: Colors.redAccent),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Urgent',
                                style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Livraison express prioritaire',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$priceUrgent FCFA',
                          style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        if (_selectedOfferId == 'Urgent')
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
                ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                String finalOfferName = 'Dès que possible';
                int finalPrice = userPriceASAP;
                if (_selectedOfferId == 'Scheduled') {
                  finalOfferName = 'Programmer la livraison';
                  finalPrice = userPriceScheduled;
                } else if (_selectedOfferId == 'Urgent') {
                  finalOfferName = 'Urgent';
                  finalPrice = priceUrgent;
                }

                String? timeStr;
                if (_selectedOfferId == 'Scheduled' && scheduledTime != null) {
                  timeStr = scheduledTime!.format(context);
                }

                // Ouvre le formulaire détaillé (OrderDetailsSheet)
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => OrderDetailsSheet(
                    offerName: finalOfferName,
                    vehicleName: widget.selectedVehicle,
                    negotiatedPrice: finalPrice, 
                    pickupAddress: widget.pickupAddress,
                    dropoffAddresses: widget.dropoffAddresses,
                    etaMinutes: widget.tripMinutes,
                    scheduledTimeStr: timeStr,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary, // Orange Yacolis
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Confirmer et continuer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        ),
      ),
    ),
  );
}

  Widget _buildNegotiableOffer({
    required String title,
    required String subtitle,
    required IconData icon,
    required int currentPrice,
    required int basePrice,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
    Widget? actionWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.grey.shade50,
          border: isSelected 
              ? Border.all(color: AppColors.secondary, width: 2) 
              : Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 12),
          if (actionWidget != null) actionWidget!,
          // Contrôles de négociation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onDecrement,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove, color: AppColors.primary),
                ),
              ),
              Column(
                children: [
                  Text(
                    '$currentPrice FCFA',
                    style: const TextStyle(color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (currentPrice != basePrice)
                    Text(
                      'Tarif recommandé: $basePrice FCFA',
                      style: const TextStyle(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.w600),
                    )
                  else
                    const Text(
                      'Tarif recommandé',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                ],
              ),
              GestureDetector(
                onTap: onIncrement,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: AppColors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildAddressBlock() {
    return Column(
      children: [
        _buildAddressRow(
          icon: Icons.inventory_2,
          isBox: true,
          label: 'Point de départ',
          address: widget.pickupAddress,
        ),
        for (int i = 0; i < widget.dropoffAddresses.length; i++) ...[
          _buildAddressLine(),
          _buildAddressRow(
            number: i + 1,
            label: 'Destination',
            address: widget.dropoffAddresses[i],
            onRemove: widget.dropoffAddresses.length > 1 ? () {
              widget.onRemoveStop(i);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Suppression de l\'adresse et recalcul...'),
                  backgroundColor: AppColors.secondary,
                )
              );
            } : null,
          ),
        ],
      ],
    );
  }

  Widget _buildAddressRow({IconData? icon, bool isBox = false, int? number, required String label, required String address, VoidCallback? onRemove}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 4, right: 16),
          decoration: BoxDecoration(
            color: isBox ? Colors.grey.shade800 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(isBox ? 6 : 12),
          ),
          alignment: Alignment.center,
          child: number != null
              ? Text(number.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))
              : Icon(icon, color: Colors.white, size: 14),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              const SizedBox(height: 2),
              Text(address, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
        else
          const Icon(Icons.chevron_right, color: Colors.grey),
      ],
    );
  }

  Widget _buildAddressLine() {
    return Container(
      margin: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
      height: 20,
      width: 2,
      color: Colors.grey.shade300,
    );
  }
}
