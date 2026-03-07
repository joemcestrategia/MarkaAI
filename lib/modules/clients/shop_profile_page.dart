import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/google_reviews_widget.dart';

class ShopProfilePage extends StatefulWidget {
  final DocumentSnapshot shopDoc;
  final Function(DocumentSnapshot) onBookService;

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

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.shopDoc.id)
        .get();
    if (mounted) {
      setState(() {
        _isFavorite = doc.exists;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.shopDoc.id);
    setState(() => _isFavorite = !_isFavorite);
    try {
      if (_isFavorite) {
        await ref.set({'added_at': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !_isFavorite);
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

  @override
  Widget build(BuildContext context) {
    final data = widget.shopDoc.data() as Map<String, dynamic>;
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final whatsapp = data['whatsapp']?.toString() ?? '';
    final instagram = data['instagram']?.toString() ?? '';

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
                final coverUrl = data['coverUrl']?.toString() ??
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
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data['nome'] ?? "Nome",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  data['endereco'] ?? "Endereço",
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
                  // Space reserved - primary header is inside the cover
                  if (whatsapp.isNotEmpty || instagram.isNotEmpty)
                    Row(
                      children: [
                        if (whatsapp.isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _launchWhatsApp(whatsapp),
                              icon: const FaIcon(FontAwesomeIcons.whatsapp,
                                  size: 20),
                              label: const Text("WhatsApp"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
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
                              onPressed: () => _launchInstagram(instagram),
                              icon: const FaIcon(FontAwesomeIcons.instagram,
                                  size: 20),
                              label: const Text("Instagram"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE1306C),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
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

          // Lista de serviços
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('services')
                .where('shopId', isEqualTo: widget.shopDoc.id)
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final services = snapshot.data!.docs;
              if (services.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(child: Text("Sem serviços.")),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sDoc = services[index];
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
                                          : const Icon(Icons.spa,
                                              color: Colors.grey),
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
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${sData['tempo_min'] ?? 30} min",
                                          style: const TextStyle(
                                              fontSize: 13, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          currency.format(sData['preco'] ?? 0),
                                          style: const TextStyle(
                                            color: AppColors.primaryPurple,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
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
          const SliverToBoxAdapter(child: SizedBox(height: 8)),

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
}
