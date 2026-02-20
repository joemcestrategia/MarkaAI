import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocg;
import 'dart:async';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/splash_loading_widget.dart';

class AddressSelectorPage extends StatefulWidget {
  const AddressSelectorPage({super.key});

  @override
  State<AddressSelectorPage> createState() => _AddressSelectorPageState();
}

class _AddressSelectorPageState extends State<AddressSelectorPage> {
  final TextEditingController _addrCtrl = TextEditingController();
  bool _loading = false;
  String? _userId;
  List<Map<String, dynamic>> _saved = [];
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _addrCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addrCtrl.removeListener(_onSearchChanged);
    _addrCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final text = _addrCtrl.text.trim();
    if (text.length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchSuggestions(text);
    });
  }

  Future<void> _searchSuggestions(String query) async {
    try {
      final locations = await geocg.locationFromAddress(query);
      final List<Map<String, dynamic>> results = [];
      for (final loc in locations.take(5)) {
        try {
          final placemarks =
              await geocg.placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final city = p.subAdministrativeArea ?? p.locality ?? '';
            final address = [
              p.thoroughfare,
              p.subLocality,
              p.subAdministrativeArea,
              p.administrativeArea,
            ].where((e) => e != null && e.isNotEmpty).join(', ');
            results.add({
              'label': city.isNotEmpty ? city : query.split(',').first,
              'address': address.isNotEmpty ? address : query,
              'city': city,
              'lat': loc.latitude,
              'lng': loc.longitude,
            });
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _suggestions = results);
    } catch (_) {
      if (mounted) setState(() => _suggestions = []);
    }
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _userId = user.uid);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final arr = (doc.data()?['saved_locations'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _saved = arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error loading user locations: $e");
    }
  }

  Future<void> _useCurrentLocation() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ative o serviço de localização')));
        setState(() => _loading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permissão de localização negada')));
          setState(() => _loading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permissão negada permanentemente')));
        setState(() => _loading = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      String address =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';

      String city = '';
      try {
        final places =
            await geocg.placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) {
          final p = places.first;
          city = p.subAdministrativeArea ?? p.locality ?? '';
          address = [
            p.thoroughfare,
            p.subLocality,
            p.subAdministrativeArea,
            p.administrativeArea
          ].where((e) => e != null && e.isNotEmpty).join(', ');
          if (address.isEmpty) {
            address =
                '${p.street ?? ''} ${p.subLocality ?? ''}, ${p.locality ?? ''}';
          }
        }
      } catch (_) {}

      final result = {
        'label': city.isNotEmpty ? city : 'Minha localização',
        'address': address,
        'city': city,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'type': 'current',
      };

      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro localização: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectSuggestion(Map<String, dynamic> suggestion) async {
    // Also save to Firestore
    if (_userId != null) {
      final entry = Map<String, dynamic>.from(suggestion);
      entry['type'] = 'saved';
      try {
        await FirebaseFirestore.instance.collection('users').doc(_userId).set({
          'saved_locations': FieldValue.arrayUnion([entry])
        }, SetOptions(merge: true));
        if (mounted) {
          setState(() {
            if (!_saved.any((s) => s['address'] == entry['address'])) {
              _saved.insert(0, entry);
            }
          });
        }
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(context, suggestion);
  }

  Future<void> _deleteSaved(int idx) async {
    if (_userId == null) return;
    final toRemove = _saved[idx];
    try {
      await FirebaseFirestore.instance.collection('users').doc(_userId).update({
        'saved_locations': FieldValue.arrayRemove([toRemove])
      });
      if (mounted) {
        setState(() => _saved.removeAt(idx));
      }
    } catch (e) {
      debugPrint("Error deleting location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SplashLoadingWidget(message: "Buscando localização...");
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Localização',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.primaryPurple,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!)),
                  child: TextField(
                    controller: _addrCtrl,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar cidade ou endereço...',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.primaryPurple, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _useCurrentLocation,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location,
                            color: AppColors.primaryPurple, size: 18),
                        const SizedBox(width: 10),
                        const Text(
                          'Usar minha localização atual',
                          style: TextStyle(
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Autocomplete suggestions
          if (_suggestions.isNotEmpty)
            Container(
              color: Colors.white,
              child: Column(
                children: _suggestions.map((s) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place,
                        color: AppColors.primaryPurple, size: 18),
                    title: Text(s['label'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(s['address'] ?? '',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => _selectSuggestion(s),
                  );
                }).toList(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.bookmark_border, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text("Cidades Salvas",
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: _saved.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 50, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text("Adicione cidades para ver ofertas",
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _saved.length,
                    itemBuilder: (context, index) {
                      final s = _saved[index];
                      final label = s['label'] ?? 'Local salvo';
                      final address = s['address'] ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(address.toString() + index.toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(12)),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.red),
                          ),
                          onDismissed: (_) => _deleteSaved(index),
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2))
                                ]),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.05),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.location_city,
                                    color: AppColors.primaryPurple, size: 18),
                              ),
                              title: Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              subtitle: Text(address,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.pop(context, {
                                'label': label,
                                'address': address,
                                'city': s['city'] ?? label,
                                'lat': s['lat'],
                                'lng': s['lng'],
                                'type': s['type'] ?? 'saved',
                              }),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
