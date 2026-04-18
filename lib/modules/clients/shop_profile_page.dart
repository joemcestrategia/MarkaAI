import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/service_image_keywords.dart';
import '../../core/widgets/pexels_image_widget.dart';
import '../../core/constants/api_keys.dart';
import 'package:markaai/widgets/google_reviews_widget.dart';

class ShopProfilePage extends StatefulWidget {
  final Map<String, dynamic> shopDoc;
  final Function(Map<String, dynamic>) onBookService;

  const ShopProfilePage({
    super.key,
    required this.shopDoc,
    required this.onBookService,
  });

  @override
  State<ShopProfilePage> createState() => _ShopProfilePageState();
}

class _ShopProfilePageState extends State<ShopProfilePage> {
  bool _isFavorite = false;
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
    _recordVisit();
  }

  Future<void> _recordVisit() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      await Supabase.instance.client.from('shop_views').insert({
        'user_id': uid,
        'shop_id': widget.shopDoc['id'],
      });
    } catch (e) {
      debugPrint('[ShopProfile] Cannot record visit: $e');
    }
  }

  Future<void> _checkFavorite() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        return;
      }
      final doc = await Supabase.instance.client
          .from('favorites')
          .select()
          .eq('user_id', uid)
          .eq('shop_id', widget.shopDoc['id'])
          .maybeSingle();
      if (mounted) {
        setState(() {
          _isFavorite = doc != null;
        });
      }
    } catch (e) {
      debugPrint('[ShopProfile] Cannot check favorite: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Faça login para favoritar lojas")),
      );
      return;
    }

    final bool wasFavorite = _isFavorite;
    setState(() => _isFavorite = !_isFavorite);

    try {
      if (wasFavorite) {
        // Remover dos favoritos
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .eq('user_id', uid)
            .eq('shop_id', widget.shopDoc['id']);
      } else {
        // Adicionar aos favoritos
        await Supabase.instance.client.from('favorites').insert({
          'user_id': uid,
          'shop_id': widget.shopDoc['id'],
          'shop_name': widget.shopDoc['nome'] ?? widget.shopDoc['name'] ?? '',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint("❌ Erro _toggleFavorite: $e");
      if (mounted) {
        setState(() => _isFavorite = wasFavorite);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao atualizar favoritos: $e")),
        );
      }
    }
  }

  Future<void> _launchWhatsApp(String whatsapp) async {
    // Remove caracteres não numéricos
    final phone = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$phone');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchInstagram(String instagram) async {
    // Remove @ se houver
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
    Uri uri;
    if (youtube.startsWith('http')) {
      uri = Uri.parse(youtube);
    } else {
      uri = Uri.parse('https://youtube.com/$youtube');
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }



  @override
  Widget build(BuildContext context) {
    final data = widget.shopDoc;
    final whatsapp = data['whatsapp']?.toString() ?? '';
    final instagram = data['instagram']?.toString() ?? '';
    final tiktok = data['tiktok']?.toString() ?? '';
    final youtube = data['youtube']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: () {
                final coverUrl = data['image_url']?.toString() ??
                    data['coverUrl']?.toString() ??
                    data['imageUrl']?.toString() ??
                    '';
                Widget cover;
                if (coverUrl.isNotEmpty &&
                    (coverUrl.startsWith('http://') ||
                        coverUrl.startsWith('https://'))) {
                  cover = CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: AppColors.primaryPurple),
                    errorWidget: (context, url, error) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [
                              AppColors.primaryPurple,
                              Color(0xFF4A148C)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                      ),
                      child: const Center(
                          child: Icon(Icons.store,
                              color: Colors.white70, size: 48)),
                    ),
                  );
                } else {
                  cover = Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [AppColors.primaryPurple, Color(0xFF4A148C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                    ),
                    child: const Center(
                        child:
                            Icon(Icons.store, color: Colors.white70, size: 48)),
                  );
                }

                // Overlay logo+name inside the cover
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: ClipRRect(child: cover)),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.35)
                          ],
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
                          () {
                            final lUrl = data['logo_url'] ?? data['logoUrl'];
                            final hasLogo = lUrl != null && lUrl.toString().isNotEmpty;
                            return Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                image: hasLogo
                                    ? DecorationImage(
                                        image: NetworkImage(lUrl.toString()),
                                        fit: BoxFit.cover)
                                    : null,
                              ),
                              child: !hasLogo
                                  ? const Icon(Icons.store, size: 36)
                                  : null,
                            );
                          }(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data['name'] ?? data['nome'] ?? "Nome",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data['address'] ?? data['endereco'] ?? "Endereço",
                                  style: const TextStyle(color: Colors.white70),
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
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : Colors.white,
                  ),
                  onPressed: _toggleFavorite,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Redes Sociais — linha cheia, cor padronizada
                  if (whatsapp.isNotEmpty ||
                      instagram.isNotEmpty ||
                      tiktok.isNotEmpty ||
                      youtube.isNotEmpty)
                    _buildSocialRow(whatsapp, instagram, tiktok, youtube),
                ],
              ),
            ),
          ),

          // Vitrine de Serviços com Fotos
          SliverToBoxAdapter(
            child: _buildServicesShowcase(),
          ),

          // (Reviews will be shown after services)

          // Título "Serviços"
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                "Serviços",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // CATEGORY TAGS (Horizontal Scroll)
          SliverToBoxAdapter(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('categories')
                  .stream(primaryKey: ['id'])
                  .eq('shop_id', widget.shopDoc['id']),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const SizedBox();
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox();
                }

                final categories = List<Map<String, dynamic>>.from(snapshot.data!);
                // Ordenar em memória para evitar necessidade de índices compostos
                categories.sort((a, b) {
                  final nameA = (a['name'] ?? a['nome'] ?? '').toString().toLowerCase();
                  final nameB = (b['name'] ?? b['nome'] ?? '').toString().toLowerCase();
                  return nameA.compareTo(nameB);
                });

                return Container(
                  height: 50,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: categories.length + 1,
                    itemBuilder: (context, index) {
                      final isAll = index == 0;
                      final category = isAll ? null : categories[index - 1];
                      final catId = isAll ? null : category!['id'];
                      final catName = isAll ? "Todos" : (category!['name'] ?? category!['nome'] ?? "");
                      final isSelected = _selectedCategoryId == catId;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: FilterChip(
                          label: Text(
                            catName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryId = catId;
                            });
                          },
                          backgroundColor: Colors.white,
                          selectedColor: AppColors.primaryPurple,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppColors.primaryPurple : Colors.grey.shade300,
                            ),
                          ),
                          elevation: isSelected ? 4 : 0,
                          pressElevation: 8,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // Lista de serviços
          // Lista de serviços
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Supabase.instance.client
                .from('services')
                .select()
                .eq('shop_id', widget.shopDoc['id'])
                .then((list) => list.where((d) => (d['is_active'] ?? d['ativo'] ?? true) == true).toList()),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return SliverToBoxAdapter(
                  child: Center(child: Text("Erro ao carregar: ${snapshot.error}")),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text("Sem serviços.")),
                );
              }

              var services = List<Map<String, dynamic>>.from(snapshot.data!);

              // Aplicar filtro de categoria manualmente
              if (_selectedCategoryId != null) {
                services = services.where((doc) {
                  final sData = doc;
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
                      child: Text("Nenhum serviço nesta categoria.", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }

              // Ordenar serviços em ordem alfabética em memória
              final sortedServices = List<Map<String, dynamic>>.from(services);
              sortedServices.sort((a, b) {
                final strA = (a['name'] ?? '') .toString().toLowerCase();
                final strB = (b['name'] ?? '') .toString().toLowerCase();
                return strA.compareTo(strB);
              });

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sDoc = sortedServices[index];
                    final sData = sDoc;
                    dynamic rawFotos = sData['photos_urls'] ??
                        sData['imageUrl'];

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
                            onTap: () => widget.onBookService(sDoc),
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
                                              searchQuery: ServiceImageKeywords.getEnglishKeyword(sData['nome'] ?? ""),
                                              index: sortedServices.indexOf(sDoc),
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
                                          sData['name'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          sData['description'] ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(
                                              "R\$ ${sData['price'] ?? sData['preco'] ?? '0'}",
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primaryPurple,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.access_time,
                                                size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              "${sData['duration_min'] ?? sData['tempo_min'] ?? '30'} min",
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios,
                                      size: 16, color: Colors.grey),
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
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Mini-Mapa Novo
          SliverToBoxAdapter(
            child: _buildMiniMap(widget.shopDoc),
          ),

          // Avaliações do Google (se conectado) - movidas para depois dos serviços
          if (data['google_business'] != null &&
              data['google_business']['place_id'] != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: GoogleReviewsWidget(
                  placeId: data['google_business']['place_id'],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildServicesShowcase() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('services')
          .select()
          .eq('shop_id', widget.shopDoc['id'])
          .then((list) => list
              .where((d) =>
                  (d['is_active'] ?? d['ativo'] ?? true) == true &&
                  (d['is_featured'] ?? false) == true)
              .toList()),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final featuredServices = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 15),
              child: Row(
                children: [
                  Icon(Icons.stars, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Destaques da Vitrine",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                scrollDirection: Axis.horizontal,
                itemCount: featuredServices.length,
                itemBuilder: (context, index) {
                  final data = featuredServices[index];

                  dynamic fotosData = data['photos_urls'] ??
                      data['fotos'] ??
                      data['image_url'] ??
                      data['imageUrl'] ??
                      data['imagens'];

                  String? thumb;
                  if (fotosData is String) {
                    thumb = fotosData;
                  } else if (fotosData is List && fotosData.isNotEmpty) {
                    thumb = fotosData.first.toString();
                  }

                  if (thumb == null) return const SizedBox.shrink();

                  return GestureDetector(
                    onTap: () => widget.onBookService(data),
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              placeholder: (c, u) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryPurple),
                                ),
                              ),
                              errorWidget: (c, u, e) => Container(
                                color: Colors.grey[300],
                                child: const Icon(Icons.broken_image,
                                    color: Colors.grey),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.8),
                                      Colors.transparent
                                    ],
                                  ),
                                ),
                                child: Text(
                                  data['name'] ?? data['nome'] ?? "Serviço",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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

  Widget _buildSocialRow(String whatsapp, String instagram, String tiktok, String youtube) {
    final chips = <Widget>[];
    if (whatsapp.isNotEmpty)
      chips.add(_buildSocialChip(onPressed: () => _launchWhatsApp(whatsapp), icon: FontAwesomeIcons.whatsapp, label: 'WhatsApp'));
    if (instagram.isNotEmpty)
      chips.add(_buildSocialChip(onPressed: () => _launchInstagram(instagram), icon: FontAwesomeIcons.instagram, label: 'Instagram'));
    if (tiktok.isNotEmpty)
      chips.add(_buildSocialChip(onPressed: () => _launchTikTok(tiktok), icon: FontAwesomeIcons.tiktok, label: 'TikTok'));
    if (youtube.isNotEmpty)
      chips.add(_buildSocialChip(onPressed: () => _launchYouTube(youtube), icon: FontAwesomeIcons.youtube, label: 'YouTube'));
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
  }

  Widget _buildSocialChip({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return InkWell(
      onTap: onPressed,
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

  // --- MÉTODOS DO MINI-MAPA ---

  Widget _buildMiniMap(Map<String, dynamic> data) {
    final fullAddress = _formatFullAddress(data);
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
                        CachedNetworkImage(
                          imageUrl: "https://maps.googleapis.com/maps/api/staticmap?center=${Uri.encodeComponent(fullAddress)}&zoom=15&size=600x300&scale=2&maptype=roadmap&markers=color:red%7C${Uri.encodeComponent(fullAddress)}&key=${ApiKeys.mapsApiKey}",
                          fit: BoxFit.cover,
                          errorWidget: (c, u, e) => Container(
                            color: AppColors.softGrey,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text("Ver no Mapa", style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
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
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Escolha o app de navegação", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.blue),
              title: const Text("Google Maps"),
              onTap: () { Navigator.pop(ctx); _launchMapsStatic(data); },
            ),
            ListTile(
              leading: const Icon(FontAwesomeIcons.waze, color: Color(0xFF33CCFF)),
              title: const Text("Waze"),
              onTap: () { Navigator.pop(ctx); _launchWazeStatic(data); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _formatFullAddress(Map<String, dynamic> data) {
    final street = data['street']?.toString() ?? '';
    final number = data['number']?.toString() ?? '';
    final neighborhood = data['neighborhood']?.toString() ?? '';
    final city = data['city']?.toString() ?? data['cidade']?.toString() ?? '';
    final state = data['state']?.toString() ?? data['estado']?.toString() ?? '';
    final address = data['address']?.toString() ?? '';

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
    return full;
  }

  Future<void> _launchMapsStatic(Map<String, dynamic> data) async {
    final address = _formatFullAddress(data);
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchWazeStatic(Map<String, dynamic> data) async {
    final address = _formatFullAddress(data);
    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://waze.com/ul?q=$query&navigate=yes');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
