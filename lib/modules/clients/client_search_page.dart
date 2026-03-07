import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme/app_colors.dart';
import 'shop_profile_page.dart';
import 'client_service_detail_page.dart';
import '../../core/utils/string_utils.dart';

class ClientSearchPage extends StatefulWidget {
  final String initialQuery;
  final String initialCity;
  final double? userLat;
  final double? userLng;
  final double initialRadius;

  const ClientSearchPage({
    super.key,
    required this.initialQuery,
    required this.initialCity,
    this.userLat,
    this.userLng,
    this.initialRadius = 20.0,
  });

  @override
  State<ClientSearchPage> createState() => _ClientSearchPageState();
}

class _ClientSearchPageState extends State<ClientSearchPage> {
  late TextEditingController _searchCtrl;
  String _currentCity = "";
  double? _userLat;
  double? _userLng;
  double _selectedRadius = 20.0;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.initialQuery);
    _currentCity = widget.initialCity;
    _userLat = widget.userLat;
    _userLng = widget.userLng;
    _selectedRadius = widget.initialRadius;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openServiceDetails({required DocumentSnapshot serviceDoc}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientServiceDetailPage(
          serviceDoc: serviceDoc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() {}),
            onSubmitted: (v) => setState(() {}),
            decoration: const InputDecoration(
              hintText: "O que você procura?",
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Subheader com info de localização e resultados
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border:
                  Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on,
                    size: 14, color: AppColors.primaryPurple),
                const SizedBox(width: 4),
                Text(
                  _currentCity.isEmpty ? "Todas as cidades" : _currentCity,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryPurple),
                ),
                const Spacer(),
                const Text("Resultados",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('shops').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final query = _searchCtrl.text.trim().toLowerCase();
                final city = _currentCity.toLowerCase();

                final filtered = snapshot.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final bool isActive = d['ativo'] ?? true;

                  final name = (d['nome'] ?? "").toString().toLowerCase();
                  final category =
                      (d['categoria'] ?? "").toString().toLowerCase();
                  // 📍 Recupera cidade e estado com fallbacks (raiz e 'endereco')
                  String getLocField(String key, List<String> fallbacks) {
                    if (d[key] != null && d[key].toString().trim().isNotEmpty)
                      return d[key].toString().trim();
                    if (d['endereco'] is Map) {
                      final map = d['endereco'] as Map;
                      if (map[key] != null &&
                          map[key].toString().trim().isNotEmpty)
                        return map[key].toString().trim();
                      for (var fb in fallbacks) {
                        if (map[fb] != null &&
                            map[fb].toString().trim().isNotEmpty)
                          return map[fb].toString().trim();
                      }
                    }
                    for (var fb in fallbacks) {
                      if (d[fb] != null && d[fb].toString().trim().isNotEmpty)
                        return d[fb].toString().trim();
                    }
                    return '';
                  }

                  final String shopCidadeRaw = getLocField('cidade', ['city']);
                  final String shopEstadoRaw =
                      getLocField('estado', ['uf', 'state']);

                  if (shopCidadeRaw.isEmpty) {
                    return false;
                  }

                  // Normalização para comparação robusta
                  final String shopCidade =
                      StringUtils.removeDiacritics(shopCidadeRaw).toLowerCase();
                  final String shopEstado = shopEstadoRaw.toLowerCase();
                  final String fullLocation = "$shopCidade $shopEstado";
                  final String searchLower =
                      StringUtils.removeDiacritics(query).toLowerCase();

                  final matchesText = searchLower.isEmpty ||
                      name.contains(searchLower) ||
                      category.contains(searchLower) ||
                      fullLocation.contains(searchLower);

                  bool matchesLoc = true;
                  if (city.isNotEmpty) {
                    final normalizedSearchCity =
                        StringUtils.removeDiacritics(city).toLowerCase();
                    // Rigorosamente a cidade correta
                    matchesLoc = shopCidade == normalizedSearchCity;
                  }

                  // ðŸ›°ï¸ Filtro por Raio (se disponível)
                  if (_userLat != null &&
                      _userLng != null &&
                      d['lat'] != null &&
                      d['lng'] != null) {
                    final double dist = Geolocator.distanceBetween(
                          _userLat!,
                          _userLng!,
                          (d['lat'] as num).toDouble(),
                          (d['lng'] as num).toDouble(),
                        ) /
                        1000.0;
                    matchesLoc = dist <= _selectedRadius;
                  }

                  return isActive && matchesText && matchesLoc;
                }).toList();

                // ðŸ”€ Ordenação por Qualidade do Perfil (Media)
                filtered.sort((a, b) {
                  final da = a.data() as Map<String, dynamic>;
                  final db = b.data() as Map<String, dynamic>;

                  int getScore(Map<String, dynamic> d) {
                    int s = 0;
                    if ((d['logoUrl'] ?? '').toString().isNotEmpty) s += 10;
                    if ((d['coverUrl'] ?? '').toString().isNotEmpty ||
                        (d['imageUrl'] ?? '').toString().isNotEmpty) {
                      s += 10;
                    }
                    if (d['is_boosted'] == true) s += 100;
                    return s;
                  }

                  return getScore(db).compareTo(getScore(da));
                });

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        const Text("Nenhuma loja encontrada.",
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.70,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final shop = filtered[index];
                    return _SearchCard(
                      shop: shop,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopProfilePage(
                              shopDoc: shop,
                              onBookService: (sDoc) {
                                _openServiceDetails(serviceDoc: sDoc);
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final DocumentSnapshot shop;
  final VoidCallback onTap;

  const _SearchCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = shop.data() as Map<String, dynamic>;
    final imgUrl = data['coverUrl'] ?? data['imageUrl'] ?? "";
    final logoUrl = data['logoUrl'] ?? "";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      child: imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.cover,
                              placeholder: (c, u) =>
                                  Container(color: Colors.grey[200]))
                          : Container(
                              color: Colors.grey[200],
                              child:
                                  const Icon(Icons.store, color: Colors.grey)),
                    ),
                  ),
                  // Rating Badge
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 10, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            (data['rating'] ?? 5.0).toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Logo overlay
                  if (logoUrl.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: ClipOval(
                            child: CachedNetworkImage(
                                imageUrl: logoUrl, fit: BoxFit.cover)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data['nome'] ?? "Loja",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['categoria'] ?? "Serviços",
                      style: TextStyle(color: Colors.grey[600], fontSize: 8),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
