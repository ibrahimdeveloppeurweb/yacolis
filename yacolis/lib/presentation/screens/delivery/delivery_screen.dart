import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:app_links/app_links.dart';
import '../../../core/theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'address_selection_screen.dart';
import 'offer_selection_bottom_sheet.dart';

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen>
    with TickerProviderStateMixin {
  // Variables d'Ã©tat pour les adresses
  String pickupAddress = 'Recherche en cours...';
  List<String> dropoffAddresses = ['Adresse de livraison'];
  String get dropoffAddress => dropoffAddresses.last;
  set dropoffAddress(String value) =>
      dropoffAddresses[dropoffAddresses.length - 1] = value;
  bool _isReady = false;
  Timer? _splashTimer;
  Timer? _trafficRefreshTimer;

  // Variables pour le trajet
  List<LatLng?> _destinationLocations = [null];
  LatLng? get _destinationLocation => _destinationLocations.last;
  set _destinationLocation(LatLng? value) =>
      _destinationLocations[_destinationLocations.length - 1] = value;
  LatLng? _customPickupLocation;
  List<LatLng> _routePoints = [];
  List<LatLng> _oldRoutePoints = [];
  List<LatLng> _displayedRoutePoints = [];
  bool _isErasing = false;
  AnimationController? _routeAnimationController;
  int _lastRouteCalcId = 0;

  String _estimatedTime = '';
  String _arrivalTime = '';
  String _driverWaitTime =
      ''; // Temps d'approche du livreur calculÃ© dynamiquement
  LatLng _currentLocation = const LatLng(5.359951, -4.008256);

  String _selectedVehicle = 'Moto'; // 'Moto' ou 'Camion'
  double? _baseDurationSeconds; // Stocke la durÃ©e brute envoyÃ©e par Mapbox

  void _updateTimes() {
    if (_baseDurationSeconds == null) return;

    // Le temps de base (Mapbox driving-traffic) est considÃ©rÃ© comme celui d'une voiture
    // La Moto se faufile -> -25% de temps (0.75)
    // Le Camion/Cargo est plus lourd -> +15% de temps (1.15)
    double multiplier = _selectedVehicle == 'Moto' ? 0.75 : 1.15;
    int tripMinutes = ((_baseDurationSeconds! / 60) * multiplier).round();

    _estimatedTime = tripMinutes.toString();

    int waitTime = (tripMinutes / 2.5).round().clamp(3, 12).toInt();
    if (waitTime >= tripMinutes) {
      waitTime = (tripMinutes / 2).floor();
      if (waitTime < 1) waitTime = 1;
    }

    _driverWaitTime = waitTime.toString();

    DateTime arrival =
        DateTime.now().add(Duration(minutes: tripMinutes + waitTime));
    String hour = arrival.hour.toString().padLeft(2, '0');
    String minute = arrival.minute.toString().padLeft(2, '0');
    _arrivalTime = '$hour:$minute';
  }

  // Centre de la vue de la carte (dÃ©calÃ© pour ajuster le marqueur au-dessus du panneau)
  LatLng get _cameraCenter =>
      LatLng(_currentLocation.latitude - 0.0007, _currentLocation.longitude);

  // ContrÃ´leur de la carte flutter_map
  final MapController _mapController = MapController();

  // Jeton Mapbox
  final String _mapboxToken =
      'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A';

  StreamSubscription<Position>? _positionStream;

  // App Links pour intercepter les liens WhatsApp (geo: ou Google Maps)
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();

    // Initialisation du contrÃ´leur d'animation pour le trajet
    _routeAnimationController = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 1000), // DurÃ©e de croissance/effacement
    )..addListener(() {
        if (mounted) {
          setState(() {
            final progress = _routeAnimationController!.value;
            if (_isErasing) {
              // Effacement de la destination vers la source (on garde les premiers points, donc Ã§a rÃ©trÃ©cit)
              int pointsCount = (_oldRoutePoints.length * progress).round();
              if (pointsCount == 0) {
                _displayedRoutePoints = [];
              } else {
                _displayedRoutePoints = _oldRoutePoints.sublist(0, pointsCount);
              }
            } else {
              // Croissance de la source vers la destination
              int pointsCount = (_routePoints.length * progress).round();
              if (pointsCount == 0) {
                _displayedRoutePoints = [];
              } else {
                _displayedRoutePoints = _routePoints.sublist(0, pointsCount);
              }
            }
          });
        }
      });

    _fetchRealLocation();
    _initDeepLinks();

    // DÃ©marre l'actualisation automatique du trafic (toutes les 2 minutes)
    _trafficRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (dropoffAddress != 'Adresse de livraison' &&
          _destinationLocation != null) {
        _calculateRoute();
      }
    });
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Si l'application Ã©tait fermÃ©e et s'ouvre via un lien WhatsApp
    _appLinks.getInitialAppLink().then((uri) {
      if (uri != null) _handleIncomingLink(uri);
    });

    // Si l'application est dÃ©jÃ  ouverte en arriÃ¨re-plan
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
        if (place.street != null && place.street!.isNotEmpty)
          addressParts.add(place.street!);
        if (place.locality != null && place.locality!.isNotEmpty)
          addressParts.add(place.locality!);

        if (addressParts.isNotEmpty) {
          setState(() {
            dropoffAddress = addressParts.join(', ');
          });
          _calculateRoute();
        }
      }
    } catch (e) {
      // Si la rue n'est pas trouvÃ©e, on affiche les coordonnÃ©es GPS
      setState(() {
        dropoffAddress = "Lieu pointÃ© ($lat, $lng)";
      });
    }
  }

  void _consumeRoute(LatLng currentPos) {
    if (_routePoints.isEmpty) return;

    // Trouver le point le plus proche sur le tracÃ© restant
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      double dist = const Distance().distance(_routePoints[i], currentPos);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    // TolÃ©rance : on "coupe" le trajet seulement si on en est proche (ex: < 100 mÃ¨tres)
    // Sinon, cela signifie qu'on a fait un grand dÃ©tour (il faudrait recalculer)
    if (minDistance < 100) {
      setState(() {
        // Supprimer tous les points qu'on a dÃ©jÃ  dÃ©passÃ©s
        _routePoints = _routePoints.sublist(closestIdx);
        // Le tout premier point devient EXACTEMENT la position GPS actuelle (pour fluiditÃ© visuelle)
        if (_routePoints.isNotEmpty) {
          _routePoints[0] = currentPos;
        } else {
          _routePoints.add(currentPos);
        }

        // Mettre Ã  jour l'affichage de la ligne verte
        _displayedRoutePoints = List.from(_routePoints);

        // Mettre Ã  jour le marqueur de dÃ©part fantÃ´me pour le prochain appel Mapbox
        _customPickupLocation = currentPos;
      });

      // On dÃ©place doucement la camÃ©ra pour suivre l'utilisateur tout en gardant
      // le trajet bien visible Ã  l'Ã©cran.
      try {
        _mapController.move(
            LatLng(currentPos.latitude - 0.0007, currentPos.longitude),
            _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  Future<void> _calculateRoute() async {
    if (dropoffAddress == 'Adresse de livraison' || dropoffAddress.isEmpty)
      return;

    if (mounted) {
      setState(() {
        _estimatedTime = ''; // Reset pour afficher "Calcul en cours..."
        _arrivalTime = '';
        _driverWaitTime = '';
      });
    }

    try {
      LatLng? dest = _destinationLocation;
      LatLng? start = _customPickupLocation;

      // Si prise en charge modifiÃ©e mais pas de coordonnÃ©es exactes (ex: via deep link ou saisie manuelle sans selection)
      if (start == null &&
          pickupAddress != 'Position actuelle' &&
          pickupAddress != 'Recherche en cours...') {
        try {
          final geocodeUrl = Uri.parse(
              'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(pickupAddress)}.json?access_token=$_mapboxToken&country=CI&proximity=${_currentLocation.longitude},${_currentLocation.latitude}&limit=1');
          final geoResponse = await http.get(geocodeUrl);
          if (geoResponse.statusCode == 200) {
            final geoData = json.decode(geoResponse.body);
            if (geoData['features'] != null && geoData['features'].isNotEmpty) {
              final coords = geoData['features'][0]['center'];
              start = LatLng(coords[1], coords[0]);
            }
          }
        } catch (e) {
          debugPrint('Mapbox geocoding error for pickup: $e');
        }
      }

      start ??= _currentLocation; // Fallback sur la position GPS rÃ©elle

      List<LatLng> validDestinations =
          _destinationLocations.whereType<LatLng>().toList();

      // Essai 1 : Mapbox Geocoding pour la destination (plus fiable pour la Côte d'Ivoire souvent)
      if (validDestinations.isEmpty && dest == null) {
        try {
          final geocodeUrl = Uri.parse(
              'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(dropoffAddress)}.json?access_token=$_mapboxToken&country=CI&proximity=${_currentLocation.longitude},${_currentLocation.latitude}&limit=1');
          final geoResponse = await http.get(geocodeUrl);
          if (geoResponse.statusCode == 200) {
            final geoData = json.decode(geoResponse.body);
            if (geoData['features'] != null && geoData['features'].isNotEmpty) {
              final coords = geoData['features'][0]['center'];
              dest = LatLng(coords[1], coords[0]);
              validDestinations.add(dest);
            }
          }
        } catch (e) {
          debugPrint('Mapbox geocoding error: $e');
        }
      }

      // Essai 2 : geocoding package (natif) si Mapbox échoue
      if (validDestinations.isEmpty && dest == null) {
        try {
          List<Location> locations = await locationFromAddress(dropoffAddress);
          if (locations.isNotEmpty) {
            dest = LatLng(locations.first.latitude, locations.first.longitude);
            validDestinations.add(dest);
          }
        } catch (e) {
          debugPrint('Native geocoding error: $e');
        }
      }

      if (validDestinations.isNotEmpty) {
        if (mounted) {
          setState(() {
            _destinationLocations[_destinationLocations.length - 1] =
                validDestinations.last;
            _customPickupLocation = start; // Met en cache si geocodé
          });
        }

        // Construire la chaîne de coordonnées
        String coordsStr = '${start.longitude},${start.latitude}';
        for (var location in validDestinations) {
          coordsStr += ';${location.longitude},${location.latitude}';
        }

        // Utilisation de l'API Mapbox Directions avec le profil "driving-traffic"
        final url = Uri.parse(
            'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
            '$coordsStr'
            '?overview=full&geometries=geojson&access_token=$_mapboxToken');

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 'Ok' &&
              data['routes'] != null &&
              data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            final geometry = route['geometry'];
            final durationSeconds = route['duration'];

            List<LatLng> points = [];
            for (var coord in geometry['coordinates']) {
              points.add(
                  LatLng(coord[1], coord[0])); // [lon, lat] -> LatLng(lat, lon)
            }
            if (points.isNotEmpty) {
              points.insert(0, start);
              points.add(validDestinations.last);
            }

            if (mounted) {
              final currentCalcId = DateTime.now().millisecondsSinceEpoch;
              _lastRouteCalcId = currentCalcId;

              // Arrêter toute animation en cours pour éviter les conflits
              _routeAnimationController?.stop();

              if (_displayedRoutePoints.isNotEmpty) {
                setState(() {
                  _oldRoutePoints = List.from(_displayedRoutePoints);
                  _routePoints = points;
                  _isErasing = true;
                });

                // On efface, puis on dessine seulement si c'est toujours le même calcul
                _routeAnimationController?.reverse(from: 1.0).then((_) {
                  if (mounted && _lastRouteCalcId == currentCalcId) {
                    setState(() {
                      _isErasing = false;
                    });
                    _routeAnimationController?.forward(from: 0.0);
                  }
                });
              } else {
                setState(() {
                  _routePoints = points;
                  _isErasing = false;
                });
                _routeAnimationController?.forward(from: 0.0);
              }

              setState(() {
                _baseDurationSeconds = (durationSeconds as num).toDouble();
                _updateTimes();
              });

              // Cadrer la carte sur l'ensemble du trajet pour le rendre visible, tout en Ã©vitant le panneau infÃ©rieur
              try {
                final bounds = LatLngBounds.fromPoints(points);
                _mapController.fitCamera(CameraFit.bounds(
                  bounds: bounds,
                  padding: EdgeInsets.only(
                    top: 160.0,
                    left: 80.0,
                    right: 80.0,
                    bottom: MediaQuery.of(context).size.height *
                        0.55, // Garde une marge importante au-dessus du panneau
                  ),
                ));
              } catch (_) {}
            }
          } else {
            if (mounted)
              setState(() {
                _estimatedTime = "N/A";
                _arrivalTime = "";
              });
          }
        } else {
          if (mounted) {
            String errMsg = "Err ${response.statusCode}";
            try {
              final errBody = json.decode(response.body);
              if (errBody['code'] == 'NoRoute') {
                errMsg = "Impossible";
              }
            } catch (_) {}

            setState(() {
              _estimatedTime = errMsg;
              _arrivalTime = "";
            });
            debugPrint(
                'Routing API Error: ${response.statusCode} - ${response.body}');
          }
        }
      } else {
        if (mounted)
          setState(() {
            _estimatedTime = "Introuvable";
            _arrivalTime = "";
          });
      }
    } catch (e) {
      debugPrint('Erreur lors du calcul du trajet : $e');
      if (mounted)
        setState(() {
          _estimatedTime = "Erreur";
          _arrivalTime = "";
        });
    }
  }

  void _hideSplashScreen() {
    if (_isReady) return;
    _splashTimer?.cancel();
    // On donne 3.5 secondes Ã  la carte pour charger ses tuiles en arriÃ¨re-plan
    // au nouvel emplacement avant de faire disparaÃ®tre l'Ã©cran
    _splashTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) setState(() => _isReady = true);
    });
  }

  Future<void> _updateAddress(double lat, double lon) async {
    if (_customPickupLocation != null)
      return; // Ne pas Ã©craser l'adresse si l'utilisateur a choisi un point prÃ©cis

    try {
      var placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        var place = placemarks.first;
        if (mounted) {
          String addressName = place.street?.isNotEmpty == true
              ? place.street!
              : 'Position Inconnue';
          if (addressName.contains(',')) {
            addressName = addressName.split(',').first.trim();
          }
          if ((addressName.contains('+') && addressName.length <= 15) ||
              addressName.toLowerCase().contains('unnamed')) {
            addressName = 'Position actuelle';
          }
          setState(() {
            pickupAddress = addressName;
            // IMPORTANT: Toujours lier l'adresse textuelle à la coordonnée GPS exacte
            // pour éviter que _calculateRoute ne refasse une recherche texte imprécise
            _customPickupLocation = LatLng(lat, lon);
          });

          if (addressName != 'Position actuelle' &&
              addressName != 'Position Inconnue' &&
              addressName != 'Recherche en cours...') {
            _saveToRecentSearchesFromGPS(
                addressName, place.locality ?? 'Abidjan', lat, lon);
          }
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

  Future<void> _saveToRecentSearchesFromGPS(
      String text, String placeName, double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recentJson = prefs.getString('recent_searches');
    List<Map<String, dynamic>> recentSearches = [];
    if (recentJson != null) {
      try {
        final List<dynamic> decoded = json.decode(recentJson);
        recentSearches =
            decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {}
    }

    recentSearches.removeWhere((p) => p['text'] == text);
    recentSearches.insert(0, {
      'text': text,
      'place_name': placeName,
      'lat': lat,
      'lng': lng,
    });

    if (recentSearches.length > 6) {
      recentSearches = recentSearches.sublist(0, 6);
    }

    await prefs.setString('recent_searches', json.encode(recentSearches));
  }

  Future<void> _fetchRealLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted)
          setState(() {
            pickupAddress = 'GPS dÃ©sactivÃ©';
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
              pickupAddress = 'Permission refusÃ©e';
            });
          _hideSplashScreen();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted)
          setState(() {
            pickupAddress = 'Permission refusÃ©e';
          });
        _hideSplashScreen();
        return;
      }

      // 1. Charger immÃ©diatement la derniÃ¨re position connue pour une fluiditÃ© instantanÃ©e
      var lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null && mounted) {
        double actualLat = lastPosition.latitude;
        double actualLon = lastPosition.longitude;

        setState(() {
          _currentLocation = LatLng(actualLat, actualLon);
        });

        // DÃ©lai pour s'assurer que le MapController est prÃªt
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _routePoints.isEmpty)
            _mapController.move(_cameraCenter, 17.5);
        });

        _hideSplashScreen(); // DÃ©marre le dÃ©compte pour cacher l'Ã©cran

        // Mettre Ã  jour l'adresse immÃ©diatement sans attendre le GPS prÃ©cis
        _updateAddress(actualLat, actualLon);
      }

      // 2. Affiner avec la position GPS exacte en arriÃ¨re-plan
      var position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 4),
        onTimeout: () => lastPosition ?? Geolocator.getCurrentPosition(),
      );

      if (position != null && mounted) {
        // Mettre Ã  jour seulement si la nouvelle position est diffÃ©rente (optimisation)
        if (lastPosition == null ||
            Geolocator.distanceBetween(
                    lastPosition.latitude,
                    lastPosition.longitude,
                    position.latitude,
                    position.longitude) >
                20) {
          double actualLat = position.latitude;
          double actualLon = position.longitude;

          setState(() {
            _currentLocation = LatLng(actualLat, actualLon);
          });

          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _routePoints.isEmpty)
              _mapController.move(_cameraCenter, 17.5);
          });

          _hideSplashScreen(); // DÃ©marre le dÃ©compte si ce n'Ã©tait pas fait

          _updateAddress(actualLat, actualLon);
        }
      }

      // 3. Ã‰coute continue en arriÃ¨re-plan (Mise Ã  jour en direct comme Yango)
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter:
              15, // Mise Ã  jour tous les 15 mÃ¨tres de dÃ©placement
        ),
      ).listen((Position newPosition) {
        if (mounted) {
          // Si on est sur l'Ã©mulateur en Californie (USA), on force Abidjan pour les tests
          double actualLat = newPosition.latitude;
          double actualLon = newPosition.longitude;

          LatLng newPos = LatLng(actualLat, actualLon);

          setState(() {
            _currentLocation = newPos;
          });

          // La carte suit automatiquement le dÃ©placement de l'utilisateur si aucun trajet n'est affichÃ©
          try {
            if (_routePoints.isEmpty) {
              _mapController.move(_cameraCenter, _mapController.camera.zoom);
            } else if (pickupAddress == 'Position actuelle' ||
                _customPickupLocation == null) {
              // "Bouffer" dynamiquement le trajet au fur et Ã  mesure que l'utilisateur avance
              _consumeRoute(newPos);
            }
          } catch (_) {
            // SÃ©curitÃ© au cas oÃ¹ la carte ne serait pas encore totalement affichÃ©e
          }

          if (_routePoints.isEmpty) {
            _updateAddress(actualLat, actualLon);
          }
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
    _routeAnimationController?.dispose();
    _splashTimer?.cancel();
    _trafficRefreshTimer?.cancel();
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
          // 0. Grille de chargement en arriÃ¨re-plan (Style Yango)
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF7F7F7), // Fond trÃ¨s clair
              child: GridPaper(
                color: Colors.black.withOpacity(0.04), // Lignes trÃ¨s subtiles
                interval: 20, // Petits carreaux
                divisions: 1,
                subdivisions: 1,
              ),
            ),
          ),

          // 1. La Carte (En fond avec flutter_map et Mapbox Data)
          FlutterMap(
            key: const ValueKey('delivery_main_map_fixed'),
            mapController: _mapController,
            options: MapOptions(
              backgroundColor:
                  Colors.transparent, // Laisse apparaÃ®tre la grille en dessous
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
                keepBuffer:
                    8, // AugmentÃ© Ã  8 pour garder les tuiles en cache mÃ©moire (Ã©vite le flash)
                additionalOptions: const {
                  'accessToken':
                      'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A',
                },
              ),
              PolylineLayer(
                polylines: [
                  if (_displayedRoutePoints.isNotEmpty)
                    Polyline(
                      points: _displayedRoutePoints,
                      color: const Color(0xFF00C853), // Vert Yango
                      strokeWidth: 5.0,
                      strokeCap: StrokeCap.butt,
                      strokeJoin: StrokeJoin.round,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (var dest in _destinationLocations.whereType<LatLng>())
                    Marker(
                      point: dest,
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black54, width: 6),
                        ),
                      ),
                    ),
                  Marker(
                    point: _customPickupLocation ?? _currentLocation,
                    width: 90,
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Grand halo transparent (uniquement si pas de trajet)
                        if (_routePoints.isEmpty)
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
                          width: _routePoints.isEmpty ? 24 : 18,
                          height: _routePoints.isEmpty ? 24 : 18,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF94B2E),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white,
                                width: _routePoints.isEmpty ? 2 : 4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                        ),
                        // FlÃ¨che blanche (uniquement si pas de trajet)
                        if (_routePoints.isEmpty)
                          Transform.translate(
                            offset: const Offset(3, -3),
                            child: Transform.rotate(
                              angle: -0.785398, // -45 degrÃ©s
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
                        // Bulle de temps estimé
                        if (_driverWaitTime.isNotEmpty)
                          Positioned(
                            top: _routePoints.isEmpty
                                ? 0
                                : 5, // Ajusté pour qu'il soit bien collé
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF94B2E),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 4)
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_driverWaitTime,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          height: 1.1)),
                                  const Text('min',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          height: 1.1)),
                                ],
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

          // 2. Ã‰lÃ©ments par dessus la carte
          // En-tÃªte (Voiture / Plus)
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

          // Bouton Retour temporairement masquÃ©
          /*
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
                onPressed: () {
                  // Action de retour temporairement commentÃ©e
                  // Navigator.of(context).pop();
                },
              ),
            ),
          ),
          */

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
                  // Petite animation de "bump" (secousse) pour donner un retour visuel
                  final currentCenter = _mapController.camera.center;
                  final currentZoom = _mapController.camera.zoom;

                  // 1. DÃ©placement trÃ¨s lÃ©ger vers le haut instantanÃ©ment
                  _mapController.move(
                      LatLng(currentCenter.latitude + 0.0003,
                          currentCenter.longitude),
                      currentZoom);

                  // 2. Retour rapide Ã  la position de base exacte aprÃ¨s 100 millisecondes
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _mapController.move(currentCenter, currentZoom);

                    // Mettre Ã  jour l'itinÃ©raire et le trafic en temps rÃ©el
                    if (dropoffAddress != 'Adresse de livraison') {
                      _calculateRoute();
                    }
                  });
                },
              ),
            ),
          ),

          // 3. Panneau de commande (Bottom Sheet)
          DraggableScrollableSheet(
            initialChildSize: 0.51,
            minChildSize: 0.51, // BloquÃ© en bas pour garantir la visibilitÃ©
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
                            // Handle (PoignÃ©e)
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
                                        PageRouteBuilder(
                                          opaque:
                                              false, // EmpÃªche Flutter de dÃ©truire la carte en dessous
                                          pageBuilder: (context, animation,
                                                  secondaryAnimation) =>
                                              AddressSelectionScreen(
                                            isSelectingDestination: false,
                                            initialPickupAddress: pickupAddress,
                                            initialDropoffAddress:
                                                dropoffAddress,
                                          ),
                                        ),
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

                                          // Si les coordonnÃ©es exactes sont retournÃ©es
                                          if (result['dropoffLat'] != null &&
                                              result['dropoffLng'] != null) {
                                            _destinationLocation = LatLng(
                                                result['dropoffLat'],
                                                result['dropoffLng']);
                                          }
                                          if (result['pickupLat'] != null &&
                                              result['pickupLng'] != null) {
                                            _customPickupLocation = LatLng(
                                                result['pickupLat'],
                                                result['pickupLng']);
                                          }
                                        });
                                        _calculateRoute();
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
                                        PageRouteBuilder(
                                          opaque:
                                              false, // EmpÃªche Flutter de dÃ©truire la carte en dessous
                                          pageBuilder: (context, animation,
                                                  secondaryAnimation) =>
                                              AddressSelectionScreen(
                                            isSelectingDestination: true,
                                            initialPickupAddress: pickupAddress,
                                            initialDropoffAddress:
                                                dropoffAddress,
                                          ),
                                        ),
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

                                          // Si les coordonnÃ©es exactes sont retournÃ©es
                                          if (result['dropoffLat'] != null &&
                                              result['dropoffLng'] != null) {
                                            _destinationLocation = LatLng(
                                                result['dropoffLat'],
                                                result['dropoffLng']);
                                          }
                                          if (result['pickupLat'] != null &&
                                              result['pickupLng'] != null) {
                                            _customPickupLocation = LatLng(
                                                result['pickupLat'],
                                                result['pickupLng']);
                                          }
                                        });
                                        _calculateRoute();
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
                                                Text(
                                                    _estimatedTime.isNotEmpty
                                                        ? '≈$_estimatedTime min. · arrivée à $_arrivalTime'
                                                        : 'Calcul en cours...',
                                                    style: const TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 12)),
                                              Text(
                                                dropoffAddresses.join(' ➔ '),
                                                style: TextStyle(
                                                    fontSize: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? 14
                                                        : 14, // Slightly smaller to fit multiple
                                                    color: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? Colors.grey.shade600
                                                        : Colors.black87,
                                                    fontWeight: dropoffAddress ==
                                                            'Adresse de livraison'
                                                        ? FontWeight.normal
                                                        : FontWeight.w500),
                                                maxLines: 2,
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

                            // VÃ©hicules
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (_selectedVehicle == 'Moto') return;
                                      setState(() {
                                        _selectedVehicle = 'Moto';
                                      });
                                      _calculateRoute(); // Reprend le calcul
                                    },
                                    child: _buildVehicleOption(
                                        'Moto',
                                        _baseDurationSeconds != null
                                            ? '${((_baseDurationSeconds! / 60) * 0.75).round()} min.'
                                            : '...',
                                        'Express',
                                        _selectedVehicle == 'Moto'),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      if (_selectedVehicle == 'Camion') return;
                                      setState(() {
                                        _selectedVehicle = 'Camion';
                                      });
                                      _calculateRoute(); // Reprend le calcul
                                    },
                                    child: _buildVehicleOption(
                                        'Camion',
                                        _baseDurationSeconds != null
                                            ? '${((_baseDurationSeconds! / 60) * 1.15).round()} min.'
                                            : '...',
                                        'Express Cargo',
                                        _selectedVehicle == 'Camion'),
                                  ),
                                ],
                              ),
                            ),
                            // SizedBox final supprimÃ© pour retirer l'espace vide
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
                            // 1. BanniÃ¨re inter-villes
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
                                      onPressed: () {
                                        if (_baseDurationSeconds == null)
                                          return;
                                        double multiplier =
                                            _selectedVehicle == 'Moto'
                                                ? 0.75
                                                : 1.15;
                                        int tripMinutes =
                                            ((_baseDurationSeconds! / 60) *
                                                    multiplier)
                                                .round();
                                        showModalBottomSheet(
                                            context: context,
                                            isScrollControlled: true,
                                            useSafeArea: true,
                                            backgroundColor: Colors.transparent,
                                            builder: (context) =>
                                                OfferSelectionBottomSheet(
                                                    selectedVehicle:
                                                        _selectedVehicle,
                                                    tripMinutes: tripMinutes,
                                                    pickupAddress:
                                                        pickupAddress,
                                                    dropoffAddresses:
                                                        dropoffAddresses,
                                                    onAddStop:
                                                        (address, lat, lng) {
                                                      setState(() {
                                                        dropoffAddresses
                                                            .add(address);
                                                        _destinationLocations
                                                            .add(lat != null &&
                                                                    lng != null
                                                                ? LatLng(
                                                                    lat, lng)
                                                                : null);
                                                      });
                                                      _calculateRoute();
                                                    },
                                                    onRemoveStop: (index) {
                                                      setState(() {
                                                        dropoffAddresses.removeAt(index);
                                                        _destinationLocations.removeAt(index);
                                                      });
                                                      _calculateRoute();
                                                    },
                                                ));
                                      },
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
                // 0xFE au lieu de 0xFF (99% opaque) pour forcer Flutter Ã  dessiner la carte en dessous
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
