import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/action_grid.dart';
import 'widgets/search_bar_widget.dart';
import 'widgets/recent_locations.dart';
import 'widgets/home_drawer.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showLocationDetailsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return const _LocationBottomSheetContent();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: const HomeDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: GestureDetector(
          onTap: () => _showLocationDetailsSheet(context),
          behavior: HitTestBehavior.opaque,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Yaco',
                  style:  GoogleFonts.anton(fontSize: 30, color: Color(0xFF002259),  fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.2),
                  //TextStyle(color: Color(0xFF002259), fontSize: 30, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.2),
                ),
                TextSpan(
                  text: 'lis',
                  style:  GoogleFonts.anton(fontSize: 30, color: Color(0xFFFF7F25),  fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -0.5),
                  //TextStyle(color: Color(0xFF002259), fontSize: 30, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -1.2),
                ),

                TextSpan(text: '.', style: TextStyle(color: Color(0xFF002259), fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFB030D1), Color(0xFF6B1DCD)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.add, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('Plus', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.black),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Header
            GestureDetector(
              onTap: () => _showLocationDetailsSheet(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Votre position', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                    const SizedBox(width: 6),
                    Container(
                      width: 16,
                      height: 16,
                      padding: const EdgeInsets.only(left: 1),
                      decoration: const BoxDecoration(color: Color(0xFF222222), shape: BoxShape.circle),
                      child: const Icon(Icons.chevron_right, size: 13, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const ActionGrid(),
            const SizedBox(height: 20),
            const SearchBarWidget(),
            const SizedBox(height: 20),
            const RecentLocations(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _LocationBottomSheetContent extends StatefulWidget {
  const _LocationBottomSheetContent();

  @override
  State<_LocationBottomSheetContent> createState() => _LocationBottomSheetContentState();
}

class _LocationBottomSheetContentState extends State<_LocationBottomSheetContent> {
  // Cache statique pour garder la position en mémoire et l'afficher instantanément
  static LatLng? _cachedPosition;
  static String _cachedAddressLine1 = '';
  static String _cachedAddressLine2 = '';

  LatLng? _currentPosition;
  String _addressLine1 = 'Recherche en cours...';
  String _addressLine2 = 'Veuillez patienter';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (_cachedPosition != null) {
      // Si on a déjà la position en mémoire, on l'affiche directement
      _currentPosition = _cachedPosition;
      _addressLine1 = _cachedAddressLine1;
      _addressLine2 = _cachedAddressLine2;
      _isLoading = false;
      // On peut relancer une recherche discrète en arrière-plan
      _fetchRealLocation(isBackground: true);
    } else {
      _fetchRealLocation(isBackground: false);
    }
  }

  Future<void> _fetchRealLocation({bool isBackground = false}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS désactivé');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Permission refusée');
      }

      if (permission == LocationPermission.deniedForever) throw Exception('Permission refusée définitivement');

      var position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _cachedPosition = _currentPosition;
        });
      }

      // Reverse Geocoding
      try {
        var placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          var place = placemarks.first;
          if (mounted) {
            setState(() {
              _addressLine1 = place.street?.isNotEmpty == true ? place.street! : 'Position Inconnue';
              _addressLine2 = [place.subLocality, place.locality].where((e) => e != null && e.isNotEmpty).join(', ');
              _isLoading = false;
              
              _cachedAddressLine1 = _addressLine1;
              _cachedAddressLine2 = _addressLine2;
            });
          }
        }
      } catch (e) {
        if (mounted && !isBackground) setState(() {
          _addressLine1 = 'Position actuelle';
          _addressLine2 = '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isBackground) setState(() {
        _addressLine1 = 'Erreur GPS';
        _addressLine2 = 'Impossible de trouver la position';
        _isLoading = false;
        // Position par défaut Abidjan si erreur
        _currentPosition = const LatLng(5.359951, -4.008256);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('VOTRE POSITION', style: GoogleFonts.anton(fontSize: 26, color: Colors.black, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 16),
          
          // Map preview container
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 170,
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  if (_currentPosition != null)
                    ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: _currentPosition!,
                          initialZoom: 16.0,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.yacolis.app',
                          ),
                        ],
                      ),
                    ),
                  if (_currentPosition == null)
                    const Center(child: CircularProgressIndicator()),
                  
                  Container(color: Colors.white.withOpacity(0.65)),
                  
                  if (_currentPosition != null)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF04D4D),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))]
                            ),
                            child: const Icon(Icons.hail, color: Colors.white, size: 26),
                          ),
                          Container(width: 2.5, height: 14, color: Colors.black),
                          const SizedBox(height: 22),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Address details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _addressLine1,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _addressLine2,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Actions list
          _buildActionItem(Icons.bookmark, 'Enregistrer la position pour une utilisation ultérieure'),
          Padding(padding: const EdgeInsets.only(left: 60, right: 20), child: Divider(height: 1, color: Colors.grey.shade200)),
          
          _buildActionItem(Icons.edit, 'Modifier votre position'),
          Padding(padding: const EdgeInsets.only(left: 60, right: 20), child: Divider(height: 1, color: Colors.grey.shade200)),
          
          _buildActionItem(Icons.turn_right, 'Partager la position'),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String text) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: Colors.black, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87, height: 1.3),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black38, size: 18),
          ],
        ),
      ),
    );
  }
}
