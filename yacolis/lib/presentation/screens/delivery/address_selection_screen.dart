import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';

class AddressSelectionScreen extends StatefulWidget {
  final bool isSelectingDestination;
  final String initialPickupAddress;
  final String initialDropoffAddress;

  const AddressSelectionScreen({
    super.key,
    this.isSelectingDestination = true,
    this.initialPickupAddress = '',
    this.initialDropoffAddress = '',
  });

  @override
  State<AddressSelectionScreen> createState() => _AddressSelectionScreenState();
}

class _AddressSelectionScreenState extends State<AddressSelectionScreen> {
  late TextEditingController _departureController;
  late TextEditingController _destinationController;
  late FocusNode _departureFocus;
  late FocusNode _destinationFocus;
  bool _isLoadingLocation = false;

  // Mapbox Autocomplete
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _recentSearches = [];
  Timer? _debounce;
  bool _isSearching = false;
  final String _googleApiKey = 'AIzaSyAFsfPw7h8v6horSQZG-noLv5ddNndF4xc';

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _departureController = TextEditingController(
        text: widget.initialPickupAddress.isNotEmpty
            ? widget.initialPickupAddress
            : 'Position actuelle');
    String destText = widget.initialDropoffAddress == 'Adresse de livraison'
        ? ''
        : widget.initialDropoffAddress;
    _destinationController = TextEditingController(text: destText);
    _departureFocus = FocusNode();
    _destinationFocus = FocusNode();

    _departureController.addListener(() {
      if (_departureFocus.hasFocus) _onSearchChanged(_departureController.text);
    });
    _destinationController.addListener(() {
      if (_destinationFocus.hasFocus)
        _onSearchChanged(_destinationController.text);
    });

    if (widget.isSelectingDestination) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _destinationFocus.requestFocus();
      });
    } else {
      Future.delayed(const Duration(milliseconds: 100), () {
        _departureFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _departureController.dispose();
    _destinationController.dispose();
    _departureFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  double? _selectedPickupLat;
  double? _selectedPickupLng;
  double? _selectedDropoffLat;
  double? _selectedDropoffLng;

  Future<void> _onSuggestionSelected(String text, {String? placeName, String? placeId, double? passedLat, double? passedLng}) async {
    double? lat = passedLat;
    double? lng = passedLng;

    if (placeId != null && placeId.isNotEmpty && lat == null && lng == null) {
      // Afficher un indicateur de chargement si nécessaire
      try {
        final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry&key=$_googleApiKey');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK') {
            final location = data['result']['geometry']['location'];
            lat = location['lat'];
            lng = location['lng'];
          }
        }
      } catch (e) {
        debugPrint('Erreur lors de la récupération des détails du lieu: $e');
      }
    }

    if (_departureFocus.hasFocus) {
      _departureController.text = text;
      _selectedPickupLat = lat;
      _selectedPickupLng = lng;
      if (_selectedPickupLat != null && _selectedPickupLng != null) {
        _saveToRecentSearches({
          'text': text,
          'place_name': placeName ?? '',
          'place_id': placeId,
          'lat': _selectedPickupLat,
          'lng': _selectedPickupLng,
        });
      }

      if (_destinationController.text.isEmpty ||
          _destinationController.text == 'Adresse de livraison') {
        _departureFocus.unfocus();
        _destinationFocus.requestFocus();
        setState(() {
          _searchResults = [];
        });
      } else {
        Navigator.pop(context, {
          'pickup': _departureController.text,
          'dropoff': _destinationController.text,
          if (_selectedPickupLat != null && _selectedPickupLng != null) 'pickupLat': _selectedPickupLat,
          if (_selectedPickupLat != null && _selectedPickupLng != null) 'pickupLng': _selectedPickupLng,
          if (_selectedDropoffLat != null && _selectedDropoffLng != null) 'dropoffLat': _selectedDropoffLat,
          if (_selectedDropoffLat != null && _selectedDropoffLng != null) 'dropoffLng': _selectedDropoffLng,
        });
      }
    } else if (_destinationFocus.hasFocus) {
      _destinationController.text = text;
      _selectedDropoffLat = lat;
      _selectedDropoffLng = lng;

      if (_selectedDropoffLat != null && _selectedDropoffLng != null) {
        _saveToRecentSearches({
          'text': text,
          'place_name': placeName ?? '',
          'place_id': placeId,
          'lat': _selectedDropoffLat,
          'lng': _selectedDropoffLng,
        });
      }

      if (_departureController.text.isEmpty ||
          _departureController.text == 'Position actuelle') {
        _destinationFocus.unfocus();
        _departureFocus.requestFocus();
        setState(() {
          _searchResults = [];
        });
      } else {
        Navigator.pop(context, {
          'pickup': _departureController.text,
          'dropoff': _destinationController.text,
          if (_selectedPickupLat != null && _selectedPickupLng != null) 'pickupLat': _selectedPickupLat,
          if (_selectedPickupLat != null && _selectedPickupLng != null) 'pickupLng': _selectedPickupLng,
          if (_selectedDropoffLat != null && _selectedDropoffLat != null) 'dropoffLat': _selectedDropoffLat,
          if (_selectedDropoffLng != null && _selectedDropoffLng != null) 'dropoffLng': _selectedDropoffLng,
        });
      }
    } else {
      Navigator.pop(context, {
        'pickup': _departureController.text,
        'dropoff': _destinationController.text,
        if (_selectedPickupLat != null) 'pickupLat': _selectedPickupLat,
        if (_selectedPickupLng != null) 'pickupLng': _selectedPickupLng,
        if (_selectedDropoffLat != null) 'dropoffLat': _selectedDropoffLat,
        if (_selectedDropoffLng != null) 'dropoffLng': _selectedDropoffLng,
      });
    }
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recentJson = prefs.getString('recent_searches');
    if (recentJson != null) {
      try {
        final List<dynamic> decoded = json.decode(recentJson);
        setState(() {
          _recentSearches = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } catch (e) {
        debugPrint('Erreur chargement historiques: $e');
      }
    }
  }

  Future<void> _saveToRecentSearches(Map<String, dynamic> place) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Retirer le lieu s'il existe déjà pour le remettre en haut
    _recentSearches.removeWhere((p) => p['text'] == place['text'] || (p['place_id'] != null && p['place_id'] == place['place_id']));
    
    // Ajouter au début
    _recentSearches.insert(0, place);
    
    // Limiter à 6 éléments
    if (_recentSearches.length > 6) {
      _recentSearches = _recentSearches.sublist(0, 6);
    }
    
    await prefs.setString('recent_searches', json.encode(_recentSearches));
    if (mounted) setState(() {});
  }

  IconData _getIconForPlace(String name) {
    name = name.toLowerCase();
    if (name.contains('pharmacie') || name.contains('hopital') || name.contains('clinique') || name.contains('santé')) {
      return Icons.medical_services; // Ressemble à la trousse médicale de la capture
    }
    if (name.contains('restaurant') || name.contains('fast food') || name.contains('maquis')) {
      return Icons.restaurant;
    }
    return Icons.location_on; // Marqueur par défaut pour les lieux classiques
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isSearching = true);
    try {
      // API Google Places Autocomplete (Identique à Yango)
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}&key=$_googleApiKey&components=country:ci&language=fr');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          final predictions = data['predictions'] as List? ?? [];

          final List<Map<String, dynamic>> results = [];
          for (var p in predictions) {
            final description = p['description']?.toString() ?? '';
            final mainText =
                p['structured_formatting']?['main_text']?.toString() ??
                    description;
            String secondaryText =
                p['structured_formatting']?['secondary_text']?.toString() ?? '';

            // Nettoyage : On enlève "Côte d'Ivoire" pour faire plus propre
            secondaryText = secondaryText.replaceAll(', Côte d\'Ivoire', '');
            secondaryText = secondaryText.replaceAll('Côte d\'Ivoire', '');
            secondaryText = secondaryText.trim();
            if (secondaryText.endsWith(',')) {
              secondaryText = secondaryText.substring(0, secondaryText.length - 1);
            }

            results.add({
              'text': mainText,
              'place_name': secondaryText,
              'place_id': p['place_id'],
              'center': [0.0, 0.0],
            });
          }

          setState(() {
            String currentText = _departureFocus.hasFocus 
                ? _departureController.text 
                : _destinationController.text;
                
            if (query == currentText) {
              _searchResults = results;
            } else if (currentText.isEmpty) {
              _searchResults = [];
            }
            _isSearching = false;
          });
        } else {
          // Erreur d'API (ex: clé invalide, quota dépassé)
          setState(() => _isSearching = false);
          if (mounted) {
            String detailedError = data['error_message'] ?? data['status'];
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Erreur Google: $detailedError'),
                duration: const Duration(seconds: 5)));
          }
        }
      } else {
        setState(() => _isSearching = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Accès refusé par le serveur (${response.statusCode})')));
        }
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur de recherche: $e')));
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Les services de localisation sont désactivés.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('La permission de localisation a été refusée.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'La permission de localisation est définitivement refusée.');
      }

      Position position = await Geolocator.getCurrentPosition();

      // Essayer de trouver l'adresse (Reverse Geocoding)
      String locationName = 'Ma position actuelle';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          // Construire une chaîne lisible
          List<String> addressParts = [];
          if (place.street != null && place.street!.isNotEmpty)
            addressParts.add(place.street!);
          if (place.locality != null && place.locality!.isNotEmpty)
            addressParts.add(place.locality!);

          if (addressParts.isNotEmpty) {
            locationName = addressParts.join(', ');
          }
        }
      } catch (e) {
        // En cas d'échec du geocoding, on garde 'Ma position actuelle'
      }

      if (mounted) {
        _onSuggestionSelected(locationName, placeName: 'Position GPS', passedLat: position.latitude, passedLng: position.longitude);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with search fields
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Ligne de Prise en charge
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, top: 16, bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Prise en charge',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              TextField(
                                controller: _departureController,
                                focusNode: _departureFocus,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        // Bouton X
                        IconButton(
                          onPressed: () => _departureController.clear(),
                          icon: const Icon(Icons.close,
                              color: Colors.black54, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        // Bouton Carte
                        GestureDetector(
                          onTap: () {
                            // Valide la sélection actuelle et retourne sur la carte
                            String pickup = _departureController.text;
                            String dropoff = _destinationController.text;
                            
                            if (pickup.isEmpty) pickup = 'Position actuelle';
                            if (dropoff.isEmpty) dropoff = 'Adresse de livraison';
                            
                            Navigator.pop(context, {
                              'pickup': pickup,
                              'dropoff': dropoff
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text('Carte',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Ligne de séparation
                  Padding(
                    padding: const EdgeInsets.only(left: 68, right: 16),
                    child: Divider(
                        height: 1, thickness: 1, color: Colors.grey.shade300),
                  ),

                  // Ligne Destination
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 16, right: 16, top: 8, bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 40,
                          child: Icon(Icons.flag,
                              color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Destination',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              TextField(
                                controller: _destinationController,
                                focusNode: _destinationFocus,
                                decoration: InputDecoration(
                                  hintText: 'Adresse de livraison',
                                  hintStyle:
                                      TextStyle(color: Colors.grey.shade400),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        // Bouton X
                        IconButton(
                          onPressed: () => _destinationController.clear(),
                          icon: const Icon(Icons.close,
                              color: Colors.black54, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        // Bouton Carte
                        GestureDetector(
                          onTap: () {
                            // Valide la sélection actuelle et retourne sur la carte
                            String pickup = _departureController.text;
                            String dropoff = _destinationController.text;
                            
                            if (pickup.isEmpty) pickup = 'Position actuelle';
                            if (dropoff.isEmpty) dropoff = 'Adresse de livraison';
                            
                            Navigator.pop(context, {
                              'pickup': pickup,
                              'dropoff': dropoff,
                              if (_selectedPickupLat != null) 'pickupLat': _selectedPickupLat,
                              if (_selectedPickupLng != null) 'pickupLng': _selectedPickupLng,
                              if (_selectedDropoffLat != null) 'dropoffLat': _selectedDropoffLat,
                              if (_selectedDropoffLng != null) 'dropoffLng': _selectedDropoffLng,
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text('Arrêts',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Liste des suggestions
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.only(top: 16),
                      children: [
                        if (_searchResults.isEmpty) ...[
                          // Votre position
                          ListTile(
                            leading: const Icon(Icons.navigation,
                                color: Colors.black87),
                            title: const Text('Votre position',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            subtitle: const Text(
                                'Prise en charge à l\'emplacement indiqué par les données GPS',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: _isLoadingLocation
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : null,
                            onTap: _isLoadingLocation
                                ? null
                                : () {
                                    _getCurrentLocation();
                                  },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Divider(color: Colors.grey.shade300),
                          ),
                          ..._recentSearches.map((item) => _buildSuggestionItem(
                              item['text'] ?? '',
                              item['place_name'] ?? '',
                              '',
                              () => _onSuggestionSelected(item['text'] ?? '', placeName: item['place_name'] ?? '', placeId: item['place_id']),
                              icon: _getIconForPlace(item['text'] ?? '')
                          )).toList(),
                        ] else ...[
                          // Si recherche en cours, afficher les récents qui correspondent en premier
                          ..._recentSearches
                              .where((item) => (item['text'] ?? '').toLowerCase().contains(
                                  (_departureFocus.hasFocus ? _departureController.text : _destinationController.text).toLowerCase()))
                              .map((item) => _buildSuggestionItem(
                                  item['text'] ?? '',
                                  item['place_name'] ?? '',
                                  '',
                                  () => _onSuggestionSelected(item['text'] ?? '', placeName: item['place_name'] ?? '', placeId: item['place_id']),
                                  icon: _getIconForPlace(item['text'] ?? '')))
                              .toList(),
                          ..._searchResults.map((item) => _buildSuggestionItem(
                              item['text'] ?? '',
                              item['place_name'] ?? '',
                              '',
                              () => _onSuggestionSelected(item['text'] ?? '', placeName: item['place_name'] ?? '', placeId: item['place_id']),
                              icon: Icons.location_on
                          )).toList(),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(
      String title, String subtitle, String distance, VoidCallback onTap, {IconData icon = Icons.location_on}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: Colors.grey.shade400),
          title: Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                color: Colors.lightBlue),
          ),
          subtitle: Text(subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: distance.isNotEmpty
              ? Text(distance,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
              : null,
          onTap: onTap,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, right: 16),
          child: Divider(height: 1, color: Colors.grey.shade300),
        ),
      ],
    );
  }
}
