import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/widgets/google_reviews_widget.dart';
import 'package:markaai/core/utils/service_image_keywords.dart';
import 'package:markaai/core/widgets/pexels_image_widget.dart';
import 'package:markaai/modules/clients/client_service_detail_page.dart';
import 'package:markaai/core/services/shop_data_cache_service.dart';
import 'package:markaai/core/widgets/shared_bottom_nav_bar.dart';
class PublicShopPage extends StatefulWidget {
  final String slug;
  final bool isReschedule;
  final String? rescheduleAppointmentId;
  final DateTime? oldDate;
  final String? oldProfessional;
  final String? oldServiceName;

  const PublicShopPage({
    super.key,
    required this.slug,
    this.isReschedule = false,
    this.rescheduleAppointmentId,
    this.oldDate,
    this.oldProfessional,
    this.oldServiceName,
  });

  @override
  State<PublicShopPage> createState() => _PublicShopPageState();
}

class _PublicShopPageState extends State<PublicShopPage> {
  String? _selectedCategoryId;
  int _selectedMainTab = 0; // 0 for Serviços, 1 for Produtos

  // FIX: Future criado UMA vez no initState, não a cada rebuild.
  // Criar o Future dentro do build() causava loop eterno de ConnectionState.waiting.
  late Future<Map<String, dynamic>> _shopDataFuture;
  
  Future<void> _launchWhatsApp(String whatsapp) async {
    final phone = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchInstagram(String instagram) async {
    final username = instagram.replaceAll('@', '');
    final uri = Uri.parse('https://instagram.com/$username');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchTikTok(String tiktok) async {
    final username = tiktok.replaceAll('@', '');
    final uri = Uri.parse('https://tiktok.com/@$username');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchYouTube(String youtube) async {
    final uri = youtube.startsWith('http') ? Uri.parse(youtube) : Uri.parse('https://youtube.com/$youtube');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }



  @override
  void initState() {
    super.initState();
    _shopDataFuture = _fetchShopData();
  }

  Future<void> _handleServiceTap(
    BuildContext context,
    Map<String, dynamic> serviceDoc,
  ) async {
    // ✅ Navegar direto para os detalhes do serviço (Antigamente pedia login aqui)
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ClientServiceDetailPage(
            serviceDoc: serviceDoc,
            isReschedule: widget.isReschedule,
            rescheduleAppointmentId: widget.rescheduleAppointmentId,
            oldDate: widget.oldDate,
            oldProfessional: widget.oldProfessional,
            oldServiceName: widget.oldServiceName,
            fromSubdomain:
                true, // Vindo de subdomínio: após booking, redireciona para ClientHomePage
          ),
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _fetchShopData() async {
    final shop = await Supabase.instance.client
        .from('shops')
        .select()
        .eq('slug', widget.slug)
        .maybeSingle();

    if (shop == null) return {'shop': null};

    final shopId = shop['id'] as String;
    final services = await ShopDataCacheService().getServices(shopId);

    return {'shop': shop, 'services': services};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _shopDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null || snapshot.data!['shop'] == null) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            bottomNavigationBar: const SharedBottomNavBar(selectedIndex: 0),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.store_mall_directory_outlined,
                      size: 100, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text(
                    'Loja não encontrada',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'O link "${widget.slug}" não existe ou foi desativado',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final result = snapshot.data!;
        final data = result['shop'] as Map<String, dynamic>;
        final preloadedServices = result['services'] as List<Map<String, dynamic>>?;
        final shopId = data['id'];
        final whatsapp = data['whatsapp']?.toString() ?? '';
        final instagram = data['instagram']?.toString() ?? '';

        return Scaffold(
          backgroundColor: Colors.white,
          bottomNavigationBar: const SharedBottomNavBar(selectedIndex: 0),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: () {
                    final coverUrl = data['image_url']?.toString() ?? '';
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (coverUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: AppColors.primaryPurple),
                            errorWidget: (context, url, error) => Container(color: Colors.black87),
                          )
                        else
                          Container(color: Colors.black87),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 16,
                          right: 16,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  image: data['logo_url'] != null
                                      ? DecorationImage(
                                          image: NetworkImage(data['logo_url']),
                                          fit: BoxFit.cover)
                                      : null,
                                ),
                                child: data['logo_url'] == null
                                    ? const Icon(Icons.store, size: 36)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      data['name'] ?? 'Loja',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      data['address'] ?? data['endereco'] ?? "Endereço",
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }(),
                ),
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                    },
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bio/Descrição
                      if (data['descricao'] != null && data['descricao'].toString().isNotEmpty) ...[
                        Text(
                          data['descricao'],
                          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Redes Sociais — linha cheia, cor padronizada
                      Builder(builder: (context) {
                        final tiktok = data['tiktok']?.toString() ?? '';
                        final yt = data['youtube']?.toString() ?? '';
                        final chips = <Widget>[];
                        if (whatsapp.isNotEmpty)
                          chips.add(_buildSocialChipItem(icon: FontAwesomeIcons.whatsapp, label: 'WhatsApp', onTap: () => _launchWhatsApp(whatsapp)));
                        if (instagram.isNotEmpty)
                          chips.add(_buildSocialChipItem(icon: FontAwesomeIcons.instagram, label: 'Instagram', onTap: () => _launchInstagram(instagram)));
                        if (tiktok.isNotEmpty)
                          chips.add(_buildSocialChipItem(icon: FontAwesomeIcons.tiktok, label: 'TikTok', onTap: () => _launchTikTok(tiktok)));
                        if (yt.isNotEmpty)
                          chips.add(_buildSocialChipItem(icon: FontAwesomeIcons.youtube, label: 'YouTube', onTap: () => _launchYouTube(yt)));
                        if (chips.isEmpty) return const SizedBox.shrink();
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: chips
                                .expand((chip) => [chip, const SizedBox(width: 8)])
                                .toList()
                              ..removeLast(),
                          ),
                        );
                      }),

                      const SizedBox(height: 20),
                      
                      const Divider(height: 1),
                    ],
                  ),
                ),
              ),

              // Vitrine de Destaques
              SliverToBoxAdapter(
                child: _buildServicesShowcase(preloadedServices, shopId),
              ),

              // TABS: Serviços / Produtos
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Container(
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedMainTab = 0),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _selectedMainTab == 0 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _selectedMainTab == 0 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)] : null,
                              ),
                              child: Center(child: Text("Serviços", style: TextStyle(fontWeight: FontWeight.bold, color: _selectedMainTab == 0 ? AppColors.textPrimary : Colors.grey[600]))),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedMainTab = 1),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _selectedMainTab == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: _selectedMainTab == 1 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)] : null,
                              ),
                              child: Center(child: Text("Produtos", style: TextStyle(fontWeight: FontWeight.bold, color: _selectedMainTab == 1 ? AppColors.textPrimary : Colors.grey[600]))),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // CATEGORY TAGS (Sticky Horizontal Scroll)
              if (_selectedMainTab == 0) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyCategoryDelegate(
                  shopId: shopId,
                  selectedCategoryId: _selectedCategoryId,
                  onCategorySelected: (catId) {
                    setState(() {
                      _selectedCategoryId = catId;
                    });
                  },
                ),
              ),

              // Lista de serviços
              FutureBuilder<List<Map<String, dynamic>>>(
                future: preloadedServices != null
                    ? Future.value(preloadedServices)
                    : Supabase.instance.client
                        .from('services')
                        .select()
                        .eq('shop_id', shopId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    debugPrint('PublicShopPage: Erro ao buscar serviços: ${snapshot.error}');
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'Erro ao carregar serviços.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  // ✅ FIX: Filtro local — null é tratado como ativo (dados migrados)
                  var services = List<Map<String, dynamic>>.from(snapshot.data!)
                      .where((s) {
                        final isActive = s['is_active'];
                        // null = sem coluna (migrado), true = ativo, false = inativo
                        return isActive == null || isActive == true;
                      })
                      .toList();

                  debugPrint('PublicShopPage: ${snapshot.data!.length} serviços no banco, '
                      '${services.length} ativos para shopId=$shopId');

                  // Aplicar filtro de categoria manualmente
                  if (_selectedCategoryId != null) {
                    services = services.where((sData) {
                      final ids = sData['category_ids'] != null 
                          ? List<String>.from(sData['category_ids']) 
                          : (sData['categoryId'] != null ? [sData['categoryId'].toString()] : []);
                      return ids.contains(_selectedCategoryId);
                    }).toList();
                  }

                  if (services.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            "Nenhum serviço disponível no momento.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    );
                  }

                  // ✅ Ordenar serviços em ordem alfabética
                  var sortedServices = List<Map<String, dynamic>>.from(services);
                  sortedServices.sort((a, b) {
                    final strA = (a['name'] ?? '').toString().toLowerCase();
                    final strB = (b['name'] ?? '').toString().toLowerCase();
                    return strA.compareTo(strB);
                  });

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final sData = sortedServices[index];
                        dynamic rawFotos = sData['photos_urls'] ??
                            sData['fotos_urls'] ??
                            sData['fotos'] ??
                            sData['imageUrl'] ??
                            sData['imagens'];

                        String? serviceThumb;
                        if (rawFotos is List && rawFotos.isNotEmpty) {
                          serviceThumb = rawFotos.first.toString();
                        } else if (rawFotos is String && rawFotos.isNotEmpty) {
                          serviceThumb = rawFotos;
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _handleServiceTap(context, sData),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 70,
                                          height: 70,
                                          color: Colors.grey[100],
                                          child: serviceThumb != null
                                              ? CachedNetworkImage(
                                                  imageUrl: serviceThumb,
                                                  fit: BoxFit.cover,
                                                )
                                              : PexelsImageWidget(
                                                  searchQuery: ServiceImageKeywords.getEnglishKeyword(sData['name'] ?? ""),
                                                  index: index,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sData['name'] ?? "",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16),
                                              softWrap: true,
                                            ),
                                            const SizedBox(height: 4),
                                            if (sData['description'] != null && sData['description'].toString().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 6),
                                                child: Text(
                                                  sData['description'],
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                                ),
                                              ),
                                            Row(
                                              children: [
                                                Text(
                                                  "R\$ ${sData['price'] ?? '0'}",
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "${sData['duration_min'] ?? 30} min",
                                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: sortedServices.length,
                    ),
                  );
                },
              ),
              ] else ...[
                // Lista de produtos
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: Supabase.instance.client
                      .from('products')
                      .select()
                      .eq('shop_id', shopId)
                      .eq('is_active', true),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text("Nenhum produto disponível.", style: TextStyle(color: Colors.grey))),
                        ),
                      );
                    }

                    final products = snapshot.data!;
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.58,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final p = products[index];
                            return _buildProductCard(context, p, whatsapp);
                          },
                          childCount: products.length,
                        ),
                      ),
                    );
                  },
                ),
              ],

              // Mini-Mapa
              SliverToBoxAdapter(
                child: _buildMiniMap(data),
              ),

              // Avaliações do Google (Depois do Mapa)
              if (data['google_business'] != null &&
                  data['google_business']['place_id'] != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: GoogleReviewsWidget(
                      placeId: data['google_business']['place_id'],
                    ),
                  ),
                ),

              // Espaço final
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }
}

// Delegate para manter as categorias fixas no topo ao rolar
class _StickyCategoryDelegate extends SliverPersistentHeaderDelegate {
  final String shopId;
  final String? selectedCategoryId;
  final Function(String?) onCategorySelected;

  _StickyCategoryDelegate({
    required this.shopId,
    required this.selectedCategoryId,
    required this.onCategorySelected,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white, // Fundo branco para as categorias também
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        // ✅ FIX: A tabela 'categories' usa shop_id (snake_case)
        stream: Supabase.instance.client
            .from('categories')
            .stream(primaryKey: ['id'])
            .eq('shop_id', shopId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('❌ Erro no Stream de Categorias: ${snapshot.error}');
            return const SizedBox();
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            debugPrint('ℹ️ PublicShopPage: Nenhuma categoria encontrada para shop_id=$shopId');
            return const SizedBox();
          }

          final categories = List<Map<String, dynamic>>.from(snapshot.data!);
          categories.sort((a, b) {
            // ✅ FIX: A tabela 'categories' usa 'name' (inglês) no Supabase
            final nameA = (a['name'] ?? '').toString().toLowerCase();
            final nameB = (b['name'] ?? '').toString().toLowerCase();
            return nameA.compareTo(nameB);
          });

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final category = isAll ? null : categories[index - 1];
              final catId = isAll ? null : category!['id']?.toString();
              // ✅ FIX: A tabela 'categories' usa 'name'
              final catName = isAll ? "Todos" : category!['name'] ?? "Sem Nome";
              final isSelected = selectedCategoryId == catId;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FilterChip(
                  label: Text(
                    catName,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) => onCategorySelected(catId),
                  backgroundColor: Colors.white,
                  selectedColor: AppColors.primaryPurple,
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primaryPurple
                          : Colors.grey.shade300,
                    ),
                  ),
                  elevation: isSelected ? 4 : 0,
                  pressElevation: 8,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  double get maxExtent => 58; // Altura do container + padding

  @override
  double get minExtent => 58;

  @override
  bool shouldRebuild(covariant _StickyCategoryDelegate oldDelegate) {
    return oldDelegate.selectedCategoryId != selectedCategoryId ||
        oldDelegate.shopId != shopId;
  }
}

// Card de Produto (Vitrine)
Widget _buildProductCard(BuildContext context, Map<String, dynamic> product, String whatsapp) {
  final isAffiliate = product['is_affiliate'] == true;
  final imageUrl = product['image_url']?.toString();
  final price = product['price'] as num?;
  
  String priceStr = '';
  if (price != null && price > 0) {
    priceStr = "R\$ ${price.toStringAsFixed(2).replaceAll('.', ',')}";
  } else {
    priceStr = isAffiliate ? "Ver Oferta" : "Consultar";
  }
  
  return GestureDetector(
    onTap: () async {
      if (isAffiliate && product['affiliate_url'] != null) {
        final uri = Uri.tryParse(product['affiliate_url']);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        if (whatsapp.isNotEmpty) {
          final phone = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
          final priceText = (price != null && price > 0) ? "no valor de $priceStr" : "";
          final msg = Uri.encodeComponent("Olá, tenho interesse no produto *${product['name']}* $priceText.");
          final uri = Uri.parse('https://wa.me/$phone?text=$msg');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp da loja indisponível')));
        }
      }
    },
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Container(
                color: Colors.grey[100],
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, color: Colors.grey),
                      )
                    : const Icon(Icons.inventory_2, size: 40, color: Colors.grey),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Text(
                    product['name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceStr,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: (price != null && price > 0) ? AppColors.primaryPurple : Colors.grey[700],
                      fontSize: (price != null && price > 0) ? 16 : 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        isAffiliate ? "Comprar" : "Pedir no WhatsApp",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

// Chip padronizado para redes sociais (linha cheia, cor da marca)
Widget _buildSocialChipItem({required IconData icon, required String label, required VoidCallback onTap}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryPurple.withValues(alpha: 0.20),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaIcon(icon, color: AppColors.primaryPurple, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryPurple,
            ),
          ),
        ],
      ),
    ),
  );
}

// Widget da Vitrine de Destaques
Widget _buildServicesShowcase(List<Map<String, dynamic>>? preloadedServices, String shopId) {
  if (preloadedServices != null && preloadedServices.isNotEmpty) {
    final featured = preloadedServices.where((s) => (s['is_active'] == null || s['is_active'] == true) && (s['is_featured'] ?? false) == true).toList();
    if (featured.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 15),
          child: Row(
            children: [
              Icon(Icons.stars, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text("Destaques da Vitrine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            scrollDirection: Axis.horizontal,
            itemCount: featured.length,
            itemBuilder: (context, index) {
              final data = featured[index];
              dynamic fotosData = data['photos_urls'] ?? data['fotos_urls'] ?? data['fotos'] ?? data['imageUrl'] ?? data['imagens'];
              String? thumb = fotosData is String ? fotosData : (fotosData is List && fotosData.isNotEmpty ? fotosData.first.toString() : null);

              if (thumb == null) return const SizedBox.shrink();

              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClientServiceDetailPage(serviceDoc: data, fromSubdomain: true))),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                              ),
                            ),
                            child: Text(
                              data['name'] ?? "Serviço",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  return FutureBuilder<List<Map<String, dynamic>>>(
    future: Supabase.instance.client
        .from('services')
        .select()
        .eq('shop_id', shopId),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

      final activeServices = snapshot.data!.where((s) => s['is_active'] == null || s['is_active'] == true).toList();
      final docsWithPhotos = activeServices.where((data) => (data['is_featured'] ?? false) == true).toList();

      if (docsWithPhotos.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 15),
            child: Row(
              children: [
                Icon(Icons.stars, color: Colors.amber, size: 20),
                SizedBox(width: 8),
                Text("Destaques da Vitrine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              scrollDirection: Axis.horizontal,
              itemCount: docsWithPhotos.length,
              itemBuilder: (context, index) {
                final data = docsWithPhotos[index];
                dynamic fotosData = data['photos_urls'] ?? data['fotos_urls'] ?? data['fotos'] ?? data['imageUrl'] ?? data['imagens'];
                String? thumb = fotosData is String ? fotosData : (fotosData is List && fotosData.isNotEmpty ? fotosData.first.toString() : null);

                if (thumb == null) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ClientServiceDetailPage(serviceDoc: data, fromSubdomain: true))),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover),
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                  colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                                ),
                              ),
                              child: Text(
                                data['name'] ?? "Serviço",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      );
    },
  );
}

// Widget do Mini-Mapa
Widget _buildMiniMap(Map<String, dynamic> data) {
  final fullAddress = _formatFullAddressStatic(data);
  if (fullAddress.isEmpty) return const SizedBox.shrink();

  return Builder(
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("LOCALIZAÇÃO", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _showMapOptions(context, data),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _MapTileWidget(fullAddress: fullAddress),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      Positioned(
                        right: 12, bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                          child: const Row(
                            children: [
                              Icon(Icons.directions, size: 18, color: AppColors.primaryPurple),
                              SizedBox(width: 4),
                              Text("Como chegar", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
  );
}

void _showMapOptions(BuildContext context, Map<String, dynamic> data) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => AppMapSelectionDialogAlt(
      onMaps: () { Navigator.pop(ctx); _launchMapsStatic(data); },
      onWaze: () { Navigator.pop(ctx); _launchWazeStatic(data); },
    ),
  );
}

// Funções Estáticas para o helper e botões (usadas dentro dos widgets build)
String _formatFullAddressStatic(Map<String, dynamic> data) {
  final street = data['street']?.toString() ?? '';
  final number = data['number']?.toString() ?? '';
  final neighborhood = data['neighborhood']?.toString() ?? '';
  final city = data['city']?.toString() ?? data['cidade']?.toString() ?? '';
  final state = data['state']?.toString() ?? data['estado']?.toString() ?? '';
  final address = data['address']?.toString() ?? data['endereco']?.toString() ?? '';

  String full = '';
  if (street.isNotEmpty) {
    full = street;
    if (number.isNotEmpty) full += ', $number';
    if (neighborhood.isNotEmpty) full += ' - $neighborhood';
    if (city.isNotEmpty) full += ', $city';
    if (state.isNotEmpty) full += ' - $state';
  } else if (address.isNotEmpty) {
    full = address;
    if (city.isNotEmpty) full += ', $city';
    if (state.isNotEmpty) full += ' - $state';
  }

  // Debug (Remover após teste se necessário)
  if (full.isEmpty) {
    debugPrint('⚠️ PublicShopPage: Endereço vazio para o mapa.');
  }

  return full;
}

Future<void> _launchMapsStatic(Map<String, dynamic> data) async {
  final address = _formatFullAddressStatic(data);
  final query = Uri.encodeComponent(address);
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _launchWazeStatic(Map<String, dynamic> data) async {
  final address = _formatFullAddressStatic(data);
  final query = Uri.encodeComponent(address);
  final uri = Uri.parse('https://waze.com/ul?q=$query&navigate=yes');
  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<LatLng?> _geocodeAddress(String address) async {
  try {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(address)}'
      '&format=json&limit=1',
    );
    final response = await http.get(url, headers: {
      'User-Agent': 'MarkaAI/1.0 (suporte@markaai.com.br)',
    });
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        return LatLng(
          double.parse(data[0]['lat'].toString()),
          double.parse(data[0]['lon'].toString()),
        );
      }
    }
  } catch (_) {}
  return null;
}

class _MapTileWidget extends StatelessWidget {
  final String fullAddress;
  const _MapTileWidget({required this.fullAddress});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LatLng?>(
      future: _geocodeAddress(fullAddress),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final pos = snapshot.data!;
          return FlutterMap(
            options: MapOptions(
              center: pos,
              zoom: 16.0,
              interactiveFlags: InteractiveFlag.none,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.markaai.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: pos,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                  ),
                ],
              ),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: AppColors.softGrey,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
          );
        }
        return Container(
          color: AppColors.softGrey,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text("Ver no Mapa", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}

class AppMapSelectionDialogAlt extends StatelessWidget {
  final VoidCallback onMaps;
  final VoidCallback onWaze;
  const AppMapSelectionDialogAlt({super.key, required this.onMaps, required this.onWaze});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Escolha o app de navegação", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.map, color: Colors.blue),
            title: const Text("Google Maps"),
            onTap: onMaps,
          ),
          ListTile(
            leading: const Icon(FontAwesomeIcons.waze, color: Color(0xFF33CCFF)),
            title: const Text("Waze"),
            onTap: onWaze,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}


