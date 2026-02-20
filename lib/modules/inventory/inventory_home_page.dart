import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'products_page.dart';
import 'sales_page.dart';
import 'purchases_page.dart';
import 'stock_movements_page.dart';

class InventoryHomePage extends StatelessWidget {
  const InventoryHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Inventário & Estoque',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
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
                  isMobile ? 20 : 40,
                  24,
                  isMobile ? 20 : 40,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Módulos de Gestão",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Selecione uma categoria para gerenciar",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 40,
                  vertical: 20,
                ),
                child: isMobile ? _buildMobileList() : _buildDesktopGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return Column(
      children: [
        _ModuleCard(
          icon: Icons.inventory_2_outlined,
          title: 'Produtos e Serviços',
          description: 'Cadastre e gerencie seu catálogo completo',
          color: AppColors.primaryPurple,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductsPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.point_of_sale_outlined,
          title: 'Frente de Caixa (PDV)',
          description: 'Realize vendas de forma rápida e integrada',
          color: Colors.green,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Entradas e Compras',
          description: 'Registre novas aquisições para o estoque',
          color: Colors.blue,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchasesPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _ModuleCard(
          icon: Icons.analytics_outlined,
          title: 'Fluxo e Histórico',
          description: 'Acompanhe todas as entradas e saídas',
          color: Colors.orange,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StockMovementsPage()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDesktopGrid() {
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
          title: 'Produtos e Serviços',
          description: 'Catálogo de itens para venda e uso profissional',
          color: AppColors.primaryPurple,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProductsPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.point_of_sale_outlined,
          title: 'Frente de Caixa (PDV)',
          description: 'Sistema integrado para registro de vendas rápidas',
          color: Colors.green,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SalesPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Entradas e Compras',
          description: 'Gestão de fornecedores e reposição de estoque',
          color: Colors.blue,
          onTap: (context) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchasesPage()),
            );
          },
        ),
        _ModuleCard(
          icon: Icons.analytics_outlined,
          title: 'Fluxo e Histórico',
          description: 'Relatórios detalhados de movimentação de itens',
          color: Colors.orange,
          onTap: (context) {
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
  final Function(BuildContext) onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
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
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: GestureDetector(
          onTap: () => widget.onTap(context),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100, width: 1),
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
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
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.grey.shade300,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
