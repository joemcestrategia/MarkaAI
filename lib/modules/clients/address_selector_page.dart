import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocg;

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

  @override
  void initState() {
    super.initState();
    _loadUser();
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
      // 1. Check Service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ative o serviço de localização')));
        setState(() => _loading = false);
        return;
      }

      // 2. Check Permission
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

      // 3. Get Position
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
          // Format: Rua X, Bairro Y, Cidade Z
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

  Future<void> _saveTypedAddress() async {
    final text = _addrCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);

    double? lat;
    double? lng;
    String formattedAddress = text;
    String city = '';

    try {
      final places = await geocg.locationFromAddress(text);
      if (places.isNotEmpty) {
        lat = places.first.latitude;
        lng = places.first.longitude;

        // Try to get pretty name back
        try {
          final placemarks = await geocg.placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            city = p.subAdministrativeArea ?? p.locality ?? '';
            formattedAddress = [
              p.thoroughfare,
              p.subLocality,
              p.subAdministrativeArea
            ].where((e) => e != null && e.isNotEmpty).join(', ');
            if (formattedAddress.isEmpty) formattedAddress = text;
          }
        } catch (_) {}
      }
    } catch (_) {}

    final entry = {
      'label': city.isNotEmpty ? city : text.split(',').first,
      'address': formattedAddress,
      'city': city,
      'lat': lat,
      'lng': lng,
      'type': 'saved',
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      // save to user doc
      if (_userId != null) {
        final ref = FirebaseFirestore.instance.collection('users').doc(_userId);
        await ref.set({
          'saved_locations': FieldValue.arrayUnion([entry])
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _saved.insert(0, Map<String, dynamic>.from(entry));
            _addrCtrl.clear();
          });
        }
      }
    } catch (e) {
      debugPrint("Error saving location: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        title: const Text('Cidades e Localização',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!)),
                  child: TextField(
                    controller: _addrCtrl,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar cidade ou endereço...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.primaryPurple),
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded,
                              color: AppColors.primaryPurple),
                          onPressed: _saveTypedAddress),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _useCurrentLocation,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primaryPurple
                                .withValues(alpha: 0.3))),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location,
                            color: AppColors.primaryPurple),
                        const SizedBox(width: 12),
                        const Text(
                          'Usar minha localização atual',
                          style: TextStyle(
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.bookmark_border, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text("Cidades Salvas",
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
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
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text("Adicione cidades para ver ofertas",
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _saved.length,
                    itemBuilder: (context, index) {
                      final s = _saved[index];
                      // If label is missing, use part of address
                      final label = s['label'] ?? 'Local salvo';
                      final address = s['address'] ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Dismissible(
                          key: ValueKey(address.toString() + index.toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(16)),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.red),
                          ),
                          onDismissed: (_) => _deleteSaved(index),
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ]),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.05),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.location_city,
                                    color: AppColors.primaryPurple, size: 20),
                              ),
                              title: Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              subtitle: Text(address,
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13),
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
