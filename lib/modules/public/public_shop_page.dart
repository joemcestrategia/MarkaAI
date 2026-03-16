import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/google_reviews_widget.dart';
import '../../core/utils/service_image_keywords.dart';
import '../../core/widgets/pexels_image_widget.dart';
import '../clients/client_service_detail_page.dart';

class PublicShopPage extends StatefulWidget {
  final String slug;
  final bool isReschedule;
  final String? rescheduleAppointmentId;

  const PublicShopPage({
    super.key,
    required this.slug,
    this.isReschedule = false,
    this.rescheduleAppointmentId,
  });

  @override
  State<PublicShopPage> createState() => _PublicShopPageState();
}

class _PublicShopPageState extends State<PublicShopPage> {
  String? _selectedCategoryId;
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Future<void> _launchWhatsApp(BuildContext context, String whatsapp) async {
    try {
      final phone = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');

      // Tenta abrir o app nativo do WhatsApp primeiro
      final nativeUri = Uri.parse('whatsapp://send?phone=$phone');
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback: abre no navegador
      final webUri = Uri.parse('https://wa.me/$phone');
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _launchInstagram(BuildContext context, String instagram) async {
    try {
      final username = instagram
          .replaceAll('@', '')
          .replaceAll('instagram.com/', '')
          .replaceAll('/', '');

      // Tenta abrir o app nativo do Instagram primeiro
      final nativeUri = Uri.parse('instagram://user?username=$username');
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback: abre no navegador
      final webUri = Uri.parse('https://instagram.com/$username');
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir Instagram: $e')),
        );
      }
    }
  }

  Future<void> _handleServiceTap(
    BuildContext context,
    DocumentSnapshot serviceDoc,
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
            fromSubdomain:
                true, // Vindo de subdomínio: após booking, redireciona para ClientHomePage
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('shops')
          .where('slug', isEqualTo: widget.slug)
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
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

        final shopDoc = snapshot.data!.docs.first;
        final data = shopDoc.data() as Map<String, dynamic>;
        final whatsapp = data['whatsapp']?.toString() ?? '';
        final instagram = data['instagram']?.toString() ?? '';

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: false,
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    data['nome'] ?? 'Loja',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                    ),
                  ),
                  background: Hero(
                    tag: 'cover_${shopDoc.id}',
                    child: () {
                      final coverUrl = data['coverUrl']?.toString() ??
                          data['imageUrl']?.toString() ??
                          '';
                      if (coverUrl.isNotEmpty) {
                        return CachedNetworkImage(
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
                      }
                      return Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [
                                AppColors.primaryPurple,
                                Color(0xFF4A148C)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                        ),
                      );
                    }(),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: logo + name + rating
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade200),
                              image: data['logoUrl'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(data['logoUrl']),
                                      fit: BoxFit.cover)
                                  : null,
                            ),
                            child: data['logoUrl'] == null
                                ? const Icon(Icons.store, size: 36)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['nome'] ?? 'Loja',
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                // Rating stars and score
                                Row(
                                  children: [
                                    if (data['google_business'] != null &&
                                        data['google_business']['rating'] !=
                                            null)
                                      ..._buildStars((data['google_business']
                                              ['rating'] as num)
                                          .toDouble()),
                                    const SizedBox(width: 8),
                                    Text(
                                      data['google_business'] != null &&
                                              data['google_business']
                                                      ['user_ratings_total'] !=
                                                  null
                                          ? '${data['google_business']['rating']} (${data['google_business']['user_ratings_total']})'
                                          : (data['rating'] != null
                                              ? '${data['rating']}'
                                              : ''),
                                      style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data['descricao'] != null &&
                          data['descricao'].toString().isNotEmpty) ...[
                        Text(
                          data['descricao'],
                          style:
                              const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Redes sociais
                      if (whatsapp.isNotEmpty || instagram.isNotEmpty)
                        Row(
                          children: [
                            if (whatsapp.isNotEmpty)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _launchWhatsApp(context, whatsapp),
                                  icon: const FaIcon(FontAwesomeIcons.whatsapp,
                                      size: 20),
                                  label: const Text("WhatsApp"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            if (whatsapp.isNotEmpty && instagram.isNotEmpty)
                              const SizedBox(width: 12),
                            if (instagram.isNotEmpty)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      _launchInstagram(context, instagram),
                                  icon: const FaIcon(FontAwesomeIcons.instagram,
                                      size: 20),
                                  label: const Text("Instagram"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE1306C),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // Título "Serviços"
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text(
                    "Serviços Disponíveis",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // CATEGORY TAGS (Sticky Horizontal Scroll)
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyCategoryDelegate(
                  shopId: shopDoc.id,
                  selectedCategoryId: _selectedCategoryId,
                  onCategorySelected: (catId) {
                    setState(() {
                      _selectedCategoryId = catId;
                    });
                  },
                ),
              ),
              // Helper: function to build star icons (placed after class content)

              // Lista de serviços
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('services')
                    .where('shopId', isEqualTo: shopDoc.id)
                    .where('ativo', isEqualTo: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  var services = snapshot.data!.docs;
                  
                  // Aplicar filtro de categoria manualmente para evitar complexidade de índice no Firestore
                  if (_selectedCategoryId != null) {
                    services = services.where((doc) {
                      final sData = doc.data() as Map<String, dynamic>;
                      final ids = sData['categoryIds'] != null 
                          ? List<String>.from(sData['categoryIds']) 
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

                  // ✅ Ordenar serviços em ordem alfabética (copiando para evitar erro em lista imutável)
                  var sortedServices = List.from(services);
                  sortedServices.sort((a, b) {
                    final strA = (a.data() as Map<String, dynamic>)['nome']
                            ?.toString()
                            .toLowerCase() ??
                        '';
                    final strB = (b.data() as Map<String, dynamic>)['nome']
                            ?.toString()
                            .toLowerCase() ??
                        '';
                    return strA.compareTo(strB);
                  });

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final sDoc = sortedServices[index];
                        final sData = sDoc.data() as Map<String, dynamic>;
                        dynamic rawFotos = sData['fotos_urls'] ??
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
                                onTap: () => _handleServiceTap(context, sDoc),
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
                                                  index: services.indexOf(sDoc),
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
                                              sData['nome'] ?? "",
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16),
                                              softWrap: true,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${sData['tempo_min'] ?? 30} min",
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _currency.format(double.tryParse(
                                                      sData['preco']
                                                              ?.toString() ??
                                                          '0') ??
                                                  0),
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primaryPurple,
                                              ),
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
                      childCount: services.length,
                    ),
                  );
                },
              ),

              // Avaliações do Google (Depois dos Serviços)
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
      color: const Color(0xFFF5F7FA), // Fundo combinando com a página
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('categories')
            .where('shopId', isEqualTo: shopId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const SizedBox();
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const SizedBox();
          }

          final categories = snapshot.data!.docs.toList();
          categories.sort((a, b) {
            final nameA = (a.data() as Map<String, dynamic>)['nome']
                    ?.toString()
                    .toLowerCase() ??
                '';
            final nameB = (b.data() as Map<String, dynamic>)['nome']
                    ?.toString()
                    .toLowerCase() ??
                '';
            return nameA.compareTo(nameB);
          });

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: categories.length + 1,
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final category = isAll ? null : categories[index - 1];
              final catId = isAll ? null : category!.id;
              final catName = isAll ? "Todos" : category!['nome'];
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

// Helper to render star icons for rating
List<Widget> _buildStars(double rating) {
  final full = rating.floor();
  final half = (rating - full) >= 0.5;
  final stars = <Widget>[];
  for (int i = 0; i < 5; i++) {
    if (i < full) {
      stars.add(const Icon(Icons.star, size: 16, color: Colors.amber));
    } else if (i == full && half) {
      stars.add(const Icon(Icons.star_half, size: 16, color: Colors.amber));
    } else {
      stars.add(const Icon(Icons.star_border, size: 16, color: Colors.amber));
    }
  }
  return stars;
}
