import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import 'products_page.dart';
import 'sales_page.dart';
import 'purchases_page.dart';
import 'stock_movements_page.dart';

class InventoryHomePage extends StatefulWidget {
  const InventoryHomePage({super.key});

  @override
  State<InventoryHomePage> createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends State<InventoryHomePage> {
  String? _shopId;
  bool _isLoadingShop = true;
  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    try {
      String? id = await SessionService.getShopId();
      if (id == null || id.isEmpty) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final doc = await Supabase.instance.client
              .from('users')
              .select('shop_id')
              .eq('id', user.id)
              .maybeSingle();
          if (doc != null) id = doc['shop_id'] as String?;
        }
      }
      if (mounted) {
        setState(() {
          _shopId = id;
          _isLoadingShop = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingShop = false);
    }
  }

  void _showUpgradeDialog() {
    UpgradeModal.show(context,
        featureName: 'Módulo de Produtos', requiredPlan: 'Plus');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingShop) {
      return const Scaffold(
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryPurple)));
    }

    if (_shopId == null) {
      return const Scaffold(
          body: Center(child: Text('Erro: Loja não identificada.')));
    }

    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(_shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _currentFeatures = snapshot.data!;
        }

        final isMobile = MediaQuery.of(context).size.width < 768;
        final bool isGated = !_currentFeatures.stockManagement;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FD),
          appBar: AppBar(
            title: const Text('Produtos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline, size: 20),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Guia Rápido'),
                      content: const Text(
                          'Gerencie seu catálogo, acompanhe saídas e otimize suas compras em um só lugar.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Entendi')),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 40,
                      16,
                      isMobile ? 16 : 40,
                      16,
                    ),
                    child: isMobile
                        ? _buildMobileList(isGated)
                        : _buildDesktopGrid(isGated),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileList(bool isGated) {
    return Column(
      children: [
        _ModuleCard(
          icon: Icons.inventory_2_outlined,
          title: 'Produtos',
          description: 'Adicione e controle os itens que você vende',
          color: AppColors.primaryPurple,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductsPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.point_of_sale_outlined,
          title: 'Registrar Venda',
          description: 'Venda produtos diretamente para seus clientes',
          color: Colors.green,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Compras',
          description: 'Registre produtos que entraram no seu estoque',
          color: Colors.blue,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchasesPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.analytics_outlined,
          title: 'Histórico',
          description: 'Veja tudo que entrou e saiu do seu estoque',
          color: Colors.orange,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockMovementsPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDesktopGrid(bool isGated) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      shrinkWrap: true,
      childAspectRatio: 2.2,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ModuleCard(
          icon: Icons.inventory_2_outlined,
          title: 'Produtos',
          description: 'Adicione e controle os itens que você vende',
          color: AppColors.primaryPurple,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductsPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.point_of_sale_outlined,
          title: 'Registrar Venda',
          description: 'Venda produtos diretamente para seus clientes',
          color: Colors.green,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Compras',
          description: 'Registre produtos que entraram no seu estoque',
          color: Colors.blue,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchasesPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.analytics_outlined,
          title: 'Histórico',
          description: 'Veja tudo que entrou e saiu do seu estoque',
          color: Colors.orange,
          isLocked: isGated,
          onTap: (context) {
            if (isGated) {
              _showUpgradeDialog();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockMovementsPage()),
            );
          },
        ),
      ],
    );
  }
}

class _ModuleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool isLocked;
  final Function(BuildContext) onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.isLocked = false,
    required this.onTap,
  });

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => !widget.isLocked ? _controller.forward() : null,
      onExit: (_) => !widget.isLocked ? _controller.reverse() : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: () => widget.onTap(context),
          child: Opacity(
            opacity: widget.isLocked ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                      widget.isLocked ? Colors.grey.shade200 : Colors.grey.shade100,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 28,
                          color: widget.color,
                        ),
                      ),
                      if (widget.isLocked)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child:
                                const Icon(Icons.lock, size: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.isLocked)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primaryPurple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  "PLUS",
                                  style: TextStyle(
                                    color: AppColors.primaryPurple,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.isLocked
                        ? Icons.lock_outline
                        : Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey.shade300,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
