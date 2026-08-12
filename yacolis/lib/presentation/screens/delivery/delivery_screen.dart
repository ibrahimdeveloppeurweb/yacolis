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

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> with TickerProviderStateMixin {
  // Variables d'état pour les adresses
  String pickupAddress = 'Recherche en cours...';
  String dropoffAddress = 'Adresse de livraison';
  bool _isReady = false;
  Timer? _splashTimer;
  Timer? _trafficRefreshTimer;

  // Variables pour le trajet
  LatLng? _destinationLocation;
  LatLng? _customPickupLocation;
  List<LatLng> _routePoints = [];
  List<LatLng> _oldRoutePoints = [];
  List<LatLng> _displayedRoutePoints = [];
  bool _isErasing = false;
  AnimationController? _routeAnimationController;
  
  String _estimatedTime = '';
  String _arrivalTime = '';
  String _driverWaitTime = ''; // Temps d'approche du livreur calculé dynamiquement
  LatLng _currentLocation = const LatLng(5.359951, -4.008256);

  // Centre de la vue de la carte (décalé pour ajuster le marqueur au-dessus du panneau)
  LatLng get _cameraCenter =>
      LatLng(_currentLocation.latitude - 0.0007, _currentLocation.longitude);

  // Contrôleur de la carte flutter_map
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
    
    // Initialisation du contrôleur d'animation pour le trajet
    _routeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // Durée de croissance/effacement
    )..addListener(() {
        if (mounted) {
          setState(() {
            final progress = _routeAnimationController!.value;
            if (_isErasing) {
              // Effacement de la destination vers la source (on garde les premiers points, donc ça rétrécit)
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
    
    // Démarre l'actualisation automatique du trafic (toutes les 2 minutes)
    _trafficRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (dropoffAddress != 'Adresse de livraison' && _destinationLocation != null) {
        _calculateRoute();
      }
    });
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
          _calculateRoute();
        }
      }
    } catch (e) {
      // Si la rue n'est pas trouvée, on affiche les coordonnées GPS
      setState(() {
        dropoffAddress = "Lieu pointé ($lat, $lng)";
      });
    }
  }

  Future<void> _calculateRoute() async {
    if (dropoffAddress == 'Adresse de livraison' || dropoffAddress.isEmpty) return;

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
      
      // Si prise en charge modifiée mais pas de coordonnées exactes (ex: via deep link ou saisie manuelle sans selection)
      if (start == null && pickupAddress != 'Position actuelle' && pickupAddress != 'Recherche en cours...') {
        try {
          final geocodeUrl = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(pickupAddress)}.json?access_token=$_mapboxToken&country=CI&limit=1');
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
      
      start ??= _currentLocation; // Fallback sur la position GPS réelle
      
      // Essai 1 : Mapbox Geocoding pour la destination (plus fiable pour la Côte d'Ivoire souvent)
      if (dest == null) {
        try {
          final geocodeUrl = Uri.parse('https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(dropoffAddress)}.json?access_token=$_mapboxToken&country=CI&limit=1');
          final geoResponse = await http.get(geocodeUrl);
          if (geoResponse.statusCode == 200) {
            final geoData = json.decode(geoResponse.body);
            if (geoData['features'] != null && geoData['features'].isNotEmpty) {
              final coords = geoData['features'][0]['center'];
              dest = LatLng(coords[1], coords[0]);
            }
          }
        } catch (e) {
          debugPrint('Mapbox geocoding error: $e');
        }
      }

      // Essai 2 : geocoding package (natif) si Mapbox échoue
      if (dest == null) {
        try {
          List<Location> locations = await locationFromAddress(dropoffAddress);
          if (locations.isNotEmpty) {
            dest = LatLng(locations.first.latitude, locations.first.longitude);
          }
        } catch (e) {
          debugPrint('Native geocoding error: $e');
        }
      }

      if (dest != null) {
        if (mounted) {
          setState(() {
            _destinationLocation = dest;
            _customPickupLocation = start; // Met en cache si geocodé
          });
        }

        // Utilisation de l'API Mapbox Directions avec le profil "driving-traffic" pour obtenir 
        // l'itinéraire en tenant compte des bouchons et du trafic en temps réel.
        final url = Uri.parse(
            'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
            '${start.longitude},${start.latitude};'
            '${dest.longitude},${dest.latitude}'
            '?overview=full&geometries=geojson&access_token=$_mapboxToken');

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            final geometry = route['geometry'];
            final durationSeconds = route['duration'];

            List<LatLng> points = [];
            for (var coord in geometry['coordinates']) {
              points.add(LatLng(coord[1], coord[0])); // [lon, lat] -> LatLng(lat, lon)
            }
            if (points.isNotEmpty) {
              // 1. Isoler la partie de la route qui concerne notre trajet
              int closestStartIdx = 0;
              double minStartDist = double.infinity;
              for (int i = 0; i < points.length; i++) {
                double dist = const Distance().distance(points[i], start);
                if (dist < minStartDist) {
                  minStartDist = dist;
                  closestStartIdx = i;
                }
              }

              int closestDestIdx = 0;
              double minDestDist = double.infinity;
              for (int i = 0; i < points.length; i++) {
                double dist = const Distance().distance(points[i], dest!);
                if (dist < minDestDist) {
                  minDestDist = dist;
                  closestDestIdx = i;
                }
              }

              if (closestStartIdx <= closestDestIdx) {
                points = points.sublist(closestStartIdx, closestDestIdx + 1);
              } else {
                points = [];
              }

              // 2. Supprimer agressivement tout débordement (overshoot) aux extrémités
              if (points.isNotEmpty) {
                double totalDist = const Distance().distance(start, dest!);
                
                // Nettoyer la fin (si la route continue après l'arrivée)
                while (points.isNotEmpty) {
                  double distFromStart = const Distance().distance(start, points.last);
                  // Si le point est plus loin du départ que ne l'est la destination, on le supprime (avec une marge de tolérance de 20m pour les courbes)
                  if (distFromStart > totalDist + 20) {
                    points.removeLast();
                  } else {
                    break;
                  }
                }
                
                // Nettoyer le début (si la route a commencé trop loin en arrière)
                while (points.isNotEmpty) {
                  double distFromDest = const Distance().distance(dest!, points.first);
                  if (distFromDest > totalDist + 20) {
                    points.removeAt(0);
                  } else {
                    break;
                  }
                }
              }

              // 3. Forcer la connexion exacte au centre des marqueurs
              points.insert(0, start);
              points.add(dest!);
            }

            if (mounted) {
              // S'il y a déjà un trajet d'affiché, on lance l'animation d'effacement
              if (_displayedRoutePoints.isNotEmpty) {
                setState(() {
                  _oldRoutePoints = List.from(_displayedRoutePoints);
                  _routePoints = points;
                  _isErasing = true;
                });
                
                // On efface, puis on dessine
                _routeAnimationController?.reverse(from: 1.0).then((_) {
                  if (mounted) {
                    setState(() {
                      _isErasing = false;
                    });
                    _routeAnimationController?.forward(from: 0.0);
                  }
                });
              } else {
                // S'il n'y a pas d'ancien trajet, on dessine directement le nouveau
                setState(() {
                  _routePoints = points;
                  _isErasing = false;
                });
                _routeAnimationController?.forward(from: 0.0);
              }
              
              setState(() {
                int tripMinutes = (durationSeconds / 60).round();
                _estimatedTime = tripMinutes.toString();
                
                // Calcul dynamique du temps d'approche du livreur pour ne pas être statique
                // On prend environ un tiers/moitié du temps de trajet, entre 3 et 12 minutes
                int waitTime = (tripMinutes / 2.5).round().clamp(3, 12).toInt();
                
                // On garantit absolument que le temps de la carte soit inférieur au temps de destination
                if (waitTime >= tripMinutes) {
                  waitTime = (tripMinutes / 2).floor();
                  if (waitTime < 1) waitTime = 1;
                }
                
                _driverWaitTime = waitTime.toString();
                
                DateTime arrival = DateTime.now().add(Duration(minutes: tripMinutes + waitTime));
                String hour = arrival.hour.toString().padLeft(2, '0');
                String minute = arrival.minute.toString().padLeft(2, '0');
                _arrivalTime = '$hour:$minute';
              });
              
              // Cadrer la carte sur l'ensemble du trajet pour le rendre visible, tout en évitant le panneau inférieur
              try {
                final bounds = LatLngBounds.fromPoints(points);
                _mapController.fitCamera(CameraFit.bounds(
                  bounds: bounds,
                  padding: EdgeInsets.only(
                    top: 160.0,
                    left: 80.0,
                    right: 80.0,
                    bottom: MediaQuery.of(context).size.height * 0.55, // Garde une marge importante au-dessus du panneau
                  ),
                ));
              } catch (_) {}
            }
          } else {
             if (mounted) setState(() { 
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
             debugPrint('Routing API Error: ${response.statusCode} - ${response.body}');
           }
        }
      } else {
         if (mounted) setState(() { 
          _estimatedTime = "Introuvable";
          _arrivalTime = "";
        });
      }
    } catch (e) {
      debugPrint('Erreur lors du calcul du trajet : $e');
      if (mounted) setState(() { 
        _estimatedTime = "Erreur";
        _arrivalTime = "";
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
    if (_customPickupLocation != null) return; // Ne pas écraser l'adresse si l'utilisateur a choisi un point précis

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
          });
          
          if (addressName != 'Position actuelle' && addressName != 'Position Inconnue' && addressName != 'Recherche en cours...') {
            _saveToRecentSearchesFromGPS(addressName, place.locality ?? 'Abidjan', lat, lon);
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

  Future<void> _saveToRecentSearchesFromGPS(String text, String placeName, double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    final String? recentJson = prefs.getString('recent_searches');
    List<Map<String, dynamic>> recentSearches = [];
    if (recentJson != null) {
      try {
        final List<dynamic> decoded = json.decode(recentJson);
        recentSearches = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
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
        double actualLat = lastPosition.latitude;
        double actualLon = lastPosition.longitude;
        
        setState(() {
          _currentLocation = LatLng(actualLat, actualLon);
        });

        // Délai pour s'assurer que le MapController est prêt
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _routePoints.isEmpty) _mapController.move(_cameraCenter, 17.5);
        });

        _hideSplashScreen(); // Démarre le décompte pour cacher l'écran

        // Mettre à jour l'adresse immédiatement sans attendre le GPS précis
        _updateAddress(actualLat, actualLon);
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
          double actualLat = position.latitude;
          double actualLon = position.longitude;
          
          setState(() {
            _currentLocation = LatLng(actualLat, actualLon);
          });

          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _routePoints.isEmpty) _mapController.move(_cameraCenter, 17.5);
          });

          _hideSplashScreen(); // Démarre le décompte si ce n'était pas fait
          
          _updateAddress(actualLat, actualLon);
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
          // Si on est sur l'émulateur en Californie (USA), on force Abidjan pour les tests
          double actualLat = newPosition.latitude;
          double actualLon = newPosition.longitude;
          
          setState(() {
            _currentLocation = LatLng(actualLat, actualLon);
          });
          
          // La carte suit automatiquement le déplacement de l'utilisateur si aucun trajet n'est affiché
          try {
            if (_routePoints.isEmpty) {
              _mapController.move(_cameraCenter, _mapController.camera.zoom);
            }
          } catch (_) {
            // Sécurité au cas où la carte ne serait pas encore totalement affichée
          }

          _updateAddress(actualLat, actualLon);
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
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
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
                            border: Border.all(color: Colors.white, width: _routePoints.isEmpty ? 2 : 4),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                        ),
                        // Flèche blanche (uniquement si pas de trajet)
                        if (_routePoints.isEmpty)
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
                        // Bulle de temps estimé
                        if (_driverWaitTime.isNotEmpty)
                          Positioned(
                            top: _routePoints.isEmpty ? 0 : 5, // Ajusté pour qu'il soit bien collé
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF94B2E),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_driverWaitTime, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.1)),
                                  const Text('min', style: TextStyle(color: Colors.white, fontSize: 10, height: 1.1)),
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

          // Bouton Retour temporairement masqué
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
                  // Action de retour temporairement commentée
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
                  
                  // 1. Déplacement très léger vers le haut instantanément
                  _mapController.move(
                    LatLng(currentCenter.latitude + 0.0003, currentCenter.longitude), 
                    currentZoom
                  );
                  
                  // 2. Retour rapide à la position de base exacte après 100 millisecondes
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _mapController.move(currentCenter, currentZoom);
                    
                    // Mettre à jour l'itinéraire et le trafic en temps réel
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
                                            
                                          // Si les coordonnées exactes sont retournées
                                          if (result['dropoffLat'] != null && result['dropoffLng'] != null) {
                                            _destinationLocation = LatLng(result['dropoffLat'], result['dropoffLng']);
                                          }
                                          if (result['pickupLat'] != null && result['pickupLng'] != null) {
                                            _customPickupLocation = LatLng(result['pickupLat'], result['pickupLng']);
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
                                            
                                          // Si les coordonnées exactes sont retournées
                                          if (result['dropoffLat'] != null && result['dropoffLng'] != null) {
                                            _destinationLocation = LatLng(result['dropoffLat'], result['dropoffLng']);
                                          }
                                          if (result['pickupLat'] != null && result['pickupLng'] != null) {
                                            _customPickupLocation = LatLng(result['pickupLat'], result['pickupLng']);
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
