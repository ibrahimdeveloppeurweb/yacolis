import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:app_links/app_links.dart';
import '../../../core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
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

  // Centre de la vue de la carte (décalé pour ajuster le marqueur au-dessus du panneau)
  LatLng get _cameraCenter =>
      LatLng(_currentLocation.latitude - 0.0007, _currentLocation.longitude);

  // Contrôleur de la carte flutter_map
  final MapController _mapController = MapController();

  // Jeton Mapbox
  final String _mapboxToken =
      'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A';

  // État de chargement initial (Splash Screen)
  bool _isReady = false;
  StreamSubscription<Position>? _positionStream;
  Timer? _splashTimer;
  
  // App Links pour intercepter les liens WhatsApp (geo: ou Google Maps)
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _fetchRealLocation();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();
    
    // Si l'application était fermée et s'ouvre via un lien WhatsApp
    _appLinks.getInitialAppLink().then((uri) {
      if (uri != null) _handleIncomingLink(uri);
    });

    // Si l'application est déjà ouverte en arrière-plan
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleIncomingLink(uri);
    });
  }

  void _handleIncomingLink(Uri uri) {
    // Cas 1 : WhatsApp envoie un lien du type geo:latitude,longitude
    if (uri.scheme == 'geo') {
      String path = uri.path; // ex: 5.3599,-4.0083
      if (path.contains(',')) {
        var parts = path.split(',');
        double lat = double.tryParse(parts[0]) ?? 0;
        double lng = double.tryParse(parts[1]) ?? 0;
        _setDestinationFromCoordinates(lat, lng);
      }
    } 
    // Cas 2 : Lien Google Maps standard (https://maps.google.com/?q=lat,lng)
    else {
      String? q = uri.queryParameters['q'];
      if (q != null && q.contains(',')) {
        var parts = q.split(',');
        double lat = double.tryParse(parts[0]) ?? 0;
        double lng = double.tryParse(parts[1]) ?? 0;
        _setDestinationFromCoordinates(lat, lng);
      }
    }
  }

  Future<void> _setDestinationFromCoordinates(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        List<String> addressParts = [];
        if (place.street != null && place.street!.isNotEmpty) addressParts.add(place.street!);
        if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
        
        if (addressParts.isNotEmpty) {
          setState(() {
            dropoffAddress = addressParts.join(', ');
          });
        }
      }
    } catch (e) {
      // Si la rue n'est pas trouvée, on affiche les coordonnées GPS
      setState(() {
        dropoffAddress = "Lieu pointé ($lat, $lng)";
      });
    }
  }

  void _hideSplashScreen() {
    if (_isReady) return;
    _splashTimer?.cancel();
    // On donne 3.5 secondes à la carte pour charger ses tuiles en arrière-plan
    // au nouvel emplacement avant de faire disparaître l'écran
    _splashTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _isReady = true);
    });
  }

  Future<void> _updateAddress(double lat, double lon) async {
    try {
      var placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        var place = placemarks.first;
        if (mounted) {
          setState(() {
            String addressName = place.street?.isNotEmpty == true
                ? place.street!
                : 'Position Inconnue';
            if (addressName.contains(',')) {
              addressName = addressName.split(',').first.trim();
            }
            pickupAddress = addressName;
          });
        }
      }
    } catch (e) {
      if (mounted && pickupAddress == 'Recherche en cours...') {
        setState(() {
          pickupAddress = 'Position actuelle';
        });
      }
    }
  }

  Future<void> _fetchRealLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted)
          setState(() {
            pickupAddress = 'GPS désactivé';
          });
        _hideSplashScreen();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted)
            setState(() {
              pickupAddress = 'Permission refusée';
            });
          _hideSplashScreen();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted)
          setState(() {
            pickupAddress = 'Permission refusée';
          });
        _hideSplashScreen();
        return;
      }

      // 1. Charger immédiatement la dernière position connue pour une fluidité instantanée
      var lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        setState(() {
          _currentLocation =
              LatLng(lastPosition.latitude, lastPosition.longitude);
        });

        // Délai pour s'assurer que le MapController est prêt
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _mapController.move(_cameraCenter, 17.5);
        });

        _hideSplashScreen(); // Démarre le décompte pour cacher l'écran

        // Mettre à jour l'adresse immédiatement sans attendre le GPS précis
        _updateAddress(lastPosition.latitude, lastPosition.longitude);
      }

      // 2. Affiner avec la position GPS exacte en arrière-plan
      var position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 4),
        onTimeout: () => lastPosition ?? Geolocator.getCurrentPosition(),
      );

      if (position != null && mounted) {
        // Mettre à jour seulement si la nouvelle position est différente (optimisation)
        if (lastPosition == null ||
            Geolocator.distanceBetween(
                    lastPosition.latitude,
                    lastPosition.longitude,
                    position.latitude,
                    position.longitude) >
                20) {
          setState(() {
            _currentLocation = LatLng(position.latitude, position.longitude);
          });

          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _mapController.move(_cameraCenter, 17.5);
          });

          _hideSplashScreen(); // Démarre le décompte si ce n'était pas fait
          _updateAddress(position.latitude, position.longitude);
        }
      }

      // 3. Écoute continue en arrière-plan (Mise à jour en direct comme Yango)
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // Mise à jour tous les 15 mètres de déplacement
        ),
      ).listen((Position newPosition) {
        if (mounted) {
          setState(() {
            _currentLocation =
                LatLng(newPosition.latitude, newPosition.longitude);
          });
          
          // La carte suit automatiquement le déplacement de l'utilisateur !
          try {
            _mapController.move(_cameraCenter, _mapController.camera.zoom);
          } catch (_) {
            // Sécurité au cas où la carte ne serait pas encore totalement affichée
          }

          _updateAddress(newPosition.latitude, newPosition.longitude);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (pickupAddress == 'Recherche en cours...')
            pickupAddress = 'Erreur GPS';
        });
        _hideSplashScreen();
      }
    }
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _positionStream?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 0. Grille de chargement en arrière-plan (Style Yango)
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF7F7F7), // Fond très clair
              child: GridPaper(
                color: Colors.black.withOpacity(0.04), // Lignes très subtiles
                interval: 20, // Petits carreaux
                divisions: 1,
                subdivisions: 1,
              ),
            ),
          ),

          // 1. La Carte (En fond avec flutter_map et Mapbox Data)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              backgroundColor: Colors.transparent, // Laisse apparaître la grille en dessous
              initialCenter: _cameraCenter,
              initialZoom: 17.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=$_mapboxToken',
                userAgentPackageName: 'com.yacolis.app',
                tileSize: 512,
                zoomOffset: -1,
                keepBuffer: 2, // Réduit de 6 à 2 pour charger 5x plus vite !
                additionalOptions: const {
                  'accessToken':
                      'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A',
                },
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Grand halo transparent
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE94335).withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                        ),
                        // Cercle rouge Yango
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF94B2E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                        ),
                        // Flèche blanche
                        Transform.translate(
                          offset: const Offset(3, -3),
                          child: Transform.rotate(
                            angle: -0.785398, // -45 degrés
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(1),
                                  bottomLeft: Radius.circular(1),
                                  bottomRight: Radius.circular(1),
                                  topRight: Radius.circular(4), // Pointe
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 8)
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car,
                          color: Colors.black, size: 20),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                        child: const Text('F',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.hail, color: Colors.black, size: 20),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 8)
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle,
                          color: Colors.purple.shade500, size: 20),
                      const SizedBox(width: 4),
                      Text('Plus',
                          style: TextStyle(
                              color: Colors.purple.shade500,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bouton Retour
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.51 + 8,
            left: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          // Bouton Navigation
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.51 + 8,
            right: 16,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 2))
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.near_me, color: Colors.black),
                onPressed: () {
                  // Recentrer la carte sur la position visible
                  _mapController.move(_cameraCenter, 17.5);
                },
              ),
            ),
          ),

          // 3. Panneau de commande (Bottom Sheet)
          DraggableScrollableSheet(
            initialChildSize: 0.51,
            minChildSize: 0.51, // Bloqué en bas pour garantir la visibilité
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, -2))
                  ],
                ),
                child: Column(
                  children: [
                    // --- PARTIE SCROLLABLE ---
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Handle (Poignée)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(top: 8),
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
                              padding: const EdgeInsets.only(
                                  left: 20.0,
                                  right: 20.0,
                                  top: 12.0,
                                  bottom: 8.0),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'ENVOYER UN COLIS',
                                  style: GoogleFonts.anton(
                                    fontSize: 22,
                                    color: Colors.black87,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),

                            // Adresses
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20.0),
                              child: Column(
                                children: [
                                  // --- Prise en charge ---
                                  GestureDetector(
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                AddressSelectionScreen(
                                                  isSelectingDestination: false,
                                                  initialPickupAddress:
                                                      pickupAddress,
                                                  initialDropoffAddress:
                                                      dropoffAddress,
                                                )),
                                      );
                                      if (result != null && result is Map) {
                                        setState(() {
                                          String shortPickup =
                                              result['pickup']?.toString() ??
                                                  '';
                                          String shortDropoff =
                                              result['dropoff']?.toString() ??
                                                  '';

                                          if (shortPickup.contains(',')) {
                                            shortPickup = shortPickup
                                                .split(',')
                                                .first
                                                .trim();
                                          }
                                          if (shortDropoff.contains(',')) {
                                            shortDropoff = shortDropoff
                                                .split(',')
                                                .first
                                                .trim();
                                          }

                                          if (shortPickup.isNotEmpty)
                                            pickupAddress = shortPickup;
                                          if (shortDropoff.isNotEmpty)
                                            dropoffAddress = shortDropoff;
                                        });
                                      }
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF333333),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.inventory_2,
                                              color: Colors.white, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('Prise en charge',
                                                  style: TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12)),
                                              Text(
                                                pickupAddress,
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black87),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 12),
                                              const Divider(
                                                  height: 1,
                                                  thickness: 1,
                                                  color: Colors.black12),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // --- Adresse de livraison ---
                                  GestureDetector(
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                AddressSelectionScreen(
                                                  isSelectingDestination: true,
                                                  initialPickupAddress:
                                                      pickupAddress,
                                                  initialDropoffAddress:
                                                      dropoffAddress,
                                                )),
                                      );
                                      if (result != null && result is Map) {
                                        setState(() {
                                          String shortPickup =
                                              result['pickup']?.toString() ??
                                                  '';
                                          String shortDropoff =
                                              result['dropoff']?.toString() ??
                                                  '';

                                          if (shortPickup.contains(',')) {
                                            shortPickup = shortPickup
                                                .split(',')
                                                .first
                                                .trim();
                                          }
                                          if (shortDropoff.contains(',')) {
                                            shortDropoff = shortDropoff
                                                .split(',')
                                                .first
                                                .trim();
                                          }

                                          if (shortPickup.isNotEmpty)
                                            pickupAddress = shortPickup;
                                          if (shortDropoff.isNotEmpty)
                                            dropoffAddress = shortDropoff;
                                        });
                                      }
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                          width: 36,
                                          child: Icon(Icons.sports_score,
                                              color: Colors.black87, size: 24),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (dropoffAddress !=
                                                  'Adresse de livraison')
                                                const Text(
                                                    '≈55 min. · arrivée estimée',
                                                    style: TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 12)),
                                              Text(
                                                dropoffAddress,
                                                style: TextStyle(
                                                    fontSize: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? 14
                                                        : 15,
                                                    color: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? Colors.grey.shade600
                                                        : Colors.black87,
                                                    fontWeight: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? FontWeight.normal
                                                        : FontWeight.w500),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade200,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: const Text('Arrêts',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.black87)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Véhicules
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                children: [
                                  _buildVehicleOption(
                                      'Moto', '10 min.', 'Express', true),
                                  const SizedBox(width: 8),
                                  _buildVehicleOption('Camion', '12 min.',
                                      'Express Cargo', false),
                                ],
                              ),
                            ),
                            // SizedBox final supprimé pour retirer l'espace vide
                          ],
                        ),
                      ),
                    ),

                    // --- PARTIE FIXE EN BAS DU TIROIR ---
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. Bannière inter-villes
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0, vertical: 8.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Expedier des colis vers d\'autres villes moins chers',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF7F25),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.inventory_2,
                                        color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right,
                                      color: Colors.black54, size: 16),
                                ],
                              ),
                            ),

                            // 2. Barre d'actions (Bouton orange)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 20, right: 20, bottom: 12, top: 0),
                              child: Row(
                                children: [
                                  const Icon(Icons.payments,
                                      color: Colors.green, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {},
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFFF7F25),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Accéder au formulaire de\ncommande',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.tune,
                                      color: Colors.black87, size: 20),
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
            },
          ),
          // 3. Splash Screen Overlay (Par dessus TOUT le reste)
          if (!_isReady)
            Positioned.fill(
              child: Container(
                // 0xFE au lieu de 0xFF (99% opaque) pour forcer Flutter à dessiner la carte en dessous
                color: const Color(0xFE002259),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Yacolis',
                          style: GoogleFonts.anton(
                              fontSize: 48,
                              color: Colors.white,
                              fontStyle: FontStyle.italic)),
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(color: Color(0xFFFF7F25)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleOption(
      String type, String time, String name, bool isSelected) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 48,
                width: double.infinity,
                alignment: Alignment.topLeft,
                child: Icon(
                    type == 'Moto' ? Icons.motorcycle : Icons.local_shipping,
                    size: 38,
                    color: const Color(0xFF002259)),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black12,
                          blurRadius: 2,
                          offset: Offset(0, 1))
                    ],
                  ),
                  child: Text(time,
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(name,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
        ],
      ),
    );
  }
}
