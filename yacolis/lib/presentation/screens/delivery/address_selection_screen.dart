import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
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
  Timer? _debounce;
  bool _isSearching = false;
  final String _mapboxToken = 'pk.eyJ1IjoiY2lzc2VpYnJhaGltMTk5NSIsImEiOiJjbXNncTJ3eHgwbWV3MnZzMXdnbzNxYjQyIn0.hKyv-YChwmlIwfZNUmiS2A';

  @override
  void initState() {
    super.initState();
    _departureController = TextEditingController(text: widget.initialPickupAddress.isNotEmpty ? widget.initialPickupAddress : 'Position actuelle');
    String destText = widget.initialDropoffAddress == 'Adresse de livraison' ? '' : widget.initialDropoffAddress;
    _destinationController = TextEditingController(text: destText);
    _departureFocus = FocusNode();
    _destinationFocus = FocusNode();
    
    _departureController.addListener(() {
      if (_departureFocus.hasFocus) _onSearchChanged(_departureController.text);
    });
    _destinationController.addListener(() {
      if (_destinationFocus.hasFocus) _onSearchChanged(_destinationController.text);
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

  void _onSuggestionSelected(String text) {
    if (_departureFocus.hasFocus) {
      _departureController.text = text;
      if (_destinationController.text.isEmpty || _destinationController.text == 'Adresse de livraison') {
        _departureFocus.unfocus();
        _destinationFocus.requestFocus();
        setState(() { _searchResults = []; });
      } else {
        Navigator.pop(context, {'pickup': _departureController.text, 'dropoff': _destinationController.text});
      }
    } else if (_destinationFocus.hasFocus) {
      _destinationController.text = text;
      if (_departureController.text.isEmpty || _departureController.text == 'Position actuelle') {
        _destinationFocus.unfocus();
        _departureFocus.requestFocus();
        setState(() { _searchResults = []; });
      } else {
        Navigator.pop(context, {'pickup': _departureController.text, 'dropoff': _destinationController.text});
      }
    } else {
      Navigator.pop(context, {'pickup': _departureController.text, 'dropoff': _destinationController.text});
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _isSearching = true);
    try {
      // Utilisation de Photon (basé sur OpenStreetMap, optimisé pour l'autocomplétion)
      final url = Uri.parse('https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=15&lat=5.3599&lon=-4.0083');
      final response = await http.get(url, headers: {
        'User-Agent': 'YacolisApp/1.0 (contact@yacolis.ci)' // Requis par Photon pour ne pas bloquer Dart
      });
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        
        final List<Map<String, dynamic>> results = [];
        for (var f in features) {
          try {
            final props = f['properties'] as Map?;
            final geom = f['geometry'] as Map?;
            if (props == null) continue;
            
            // Filtre strict pour la Côte d'Ivoire
            if (props['countrycode'] != 'CI' && props['country'] != 'Côte d’Ivoire') continue;
            
            final title = props['name']?.toString() ?? '';
            if (title.isEmpty) continue;
            
            List<String> subtitleParts = [];
            if (props['street'] != null) subtitleParts.add(props['street'].toString());
            if (props['locality'] != null) subtitleParts.add(props['locality'].toString());
            if (props['district'] != null) subtitleParts.add(props['district'].toString());
            if (props['city'] != null) subtitleParts.add(props['city'].toString());
            
            String subtitle = subtitleParts.isNotEmpty ? subtitleParts.join(', ') : (props['state']?.toString() ?? 'Côte d\'Ivoire');
            
            List<double> center = [0, 0];
            if (geom != null && geom['coordinates'] != null) {
              final coords = geom['coordinates'] as List;
              center = [(coords[0] as num).toDouble(), (coords[1] as num).toDouble()];
            }
            
            results.add({
              'text': title,
              'place_name': subtitle,
              'center': center,
            });
          } catch (e) {
            // ignore error for single item
          }
        }
        
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      } else {
        setState(() => _isSearching = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Accès refusé par le serveur (${response.statusCode})')));
        }
      }
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de recherche: $e')));
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
        throw Exception('La permission de localisation est définitivement refusée.');
      }

      Position position = await Geolocator.getCurrentPosition();
      
      // Essayer de trouver l'adresse (Reverse Geocoding)
      String locationName = 'Ma position actuelle';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          // Construire une chaîne lisible
          List<String> addressParts = [];
          if (place.street != null && place.street!.isNotEmpty) addressParts.add(place.street!);
          if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
          
          if (addressParts.isNotEmpty) {
             locationName = addressParts.join(', ');
          }
        }
      } catch (e) {
        // En cas d'échec du geocoding, on garde 'Ma position actuelle'
      }

      if (mounted) {
        _onSuggestionSelected(locationName);
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
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
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
                          child: const Icon(Icons.inventory_2, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Prise en charge', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              TextField(
                                controller: _departureController,
                                focusNode: _departureFocus,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        // Bouton X
                        IconButton(
                          onPressed: () => _departureController.clear(),
                          icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        // Bouton Carte
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text('Carte', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                  
                  // Ligne de séparation
                  Padding(
                    padding: const EdgeInsets.only(left: 68, right: 16),
                    child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                  ),
                  
                  // Ligne Destination
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 40,
                          child: Icon(Icons.flag, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Destination', style: TextStyle(color: Colors.grey, fontSize: 12)),
                              TextField(
                                controller: _destinationController,
                                focusNode: _destinationFocus,
                                decoration: InputDecoration(
                                  hintText: 'Adresse de livraison',
                                  hintStyle: TextStyle(color: Colors.grey.shade400),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ],
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
              child: _searchResults.isEmpty && _destinationController.text.isEmpty && !_isSearching
                  ? ListView(
                      padding: const EdgeInsets.only(top: 16),
                      children: [
                        // Votre position
                        ListTile(
                          leading: const Icon(Icons.navigation, color: Colors.black87),
                          title: const Text('Votre position', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          subtitle: const Text('Prise en charge à l\'emplacement indiqué par les données GPS', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: _isLoadingLocation ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                          onTap: _isLoadingLocation ? null : () {
                            _getCurrentLocation();
                          },
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(color: Colors.grey.shade300),
                        ),
                      ],
                    )
                  : _isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 16),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final item = _searchResults[index];
                            return _buildSuggestionItem(
                              item['text'],
                              item['place_name'],
                              '', // Distance non disponible immédiatement via cette API sans calcul
                              () => _onSuggestionSelected(item['text'])
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(String title, String subtitle, String distance, VoidCallback onTap) {
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.location_on, color: Colors.grey.shade400),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: Colors.lightBlue),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: distance.isNotEmpty ? Text(distance, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)) : null,
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
