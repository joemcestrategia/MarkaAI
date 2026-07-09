import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';

class BusinessClientsHeatmapPage extends StatefulWidget {
  const BusinessClientsHeatmapPage({super.key});

  @override
  State<BusinessClientsHeatmapPage> createState() =>
      _BusinessClientsHeatmapPageState();
}

class _BusinessClientsHeatmapPageState extends State<BusinessClientsHeatmapPage> {
  final MapController _mapController = MapController();
  MapCamera? _camera;
  Size _mapSize = Size.zero;
  LatLng? _shopLatLng;
  String? _shopName;
  String? _shopLogoUrl;

  // Pontos de clientes (SEM a loja)
  final List<LatLng> _geocodedPoints = [];
  int _cachedCount = 0;
  int _newlyGeocoded = 0;
  bool _isLoadingAddresses = true;
  bool _isGeocoding = false;
  int _totalClients = 0;        // Total de clientes encontrados
  int _clientsNoAddress = 0;    // Clientes sem endereço algum
  int _geocodedCount = 0;
  String _statusMessage = 'Carregando clientes...';

  // --- KPIs ---
  double _avgDistanceKm = 0;
  String _topNeighborhood = '';
  int _topNeighborhoodCount = 0;
  final Map<String, int> _neighborhoodCounts = {};

  // --- Raio de alcance ---
  bool _showRadiusOverlay = true;
  int _clientsWithin1km = 0;
  int _clientsWithin3km = 0;
  int _clientsWithin5km = 0;

  @override
  void initState() {
    super.initState();
    _loadShopAndClients();
  }

  Future<void> _loadShopAndClients() async {
    final shopId = await SessionService.getShopId();
    if (shopId == null || !mounted) {
      setState(() {
        _isLoadingAddresses = false;
        _statusMessage = 'Erro: loja não encontrada';
      });
      return;
    }

    final shopResponse = await sb.Supabase.instance.client
        .from('shops')
        .select('lat, lng, name, logo_url, address, city, state, neighborhood, number, zip_code')
        .eq('id', shopId)
        .maybeSingle();

    final List<Map<String, dynamic>> toGeocode = [];

    if (shopResponse != null && mounted) {
      final sLat = shopResponse['lat'];
      final sLng = shopResponse['lng'];
      if (sLat != null && sLng != null) {
        _shopLatLng = LatLng(
          (sLat as num).toDouble(),
          (sLng as num).toDouble(),
        );
      } else {
        final street = shopResponse['address']?.toString().trim();
        final number = shopResponse['number']?.toString().trim();
        final neighborhood = shopResponse['neighborhood']?.toString().trim();
        final city = shopResponse['city']?.toString().trim();
        final state = shopResponse['state']?.toString().trim();
        final zipCode = shopResponse['zip_code']?.toString().trim();

        final query = _buildQuery(street, number, neighborhood, city, state, null, zipCode);
        if (query.isNotEmpty) {
          toGeocode.add({
            'id': 'SHOP_$shopId',
            'query': query,
          });
        }
      }
      _shopName = shopResponse['name']?.toString() ?? 'Sua loja';
      _shopLogoUrl = shopResponse['logo_url']?.toString();
    }

    // Coleta IDs e telefones de clientes
    final Set<String> clientIds = {};
    final Set<String> manualPhones = {};
    
    try {
      final appointments = await sb.Supabase.instance.client
          .from('appointments')
          .select('client_id, client_phone')
          .eq('shop_id', shopId);
      for (var a in appointments) {
        final id = a['client_id']?.toString();
        if (id != null && id.isNotEmpty) {
          clientIds.add(id);
        } else {
          final phone = a['client_phone']?.toString();
          if (phone != null && phone.isNotEmpty) {
            final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
            if (cleanPhone.isNotEmpty) manualPhones.add(cleanPhone);
          }
        }
      }
    } catch (_) {}

    try {
      final shopClients = await sb.Supabase.instance.client
          .from('shop_clients')
          .select('user_id')
          .eq('shop_id', shopId);
      for (var c in shopClients) {
        final id = c['user_id']?.toString();
        if (id != null && id.isNotEmpty) clientIds.add(id);
      }
    } catch (_) {}

    try {
      final favorites = await sb.Supabase.instance.client
          .from('favorites')
          .select('user_id')
          .eq('shop_id', shopId);
      for (var f in favorites) {
        final id = f['user_id']?.toString();
        if (id != null && id.isNotEmpty) clientIds.add(id);
      }
    } catch (_) {}

    try {
      final views = await sb.Supabase.instance.client
          .from('shop_views')
          .select('user_id')
          .eq('shop_id', shopId);
      for (var v in views) {
        final id = v['user_id']?.toString();
        if (id != null && id.isNotEmpty) clientIds.add(id);
      }
    } catch (_) {}

    if (clientIds.isEmpty && manualPhones.isEmpty && !mounted) {
      setState(() {
        _isLoadingAddresses = false;
        _statusMessage = 'Nenhum cliente cadastrado';
      });
      return;
    }

    // Busca os dados de endereço e geolocalização dos clientes
    List<dynamic> clientsResponse = [];
    try {
      if (clientIds.isNotEmpty) {
        final idChunks = clientIds.toList();
        for (var i = 0; i < idChunks.length; i += 100) {
          final chunk = idChunks.sublist(i, (i + 100).clamp(0, idChunks.length));
          final users = await sb.Supabase.instance.client
              .from('users')
              .select('id, city, state, street, number, neighborhood, address, zip_code, lat, lng')
              .inFilter('id', chunk);
          clientsResponse.addAll(users);
        }
      }
      
      if (manualPhones.isNotEmpty) {
        final phoneChunks = manualPhones.toList();
        for (var i = 0; i < phoneChunks.length; i += 100) {
          final chunk = phoneChunks.sublist(i, (i + 100).clamp(0, phoneChunks.length));
          final users = await sb.Supabase.instance.client
              .from('users')
              .select('id, city, state, street, number, neighborhood, address, zip_code, lat, lng')
              .inFilter('phone', chunk);
              
          // Adiciona apenas se ainda não estiver na lista
          final existingIds = clientsResponse.map((u) => u['id'].toString()).toSet();
          for (var u in users) {
            if (!existingIds.contains(u['id'].toString())) {
              clientsResponse.add(u);
            }
          }
        }
      }
    } catch (_) {}

    if (clientsResponse.isEmpty || !mounted) {
      setState(() {
        _isLoadingAddresses = false;
        _statusMessage = 'Nenhum endereço encontrado para os clientes';
      });
      return;
    }

    _totalClients = clientsResponse.length;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final lastCacheDateStr = prefs.getString('heatmap_cache_date');
    
    bool shouldClearCache = false;
    if (lastCacheDateStr == null) {
      shouldClearCache = true;
    } else {
      final lastDate = DateTime.tryParse(lastCacheDateStr);
      if (lastDate == null || today.difference(lastDate).inDays >= 7) {
        shouldClearCache = true;
      }
    }
    
    if (shouldClearCache) {
      final keys = prefs.getKeys().where((k) => k.startsWith('geo_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
      await prefs.setString('heatmap_cache_date', today.toIso8601String());
    }

    // Mapa de endereço normalizado → LatLng (evita geocodificar duplicado)
    // mas todos os clientes com mesmo endereço ganham um ponto no mapa
    final Map<String, LatLng?> resolvedAddresses = {};

    for (final client in clientsResponse) {
      final c = client as Map<String, dynamic>;
      final cLat = c['lat'];
      final cLng = c['lng'];

      // Coletar bairro para KPIs
      final neighborhood = c['neighborhood']?.toString().trim();
      if (neighborhood != null && neighborhood.isNotEmpty) {
        _neighborhoodCounts[neighborhood] = (_neighborhoodCounts[neighborhood] ?? 0) + 1;
      }

      // Cliente já tem lat/lng no banco
      if (cLat != null && cLng != null) {
        final latLng = LatLng(
          (cLat as num).toDouble(),
          (cLng as num).toDouble(),
        );
        _geocodedPoints.add(latLng);
        _cachedCount++;
        continue;
      }

      final street = c['street']?.toString().trim();
      final number = c['number']?.toString().trim();
      final city = c['city']?.toString().trim();
      final state = c['state']?.toString().trim();
      final address = c['address']?.toString().trim();
      final zipCode = c['zip_code']?.toString().trim();

      final query = _buildQuery(street, number, neighborhood, city, state, address, zipCode);
      if (query.isEmpty) {
        _clientsNoAddress++;
        continue;
      }

      final normalized = query.toLowerCase().replaceAll(RegExp(r'[\s,]+'), '');
      
      // Verificar cache local
      final cachedLoc = prefs.getString('geo_$normalized');
      if (cachedLoc != null) {
        final parts = cachedLoc.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0]);
          final lng = double.tryParse(parts[1]);
          if (lat != null && lng != null) {
            final latLng = LatLng(lat, lng);
            _geocodedPoints.add(latLng);
            _cachedCount++;
            resolvedAddresses[normalized] = latLng;
            continue;
          }
        }
      }

      // Verificar se já resolvemos esse endereço nesta sessão
      if (resolvedAddresses.containsKey(normalized)) {
        final existing = resolvedAddresses[normalized];
        if (existing != null) {
          _geocodedPoints.add(existing);
          _cachedCount++;
        }
        continue;
      }

      // Marcar como pendente para geocodificação
      resolvedAddresses[normalized] = null;
      toGeocode.add({
        'id': c['id'],
        'query': query,
        'normalized': normalized,
      });
    }

    _geocodedCount = _cachedCount;

    // Calcular KPIs com dados disponíveis
    _computeKPIs();

    if (toGeocode.isEmpty) {
      setState(() {
        _isLoadingAddresses = false;
        _statusMessage = '';
      });
      return;
    }

    setState(() {
      _isLoadingAddresses = false;
      _isGeocoding = true;
      _newlyGeocoded = 0;
      _statusMessage = 'Geocodificando ${toGeocode.length} novos endereços...';
    });

    _geocodeAndCache(toGeocode);
  }

  void _computeKPIs() {
    if (_geocodedPoints.isEmpty) return;

    if (_shopLatLng != null) {
      final distCalc = const Distance();
      double totalDist = 0;
      int count = 0;
      _clientsWithin1km = 0;
      _clientsWithin3km = 0;
      _clientsWithin5km = 0;

      for (final p in _geocodedPoints) {
        final distMeters = distCalc.as(LengthUnit.Meter, _shopLatLng!, p);
        final distKm = distMeters / 1000.0;
        totalDist += distKm;
        count++;

        if (distKm <= 1) _clientsWithin1km++;
        if (distKm <= 3) _clientsWithin3km++;
        if (distKm <= 5) _clientsWithin5km++;
      }

      if (count > 0) {
        _avgDistanceKm = totalDist / count;
      }
    }

    // Bairro mais forte
    if (_neighborhoodCounts.isNotEmpty) {
      final sorted = _neighborhoodCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _topNeighborhood = sorted.first.key;
      _topNeighborhoodCount = sorted.first.value;
    }
  }

  Future<void> _geocodeAndCache(
    List<Map<String, dynamic>> toGeocode,
  ) async {
    final sbClient = sb.Supabase.instance.client;
    final prefs = await SharedPreferences.getInstance();
    int done = 0;

    for (final entry in toGeocode) {
      final query = entry['query'] as String;
      final userId = entry['id'] as String;
      final normalized = entry['normalized'] as String?;

      final latLng = await _nominatimSearch(query);
      if (latLng != null) {
        if (normalized != null) {
          await prefs.setString('geo_$normalized', '${latLng.latitude},${latLng.longitude}');
        }
        if (userId.startsWith('SHOP_')) {
          _shopLatLng = latLng;
          try {
            final sid = userId.replaceFirst('SHOP_', '');
            await sbClient.from('shops').update({
              'lat': latLng.latitude,
              'lng': latLng.longitude,
            }).eq('id', sid);
          } catch (_) {}
        } else {
          _geocodedPoints.add(latLng);
          _newlyGeocoded++;
          _geocodedCount = _cachedCount + _newlyGeocoded;

          try {
            await sbClient.rpc('update_user_geolocation', params: {
              'p_user_id': userId,
              'p_lat': latLng.latitude,
              'p_lng': latLng.longitude,
            });
          } catch (_) {}
        }
      }

      done++;
      if (mounted) {
        setState(() {
          _statusMessage = 'Geocodificando $done de ${toGeocode.length}...';
        });
      }

      await Future.delayed(const Duration(milliseconds: 1100));
    }

    // Recalcular KPIs com pontos novos
    _computeKPIs();

    if (mounted) {
      setState(() {
        _isGeocoding = false;
        _statusMessage = '';
      });

      try {
        final bounds = _computeBounds();
        if (bounds != null) {
          final zoom = _computeZoom(_geocodedPoints, bounds);
          LatLng center;
          if (_shopLatLng != null) {
            center = _shopLatLng!;
          } else if (_geocodedPoints.isNotEmpty) {
            double avgLat = 0, avgLng = 0;
            for (final p in _geocodedPoints) {
              avgLat += p.latitude;
              avgLng += p.longitude;
            }
            center = LatLng(avgLat / _geocodedPoints.length, avgLng / _geocodedPoints.length);
          } else {
            center = const LatLng(-15.793, -47.882);
          }
          _mapController.move(center, zoom);
        }
      } catch (_) {}
    }
  }

  String _buildQuery(
    String? street,
    String? number,
    String? neighborhood,
    String? city,
    String? state,
    String? address,
    String? zipCode,
  ) {
    final parts = <String>[];

    if (street != null && street.isNotEmpty && number != null && number.isNotEmpty) {
      parts.add('$street, $number');
    } else if (street != null && street.isNotEmpty) {
      parts.add(street);
    } else if (address != null && address.isNotEmpty) {
      parts.add(address);
    }

    if (neighborhood != null && neighborhood.isNotEmpty) {
      parts.add(neighborhood);
    }
    if (city != null && city.isNotEmpty) {
      parts.add(city);
    }
    if (state != null && state.isNotEmpty) {
      parts.add(state);
    }
    if (zipCode != null && zipCode.isNotEmpty) {
      parts.add(zipCode);
    }
    parts.add('Brasil');

    return parts.join(', ');
  }

  Future<LatLng?> _nominatimSearch(String query) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=1&accept-language=pt-BR',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'MarkaAI/1.0'});
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as List;
        if (json.isNotEmpty) {
          final r = json[0] as Map<String, dynamic>;
          final lat = double.tryParse(r['lat']?.toString() ?? '');
          final lon = double.tryParse(r['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLngBounds? _computeBounds() {
    if (_geocodedPoints.isEmpty && _shopLatLng == null) return null;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;

    final points = [..._geocodedPoints];
    if (_shopLatLng != null) points.add(_shopLatLng!);

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      LatLng(minLat - 0.02, minLng - 0.02),
      LatLng(maxLat + 0.02, maxLng + 0.02),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAddresses) {
      return const Center(child: CircularProgressIndicator());
    }

    final points = _geocodedPoints;
    LatLng center;

    if (_shopLatLng != null) {
      center = _shopLatLng!;
    } else if (points.isNotEmpty) {
      double avgLat = 0, avgLng = 0;
      for (final p in points) {
        avgLat += p.latitude;
        avgLng += p.longitude;
      }
      center = LatLng(avgLat / points.length, avgLng / points.length);
    } else {
      center = const LatLng(-15.793, -47.882);
    }

    final bounds = _computeBounds();
    final initialZoom = _computeZoom(points, bounds);

    return Scaffold(
      body: Column(
        children: [
          if (_isGeocoding || _statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _buildStatusBar(),
            ),
          Expanded(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final mapSize = Size(constraints.maxWidth, constraints.maxHeight);
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: initialZoom,
                  minZoom: 3,
                  maxZoom: 18,
                  onMapReady: () {
                    _camera = _mapController.camera;
                    _mapSize = mapSize;
                    if (mounted) setState(() {});
                  },
                  onMapEvent: (evt) {
                    _camera = evt.camera;
                    _mapSize = mapSize;
                    if (mounted) setState(() {});
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.markaai.app',
                  ),
                  // Raio de alcance
                  if (_shopLatLng != null && _showRadiusOverlay)
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: _shopLatLng!,
                          radius: 5000,
                          useRadiusInMeter: true,
                          color: const Color(0xFF7B1FA2).withValues(alpha: 0.03),
                          borderColor: const Color(0xFF7B1FA2).withValues(alpha: 0.12),
                          borderStrokeWidth: 1,
                        ),
                        CircleMarker(
                          point: _shopLatLng!,
                          radius: 3000,
                          useRadiusInMeter: true,
                          color: const Color(0xFF7B1FA2).withValues(alpha: 0.05),
                          borderColor: const Color(0xFF7B1FA2).withValues(alpha: 0.2),
                          borderStrokeWidth: 1,
                        ),
                        CircleMarker(
                          point: _shopLatLng!,
                          radius: 1000,
                          useRadiusInMeter: true,
                          color: const Color(0xFF7B1FA2).withValues(alpha: 0.08),
                          borderColor: const Color(0xFF7B1FA2).withValues(alpha: 0.35),
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),
                  if (points.isNotEmpty && _camera != null)
                    _HeatmapOverlay(
                      points: points,
                      mapController: _mapController,
                      camera: _camera!,
                      mapSize: _mapSize,
                    ),
                  if (_shopLatLng != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _shopLatLng!,
                          width: 140,
                          height: 90,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primaryPurple, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.white,
                                  backgroundImage: _shopLogoUrl != null ? NetworkImage(_shopLogoUrl!) : null,
                                  child: _shopLogoUrl == null ? const Icon(Icons.store, color: AppColors.primaryPurple, size: 24) : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: Text(
                                  _shopName ?? 'Sua loja',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    );
                  },
                ),

                // --- Painel superior unificado ---
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _buildUnifiedTopPanel(),
                ),

                // --- Botões flutuantes (direita) ---
                Positioned(
                  bottom: 24,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_shopLatLng != null)
                        _buildSmallFAB(
                          icon: Icons.radar_rounded,
                          isActive: _showRadiusOverlay,
                          heroTag: 'toggleRadius',
                          onTap: () => setState(() => _showRadiusOverlay = !_showRadiusOverlay),
                        ),
                      const SizedBox(height: 8),
                      FloatingActionButton(
                        heroTag: 'centerMap',
                        backgroundColor: AppColors.primaryPurple,
                        elevation: 3,
                        onPressed: () {
                          if (_shopLatLng != null) {
                            _mapController.move(_shopLatLng!, 14.0);
                          } else if (_geocodedPoints.isNotEmpty) {
                            final bounds = _computeBounds();
                            if (bounds != null) {
                              _mapController.move(bounds.center, _computeZoom(_geocodedPoints, bounds));
                            }
                          }
                        },
                        child: const Icon(Icons.my_location, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // --- Painel de Raio (esquerda inferior) ---
                if (_showRadiusOverlay && _shopLatLng != null && _geocodedPoints.isNotEmpty)
                  Positioned(
                    bottom: 24,
                    left: 16,
                    child: _buildRadiusInfo(),
                  ),
              ],
            ),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  // ============================================================================
  // PAINEL SUPERIOR UNIFICADO (KPIs + info)
  // ============================================================================

  Widget _buildUnifiedTopPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Linha 1: KPIs principais
          Row(
            children: [
              // Clientes mapeados
              _buildKPIChip(
                icon: Icons.people_alt_rounded,
                value: '${_geocodedPoints.length}',
                subtitle: 'de $_totalClients',
                color: const Color(0xFF7B1FA2),
              ),
              const SizedBox(width: 8),
              // Distância média
              if (_shopLatLng != null) ...[
                _buildKPIChip(
                  icon: Icons.straighten_rounded,
                  value: '${_avgDistanceKm.toStringAsFixed(1)} km',
                  subtitle: 'dist. média',
                  color: const Color(0xFFE91E63),
                ),
                const SizedBox(width: 8),
              ],
              // Bairro top
              if (_topNeighborhood.isNotEmpty)
                Expanded(
                  child: _buildKPIChip(
                    icon: Icons.location_city_rounded,
                    value: _topNeighborhood,
                    subtitle: '$_topNeighborhoodCount clientes',
                    color: const Color(0xFFAB47BC),
                  ),
                ),
            ],
          ),
          // Linha 2: Info de clientes sem endereço (se houver)
          if (_clientsNoAddress > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_clientsNoAddress clientes sem endereço cadastrado',
                      style: TextStyle(fontSize: 11, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKPIChip({
    required IconData icon,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // SMALL FAB HELPER
  // ============================================================================

  Widget _buildSmallFAB({
    required IconData icon,
    required bool isActive,
    required String heroTag,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: FloatingActionButton(
        heroTag: heroTag,
        backgroundColor: isActive ? AppColors.primaryPurple : Colors.white,
        elevation: 2,
        onPressed: onTap,
        child: Icon(
          icon,
          color: isActive ? Colors.white : AppColors.primaryPurple,
          size: 20,
        ),
      ),
    );
  }

  // ============================================================================
  // RADIUS INFO
  // ============================================================================

  Widget _buildRadiusInfo() {
    final total = _geocodedPoints.length;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Alcance',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          _buildRadiusRow('1km', _clientsWithin1km, total),
          const SizedBox(height: 3),
          _buildRadiusRow('3km', _clientsWithin3km, total),
          const SizedBox(height: 3),
          _buildRadiusRow('5km', _clientsWithin5km, total),
        ],
      ),
    );
  }

  Widget _buildRadiusRow(String label, int count, int total) {
    final pct = total > 0 ? ((count / total) * 100).round() : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          child: Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        ),
        Container(
          width: 50,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: total > 0 ? (count / total).clamp(0.0, 1.0) : 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B1FA2), Color(0xFFE91E63)],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$pct%',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF7B1FA2)),
        ),
      ],
    );
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  double _computeZoom(List<LatLng> points, LatLngBounds? bounds) {
    if (points.isEmpty && _shopLatLng != null) return 14;
    if (bounds == null) return 13;
    
    final latDiff = (bounds.northEast.latitude - bounds.southWest.latitude).abs();
    final lngDiff = (bounds.northEast.longitude - bounds.southWest.longitude).abs();
    final maxDiff = max(latDiff, lngDiff);
    
    if (maxDiff < 0.01) return 15;
    if (maxDiff < 0.05) return 13;
    if (maxDiff < 0.2) return 11;
    if (maxDiff < 1.0) return 9;
    if (maxDiff < 5.0) return 7;
    return 5;
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (_isGeocoding)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_isGeocoding) const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
            ),
          ),
          if (_isGeocoding && _totalClients > 0)
            Text(
              '${((_geocodedCount / _totalClients) * 100).round()}%',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      width: double.infinity,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Menos ', style: TextStyle(fontSize: 12, color: Colors.black54)),
          _legendGradient(),
          const Text(' Mais', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _legendGradient() {
    return Container(
      width: 120,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF7B1FA2),
            Color(0xFFAB47BC),
            Color(0xFFE91E63),
            Color(0xFFFF1744),
          ],
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _HeatmapOverlay extends StatelessWidget {
  final List<LatLng> points;
  final MapController mapController;
  final MapCamera camera;
  final Size mapSize;

  const _HeatmapOverlay({
    required this.points,
    required this.mapController,
    required this.camera,
    required this.mapSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeatmapPainter(
        points: points,
        camera: camera,
        size: mapSize,
      ),
      size: mapSize,
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<LatLng> points;
  final MapCamera camera;
  final Size size;

  _HeatmapPainter({
    required this.points,
    required this.camera,
    required this.size,
  });

  Offset _latLngToScreen(LatLng latLng) {
    final point = camera.crs.latLngToPoint(latLng, camera.zoom);
    final centerPoint = camera.crs.latLngToPoint(camera.center, camera.zoom);
    final dx = point.x - centerPoint.x;
    final dy = point.y - centerPoint.y;
    return Offset(dx.toDouble() + size.width / 2, dy.toDouble() + size.height / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Raio dinâmico baseado no zoom — mais contido para manchas mais focadas
    final double radius = (camera.zoom * 3.0).clamp(14.0, 55.0);
    final double blurSigma = radius * 0.6;

    // Única saveLayer: círculos brancos definem a máscara de intensidade
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());

    final heatPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    for (final p in points) {
      final offset = _latLngToScreen(p);
      if (offset.dx < -radius * 2 || offset.dx > size.width + radius * 2) continue;
      if (offset.dy < -radius * 2 || offset.dy > size.height + radius * 2) continue;
      canvas.drawCircle(offset, radius, heatPaint);
    }

    // Gradiente só pinta DENTRO dos círculos (srcIn)
    final gradientPaint = Paint()
      ..blendMode = BlendMode.srcIn
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xFF7B1FA2),
          Color(0xFFAB47BC),
          Color(0xFFE91E63),
          Color(0xFFFF1744),
        ],
        stops: [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, gradientPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.camera != camera ||
        oldDelegate.size != size;
  }
}
