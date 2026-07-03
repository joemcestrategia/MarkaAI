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
  int _refreshKey = 0;

  // Controle do Painel Lateral (Apenas Desktop)
  bool _showPanel = false;
  Map<String, dynamic>? _employeeToEdit;

  // Ordenação de prioridade de escala
  List<Map<String, dynamic>> _orderedEmployees = [];
  bool _isSavingPriority = false;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _savePriorities(List<Map<String, dynamic>> employees) async {
    if (shopId == null) return;
    setState(() => _isSavingPriority = true);
    try {
      for (int i = 0; i < employees.length; i++) {
        await sb.Supabase.instance.client
            .from('employees')
            .update({'schedule_priority': i})
            .eq('id', employees[i]['id'].toString());
      }
    } catch (e) {
      debugPrint('❌ Erro ao salvar prioridades de escala: $e');
    } finally {
      if (mounted) setState(() => _isSavingPriority = false);
    }
  }

  // 🛡️ CARREGAMENTO DE ID BLINDADO
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
      ).then((_) { if (mounted) setState(() => _refreshKey++); });
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
        _refreshKey++;
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
        // CABEÇALHO MODERNO
        Container(
          padding: EdgeInsets.fromLTRB(isMobile ? 20 : 32, isMobile ? 24 : 32, isMobile ? 20 : 32, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Membros da Equipe",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.deepPurple, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(Icons.drag_handle, size: 14, color: AppColors.primaryPurple),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Arraste os cards para definir a ordem (prioridade) na agenda.",
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _handleMemberTap(context, null, isMobile),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(isMobile ? "NOVO" : "NOVO MEMBRO", style: const TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: AppColors.primaryPurple.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),

        // LISTA
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey('emp_stream_$_refreshKey'),
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

              // Sincroniza _orderedEmployees com dados do stream (preservando ordem de prioridade)
              if (!_isSavingPriority) {
                final newData = snapshot.data!;
                final sortedFromServer = [...newData]
                  ..sort((a, b) => ((a['schedule_priority'] ?? 0) as int)
                      .compareTo((b['schedule_priority'] ?? 0) as int));

                final currentIds = _orderedEmployees
                    .map((e) => e['id'].toString())
                    .join(',');
                final serverIds = sortedFromServer
                    .map((e) => e['id'].toString())
                    .join(',');

                if (currentIds != serverIds) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _orderedEmployees = sortedFromServer);
                  });
                }
              }

              final displayList = _orderedEmployees.isNotEmpty
                  ? _orderedEmployees
                  : snapshot.data!;

              return Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: Colors.transparent,
                ),
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final data = displayList[index];
                    final bool isSelected =
                        !isMobile && _showPanel && _employeeToEdit?['id'] == data['id'];
                    return Padding(
                      key: ValueKey(data['id']),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () => _handleMemberTap(context, data, isMobile),
                        child: _buildEmployeeCard(data, isSelected),
                      ),
                    );
                  },
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final updated = List<Map<String, dynamic>>.from(_orderedEmployees.isNotEmpty
                          ? _orderedEmployees
                          : snapshot.data!);
                      final item = updated.removeAt(oldIndex);
                      updated.insert(newIndex, item);
                      _orderedEmployees = updated;
                    });
                    _savePriorities(_orderedEmployees);
                  },
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.transparent,
                      child: child,
                    );
                  },
                ),
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
        color: isSelected ? AppColors.primaryPurple.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.primaryPurple.withValues(alpha: 0.5) : AppColors.border.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? AppColors.primaryPurple.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: isSelected ? AppColors.primaryPurple : AppColors.surface,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.surface,
                backgroundImage: (data['photo_url'] != null && data['photo_url'].isNotEmpty)
                    ? CachedNetworkImageProvider(data['photo_url'])
                    : null,
                child: (data['photo_url'] == null || data['photo_url'].isEmpty)
                    ? Icon(Icons.person_rounded, color: isSelected ? AppColors.primaryPurple : AppColors.textSecondary, size: 28)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'] ?? "Sem nome",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isSelected ? AppColors.primaryPurple : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      "${data['start_time'] ?? '--:--'} às ${data['end_time'] ?? '--:--'}",
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isSavingPriority)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryPurple),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 24),
            ),
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
