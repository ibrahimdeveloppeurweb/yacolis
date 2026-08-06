import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'address_selection_screen.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  // Variables d'état pour les adresses
  String pickupAddress = 'Recherche en cours...';
  String dropoffAddress = 'Adresse de livraison';

  // Coordonnées de la position du client (Par défaut Abidjan)
  LatLng _currentLocation = const LatLng(5.359951, -4.008256);
  
  // Centre de la vue de la carte (décalé vers le sud)
  LatLng get _cameraCenter => LatLng(_currentLocation.latitude - 0.003, _currentLocation.longitude);
  
  // Jeton Mapbox
  final String _mapboxToken = 'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A';
  
  // Contrôleur de la carte
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _fetchRealLocation();
  }

  Future<void> _fetchRealLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      var position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_cameraCenter, 16.5);
      }

      try {
        var placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          var place = placemarks.first;
          if (mounted) {
            setState(() {
              String addressName = place.street?.isNotEmpty == true ? place.street! : 'Position Inconnue';
              // On ne garde que la partie principale du nom de la rue ou du lieu
              if (addressName.contains(',')) {
                addressName = addressName.split(',').first.trim();
              }
              pickupAddress = addressName;
            });
          }
        }
      } catch (e) {
        if (mounted) setState(() { pickupAddress = 'Position actuelle'; });
      }
    } catch (e) {
      if (mounted) setState(() { pickupAddress = 'Erreur GPS'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. La Carte (En fond)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _cameraCenter,
              initialZoom: 16.5, // Zoom plus rapproché pour voir les rues
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=$_mapboxToken',
                userAgentPackageName: 'com.yacolis.app',
                tileSize: 512,
                zoomOffset: -1,
                additionalOptions: const {
                  'accessToken': 'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A',
                },
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 80,
                    height: 80,
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04), // Grand Halo gris clair/transparent
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.785398, // Rotation de -45°
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                  topRight: Radius.circular(2), // Pointe directionnelle
                                ),
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Éléments par dessus la carte
          // En-tête (Voiture / Plus)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car, color: Colors.black, size: 20),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                        child: const Text('F', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.hail, color: Colors.black, size: 20),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle, color: Colors.purple.shade500, size: 20),
                      const SizedBox(width: 4),
                      Text('Plus', style: TextStyle(color: Colors.purple.shade500, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bouton Retour
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.55 + 16,
            left: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          
          // Bouton Navigation
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.55 + 16,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.near_me, color: Colors.black),
                onPressed: () {
                  // Recentrer la carte sur la position visible
                  _mapController.move(_cameraCenter, 16.5);
                },
              ),
            ),
          ),

          // 3. Panneau de commande (Bottom Sheet)
          DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.55,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50, // Fond légèrement gris clair
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle (Poignée)
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      
                      // Titre
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 16.0, bottom: 16.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ENVOYER UN COLIS',
                            style: GoogleFonts.anton(
                              fontSize: 26,
                              color: Colors.black87,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      
                      // Adresses
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Colonne des icônes
                                Column(
                                  children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF333333), // Couleur sombre comme sur capture1
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                                      ),
                                    const SizedBox(height: 32),
                                    const SizedBox(
                                      width: 40,
                                      child: Icon(Icons.flag, color: AppColors.primary, size: 24),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Colonne des textes avec lignes de séparation nettes
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => AddressSelectionScreen(
                                              isSelectingDestination: false,
                                              initialPickupAddress: pickupAddress,
                                              initialDropoffAddress: dropoffAddress,
                                            )),
                                          );
                                          if (result != null && result is String) {
                                            setState(() {
                                              String shortAddress = result;
                                              if (shortAddress.contains(',')) {
                                                shortAddress = shortAddress.split(',').first.trim();
                                              }
                                              pickupAddress = shortAddress;
                                            });
                                          }
                                        },
                                        behavior: HitTestBehavior.opaque,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Prise en charge', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                            const SizedBox(height: 2),
                                            Text(
                                              pickupAddress, 
                                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black87),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 12),
                                            const Divider(height: 1, thickness: 1, color: Colors.black12),
                                          ],
                                        ),
                                      ),
                                      
                                      const SizedBox(height: 24),
                                      
                                      GestureDetector(
                                        onTap: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (context) => AddressSelectionScreen(
                                              isSelectingDestination: true,
                                              initialPickupAddress: pickupAddress,
                                              initialDropoffAddress: dropoffAddress,
                                            )),
                                          );
                                          if (result != null && result is String) {
                                            setState(() {
                                              String shortAddress = result;
                                              if (shortAddress.contains(',')) {
                                                shortAddress = shortAddress.split(',').first.trim();
                                              }
                                              dropoffAddress = shortAddress;
                                            });
                                          }
                                        },
                                        behavior: HitTestBehavior.opaque,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (dropoffAddress != 'Adresse de livraison') 
                                              const Text('≈55 min. · arrivée estimée', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                            if (dropoffAddress != 'Adresse de livraison') 
                                              const SizedBox(height: 2),
                                            Text(
                                              dropoffAddress, 
                                              style: TextStyle(
                                                fontSize: dropoffAddress == 'Adresse de livraison' ? 16 : 18, 
                                                color: dropoffAddress == 'Adresse de livraison' ? Colors.grey.shade600 : Colors.black87, 
                                                fontWeight: dropoffAddress == 'Adresse de livraison' ? FontWeight.normal : FontWeight.w500
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 12),
                                            const Divider(height: 1, thickness: 1, color: Colors.black12),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),

                      // Véhicules
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            _buildVehicleOption('Moto', '1 min.', 'Express', '300 F', true),
                            const SizedBox(width: 12),
                            _buildVehicleOption('Camion', '9 min.', 'Express Cargo', '3400 F', false),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      const SizedBox(height: 180), // Espace pour le bloc fixe du bas (bannière + bouton)
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Bloc Fixe en bas de l'écran (Bannière + Barre de bouton)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, -4), // Ombre vers le haut au-dessus de la bannière
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Bannière inter-villes
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Expedier des colis vers d\'autres villes moins chers',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.secondary, // Orange
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.inventory_2, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.black54),
                      ],
                    ),
                  ),
                  
                  // 2. Barre d'actions (Bouton rouge)
                  Padding(
                    padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).padding.bottom + 16),
                    child: Row(
                      children: [
                        // Icône Billets de banque
                        const Icon(Icons.payments, color: Colors.green, size: 36),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.secondary, // Orange principal de l'application
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Accéder au formulaire de\ncommande',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleOption(String type, String time, String name, String price, bool isSelected) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.grey.shade200 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simulate vehicle image with overlapped time pill
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 40,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                child: Icon(type == 'Moto' ? Icons.motorcycle : Icons.local_shipping, size: 40, color: AppColors.primary),
              ),
              Positioned(
                bottom: -8,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                  ),
                  child: Text(time, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
        ],
      ),
    );
  }
}
