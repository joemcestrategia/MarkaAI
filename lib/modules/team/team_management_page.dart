import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import 'employee_register_page.dart';

class TeamManagementPage extends StatefulWidget {
  const TeamManagementPage({super.key});

  @override
  State<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends State<TeamManagementPage> {
  String? shopId;
  bool _isLoading = true;
  late PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;
  int _currentEmployeeCount = 0;

  // Controle do Painel Lateral (Apenas Desktop)
  bool _showPanel = false;
  Map<String, dynamic>? _employeeToEdit;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  // ðŸ›¡ï¸ CARREGAMENTO DE ID BLINDADO
  Future<void> _loadShopId() async {
    String? id = await SessionService.getShopId();
    if (id == null || id.isEmpty) {
      final user = AuthService().currentUser;
      if (user != null) {
        final doc = await sb.Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (doc != null) {
          id = doc['shop_id'];
        }
      }
    }

    if (id != null) {
      // Features are now handled by StreamBuilder in build()
    }

    if (mounted) {
      setState(() {
        shopId = id;
        _isLoading = false;
      });
    }
  }

  // 🧠 NAVEGAÇÃO INTELIGENTE (O Segredo da Responsividade)
  void _handleMemberTap(
      BuildContext context, Map<String, dynamic>? doc, bool isMobile) {
    if (doc == null) {
      // Validar Limite antes de permitir novo cadastro
      if (_currentEmployeeCount >= _currentFeatures.maxProfessionals) {
        UpgradeModal.show(context,
            featureName: "Adicionar Profissionais",
            requiredPlan: (_currentFeatures.maxProfessionals == 1)
                ? "START"
                : (_currentFeatures.maxProfessionals == 2)
                    ? "PLUS"
                    : "PRO");
        return;
      }
    }

    if (isMobile) {
      // 📱 MODO CELULAR: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(doc == null ? "Novo Membro" : "Editar Membro"),
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: EmployeeRegisterPage(
              key: ValueKey(doc?['id'] ?? 'novo'), // Força recriação
              employeeToEdit: doc,
              onClose: () => Navigator.pop(context), // Fecha a tela no mobile
            ),
          ),
        ),
      );
    } else {
      // 💻 MODO PC: Abre painel lateral
      _openPanelDesktop(doc);
    }
  }

  void _openPanelDesktop(Map<String, dynamic>? doc) {
    setState(() {
      _showPanel = false;
    }); // Reseta para forçar rebuild
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {
          _employeeToEdit = doc;
          _showPanel = true;
        });
      }
    });
  }

  void _closePanelDesktop() {
    if (mounted) {
      setState(() {
        _showPanel = false;
        _employeeToEdit = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple));
    }
    if (shopId == null) {
      return const Center(child: Text("Erro: Loja não identificada."));
    }

    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _currentFeatures = snapshot.data!;
        }

        // 🛡️ O GUARDIÃO DO LAYOUT
        return LayoutBuilder(
          builder: (context, constraints) {
            bool isMobile = constraints.maxWidth < 850;

            if (isMobile) {
              // --- LAYOUT MOBILE (Só Lista) ---
              return Material(
                color: const Color(0xFFF2F4F8),
                child: _buildListContent(isMobile),
              );
            } else {
              // --- LAYOUT DESKTOP (Split View) ---
              return Material(
                color: const Color(0xFFF2F4F8),
                child: Row(
                  children: [
                    // COLUNA 2: LISTA
                    Expanded(
                      flex: 3,
                      child: _buildListContent(isMobile),
                    ),
                    // COLUNA 3: PAINEL
                    VerticalDivider(width: 1, color: Colors.grey[300]),
                    Expanded(
                      flex: 2,
                      child: Container(
                        color: Colors.white,
                        child: _showPanel
                            ? EmployeeRegisterPage(
                                key: ValueKey(_employeeToEdit?['id'] ?? 'novo_membro'),
                                employeeToEdit: _employeeToEdit,
                                onClose: _closePanelDesktop,
                              )
                            : _buildPlaceholder(),
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        );
      },
    );
  }

  // 🧩 CONTEÚDO DA LISTA (REUSÁVEL)
  Widget _buildListContent(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CABEÇALHO
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Membros da Equipe",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () =>
                    _handleMemberTap(context, null, isMobile), // Novo Membro
                icon: const Icon(Icons.add, size: 18),
                label: Text(isMobile ? "NOVO" : "NOVO MEMBRO"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // LISTA
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: sb.Supabase.instance.client
                .from('employees')
                .stream(primaryKey: ['id'])
                .eq('shop_id', shopId!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Erro: ${snapshot.error}"));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              
              // Atualiza o contador para validação de limite
              _currentEmployeeCount = snapshot.data!.length;

              if (snapshot.data!.isEmpty) return _buildEmptyState();

              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  var data = snapshot.data![index];
                  // No desktop, destaca o selecionado. No mobile, ninguém fica selecionado visualmente.
                  bool isSelected =
                      !isMobile && _showPanel && _employeeToEdit?['id'] == data['id'];

                  return GestureDetector(
                    onTap: () => _handleMemberTap(
                        context, data, isMobile), // Editar Membro
                    child: _buildEmployeeCard(data, isSelected),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> data, bool isSelected) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple.withValues(alpha: 0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: AppColors.primaryPurple, width: 2)
            : Border.all(color: Colors.transparent, width: 2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
            backgroundImage:
                (data['photo_url'] != null && data['photo_url'].isNotEmpty)
                    ? CachedNetworkImageProvider(data['photo_url'])
                    : null,
            child: (data['photo_url'] == null || data['photo_url'].isEmpty)
                ? const Icon(Icons.person, color: AppColors.primaryPurple)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? "Sem nome",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  "🕒 ${data['start_time'] ?? '--:--'} às ${data['end_time'] ?? '--:--'}",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Opacity(
        opacity: 0.1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.badge_outlined, size: 100),
            SizedBox(height: 16),
            Text("Selecione um membro para editar"),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("Nenhum membro cadastrado",
              style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}
