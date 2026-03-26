import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import 'service_register_page.dart';
import 'category_management_page.dart';
import '../../core/utils/service_image_keywords.dart';
import '../../core/widgets/pexels_image_widget.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/shop_data_cache_service.dart';
import 'package:flutter/foundation.dart';

// --- CLASSE DE DETALHES (MANTIDA E OTIMIZADA) ---
class ServiceDetailsPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String id;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const ServiceDetailsPage({
    super.key,
    required this.data,
    required this.id,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    List<dynamic> fotos = data['photos_urls'] ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: Colors.white,
          height: constraints.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Detalhes",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 20, color: AppColors.primaryPurple),
                          onPressed: onEdit,
                          tooltip: "Editar",
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: onClose,
                          tooltip: "Fechar",
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // CONTEÚDO COM SCROLL (Para não quebrar em telas pequenas)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // GALERIA
                      if (fotos.isNotEmpty)
                        SizedBox(
                          height:
                              200, // Aumentei um pouco para ficar mais bonito
                          width: double.infinity,
                          child: PageView.builder(
                            itemCount: fotos.length,
                            itemBuilder: (context, i) => Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: fotos[i],
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey[100]),
                                  errorWidget: (context, url, error) =>
                                      const Icon(Icons.error),
                                ),
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "${i + 1}/${fotos.length}",
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 150,
                          width: double.infinity,
                          color: Colors.grey[50],
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.image_not_supported,
                                  size: 30, color: Colors.grey),
                              Text("Sem fotos",
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12))
                            ],
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? "",
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildBadge(data['category'] ?? "Serviço",
                                    AppColors.primaryPurple),
                                if (data['is_active'] == false) ...[
                                  const SizedBox(width: 8),
                                  _buildBadge("INATIVO", Colors.red),
                                ]
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoCard(
                                    Icons.timer_outlined,
                                    "Duração",
                                    "${data['duration_min']} min",
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildInfoCard(
                                    Icons.attach_money,
                                    "Valor",
                                    "R\$ ${data['price']}",
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              "Descrição",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['description']?.toString().isNotEmpty == true
                                  ? data['description']
                                  : "Nenhuma descrição.",
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 40), // Espaço extra final
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            // Adicionado Expanded para evitar overflow de texto
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- PÁGINA DE GESTÃO (AGORA RESPONSIVA) ---
class ServicesManagementPage extends StatefulWidget {
  const ServicesManagementPage({super.key});

  @override
  State<ServicesManagementPage> createState() => _ServicesManagementPageState();
}

class _ServicesManagementPageState extends State<ServicesManagementPage> {
  String? shopId;
  bool _isLoading = true;
  int _refreshKey = 0;

  // Controle Desktop
  bool _showPanel = false;
  bool _isEditing = false;
  Map<String, dynamic>? _selectedService;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    try {
      final id = await SessionService.getShopId();
      if (mounted) {
        setState(() {
          shopId = id;
          _isLoading = false;
        });
      }

      if (id == null || id.isEmpty) {
        await _loadShopIdFromUser();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadShopIdFromUser() async {
    try {
      final user = AuthService().currentUser;
      if (user != null) {
        final userDoc = await sb.Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (userDoc != null) {
          if (mounted) {
            setState(() {
              shopId = userDoc['shop_id'];
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Erro load user shop: $e");
    }
  }

  // 🧠 CÉREBRO DA NAVEGAÇÃO: Decide se abre painel (PC) ou navega (Mobile)
  void _handleServiceTap(
      BuildContext context, Map<String, dynamic> data, bool isMobile) {
    if (isMobile) {
      // 📱 MOBILE: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: ServiceDetailsPage(
                data: data,
                id: data['id'],
                onClose: () => Navigator.pop(context),
                onEdit: () {
                  // Ao clicar em editar dentro do mobile, empilhamos a tela de edição
                  Navigator.pop(context); // Fecha detalhes
                  _handleCreateTap(context, isMobile,
                      docToEdit: data); // Abre edição
                },
              ),
            ),
          ),
        ),
      ).then((_) { if (mounted) setState(() => _refreshKey++); });
    } else {
      // 💻 DESKTOP: Abre painel lateral
      _openDetailsModeDesktop(data);
    }
  }

  void _handleCreateTap(BuildContext context, bool isMobile,
      {Map<String, dynamic>? docToEdit}) {
    if (isMobile) {
      // 📱 MOBILE: Navega para tela de cadastro
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title:
                  Text(docToEdit == null ? "Novo Serviço" : "Editar Serviço"),
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: ServiceRegisterPage(
              serviceToEdit: docToEdit,
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      ).then((_) { if (mounted) setState(() => _refreshKey++); });
    } else {
      // 💻 DESKTOP: Abre painel lateral
      if (docToEdit != null) {
        _openEditModeDesktop(docToEdit);
      } else {
        _openCreateModeDesktop();
      }
    }
  }

  // --- Funções de Estado para Desktop ---
  void _openCreateModeDesktop() {
    setState(() {
      _selectedService = null;
      _isEditing = true;
      _showPanel = true;
    });
  }

  void _openDetailsModeDesktop(Map<String, dynamic> data) {
    setState(() {
      _showPanel = false;
    }); // Reset para rebuild
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {
          _selectedService = data;
          _isEditing = false;
          _showPanel = true;
        });
      }
    });
  }

  void _openEditModeDesktop(Map<String, dynamic> data) {
    setState(() {
      _selectedService = data;
      _isEditing = true;
      _showPanel = true;
    });
  }

  void _openCategoryManagement(BuildContext context) {
    if (shopId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoryManagementPage(shopId: shopId!),
      ),
    );
  }

  void _closePanel() {
    setState(() {
      _showPanel = false;
      _selectedService = null;
      _isEditing = false;
      _refreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primaryPurple)),
      );
    }

    // 2. Erro ShopId
    if (shopId == null || shopId!.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text("Erro ao carregar loja"),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadShopId();
                },
                child: const Text("Tentar Novamente"),
              ),
            ],
          ),
        ),
      );
    }

    // 3. ðŸ›¡ï¸ LAYOUT RESPONSIVO (O Guardião)
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 850;

        // No mobile, usamos Scaffold normal com FAB. No desktop, o botão fica no header.
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          floatingActionButton: isMobile // Só mostra FAB no mobile
              ? FloatingActionButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (context) => Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.add_circle_outline, color: AppColors.primaryPurple),
                              title: const Text("Criar Novo Serviço"),
                              onTap: () {
                                Navigator.pop(context);
                                _handleCreateTap(context, isMobile);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.category_outlined, color: AppColors.primaryPurple),
                              title: const Text("Gerenciar Categorias"),
                              onTap: () {
                                Navigator.pop(context);
                                _openCategoryManagement(context);
                              },
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    );
                  },
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
          body: isMobile
              ? _buildListContent(isMobile) // Mobile: Só lista
              : Row(
                  // Desktop: Lista + Painel
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildListContent(isMobile),
                    ),
                    if (_showPanel) ...[
                      VerticalDivider(width: 1, color: Colors.grey[300]),
                      Expanded(
                        flex: 2,
                        child: _isEditing
                            ? ServiceRegisterPage(
                                key: ValueKey(_selectedService?['id'] ??
                                    'novo'), // Força rebuild
                                serviceToEdit: _selectedService,
                                onClose: _closePanel,
                              )
                            : ServiceDetailsPage(
                                data: _selectedService!,
                                id: _selectedService!['id'],
                                onClose: _closePanel,
                                onEdit: () =>
                                    _openEditModeDesktop(_selectedService!),
                              ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // 🧩 WIDGET DE LISTA REUSÁVEL
  Widget _buildListContent(bool isMobile) {
    return Column(
      children: [
        // CABEÇALHO DA LISTA
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // No Mobile, o botão de novo serviço é um FAB.
              // No Desktop, ele fica no topo à direita.
              if (!isMobile) ...[
                OutlinedButton.icon(
                  onPressed: () => _openCategoryManagement(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryPurple,
                    side: const BorderSide(color: AppColors.primaryPurple),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.category_outlined, size: 18),
                  label: const Text("CATEGORIAS"),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _handleCreateTap(context, isMobile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("NOVO SERVIÇO"),
                ),
              ],
            ],
          ),
        ),

        // LISTA (STREAM)
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('svc_stream_$_refreshKey'),
            stream: sb.Supabase.instance.client
                .from('services')
                .stream(primaryKey: ['id'])
                .eq('shop_id', shopId!)
                .order('name')
                .map((list) {
                  list.sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
                  return list;
                }),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryPurple));
              }

              if (snapshot.hasError) {
                return Center(child: Text("Erro: ${snapshot.error}"));
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  var data = snapshot.data![index];
                  // Seleção visual apenas no Desktop
                  bool isSelected =
                      !isMobile && _showPanel && _selectedService?['id'] == data['id'];

                  return GestureDetector(
                    onTap: () => _handleServiceTap(context, data, isMobile),
                    child: Container(
                      decoration: isSelected
                          ? BoxDecoration(
                              border: Border.all(
                                  color: AppColors.primaryPurple, width: 2),
                              borderRadius: BorderRadius.circular(14),
                            )
                          : null,
                      child: _buildCompactCard(data, index),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(Map<String, dynamic> data, int index) {
    List<dynamic> fotos = data['photos_urls'] ?? [];
    String nome = data['name'] ?? "";
    bool ativo = data['is_active'] ?? true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 70,
              height: 70,
              child:
                  _buildSmartImage(fotos, nome, data['categoria'] ?? "", index),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: ativo ? Colors.black87 : Colors.grey,
                    decoration: ativo ? null : TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildTag(Icons.access_time, "${data['duration_min']} min",
                        Colors.blue),
                    const SizedBox(width: 8),
                    _buildTag(Icons.attach_money, "R\$ ${data['price']}",
                        Colors.green),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
            onPressed: () => _showOptions(data),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.content_cut, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            "Nenhum serviço cadastrado",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            "Clique em 'Novo Serviço' para começar",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartImage(
      List<dynamic> fotos, String nome, String categoria, int index) {
    if (fotos.isNotEmpty) {
      return CachedNetworkImage(
        // Usar CachedNetworkImage aqui também é melhor
        imageUrl: fotos[0],
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[100]),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    }
    return PexelsImageWidget(
      searchQuery: ServiceImageKeywords.getEnglishKeyword(nome),
      index: index,
    );
  }

  void _showOptions(Map<String, dynamic> data) {
    final String nome = data['name'] ?? "Serviço";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.only(top: 12, bottom: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),

            // Header/Service Preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined,
                      color: AppColors.primaryPurple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Gerenciar Serviço",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          nome,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Options
            _buildModalItem(
              icon: Icons.edit_outlined,
              label: "Editar Informações",
              color: Colors.black87,
              onTap: () {
                Navigator.pop(context);
                bool isMobile = MediaQuery.of(context).size.width < 850;
                if (isMobile) {
                  _handleCreateTap(context, true, docToEdit: data);
                } else {
                  _openEditModeDesktop(data);
                }
              },
            ),

            _buildModalItem(
              icon: Icons.delete_outline,
              label: "Excluir Serviço",
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(data['id']);
              },
            ),
          ],
        ),
      ),
    ).then((_) { if (mounted) setState(() => _refreshKey++); });
  }

  Widget _buildModalItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing:
          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
    );
  }

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir Serviço?"),
        content: const Text("Esta ação não pode ser desfeita."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () async {
              try {
                await sb.Supabase.instance.client
                    .from('services')
                    .delete()
                    .eq('id', docId);
                
                ShopDataCacheService().invalidate(shopId!, 'services');

                if (_selectedService?['id'] == docId) _closePanel();
                if (mounted) Navigator.pop(context);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Serviço excluído com sucesso"),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Erro ao excluir: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text("Excluir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((_) { if (mounted) setState(() => _refreshKey++); });
  }
}

