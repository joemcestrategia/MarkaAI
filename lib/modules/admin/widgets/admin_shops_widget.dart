import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/format_utils.dart';
import 'package:markaai/modules/admin/services/admin_service.dart';

class AdminShopsWidget extends StatefulWidget {
  const AdminShopsWidget({super.key});

  @override
  State<AdminShopsWidget> createState() => _AdminShopsWidgetState();
}

class _AdminShopsWidgetState extends State<AdminShopsWidget> {
  final _adminService = AdminService();
  String _searchQuery = '';
  String _selectedPlan = 'all';
  bool _showBlocked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return Column(
      children: [
        // Filtros e Busca
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome, email ou telefone...',
                    hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: cs.primary, size: 20),
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cs.primary, width: 1.5)),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedPlan,
                  dropdownColor: cardColor,
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos Planos')),
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'start', child: Text('Start')),
                    DropdownMenuItem(value: 'plus', child: Text('Plus')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  ],
                  onChanged: (value) => setState(() => _selectedPlan = value!),
                ),
              ),
              const SizedBox(width: 16),
              FilterChip(
                label: const Text('Bloqueados'),
                selected: _showBlocked,
                onSelected: (value) => setState(() => _showBlocked = value),
                selectedColor: cs.error.withValues(alpha: 0.2),
                checkmarkColor: cs.error,
                labelStyle: TextStyle(color: _showBlocked ? cs.error : cs.onSurface),
              ),
            ],
          ),
        ),

        // Listagem
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _buildQuery().asStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));

              final shops = snapshot.data ?? [];

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: borderColor),
                ),
                child: ListView.separated(
                  itemCount: shops.length,
                  separatorBuilder: (context, index) => Divider(color: borderColor, height: 1),
                  itemBuilder: (context, index) {
                    final shop = shops[index];
                    final owner = shop['users'] as Map<String, dynamic>?;
                    final subscription = shop['subscription'] as Map<String, dynamic>?;
                    final plan = subscription?['plano'] ?? 'free';
                    final isActive = owner?['is_active'] ?? true;

                    return ListTile(
                      onTap: () => _showShopDetails(shop),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                        backgroundImage: shop['logo_url'] != null ? NetworkImage(shop['logo_url']) : null,
                        child: shop['logo_url'] == null ? const Icon(Icons.store_rounded, color: AppColors.primaryPurple) : null,
                      ),
                      title: Text(shop['name'] ?? 'Sem nome', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(owner?['email'] ?? 'Sem dono', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildPlanChip(plan),
                          const SizedBox(width: 8),
                          if (!isActive)
                            Icon(Icons.block, color: cs.error, size: 16),
                          Icon(Icons.chevron_right, color: cs.onSurface.withValues(alpha: 0.3)),
                        ],
                      ),
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

  Future<List<Map<String, dynamic>>> _buildQuery() async {
    var query = Supabase.instance.client
        .from('shops')
        .select('*, users!inner(email, is_active, id)');

    if (_selectedPlan != 'all') {
      query = query.filter('subscription->>plano', 'eq', _selectedPlan);
    }
    
    if (_showBlocked) {
      query = query.eq('users.is_active', false);
    }

    if (_searchQuery.isNotEmpty) {
      query = query.or('name.ilike.%$_searchQuery%,slug.ilike.%$_searchQuery%,users.email.ilike.%$_searchQuery%');
    }

    final response = await query.order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Widget _buildPlanChip(String plan) {
    Color color;
    switch (plan.toLowerCase()) {
      case 'pro': color = Colors.purple; break;
      case 'plus': color = Colors.blue; break;
      case 'start': color = AppColors.gold; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(plan.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _showShopDetails(Map<String, dynamic> shop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShopDetailsDrawer(shop: shop),
    );
  }
}

class _ShopDetailsDrawer extends StatefulWidget {
  final Map<String, dynamic> shop;
  const _ShopDetailsDrawer({required this.shop});

  @override
  State<_ShopDetailsDrawer> createState() => _ShopDetailsDrawerState();
}

class _ShopDetailsDrawerState extends State<_ShopDetailsDrawer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _adminService = AdminService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bgColor = cs.surface;
    final textColor = cs.onSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                  backgroundImage: widget.shop['logo_url'] != null ? NetworkImage(widget.shop['logo_url']) : null,
                  child: widget.shop['logo_url'] == null ? const Icon(Icons.store_rounded, size: 30, color: AppColors.primaryPurple) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.shop['name'] ?? 'Sem nome', 
                           overflow: TextOverflow.ellipsis,
                           maxLines: 1,
                           style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('/${widget.shop['slug']}', 
                           overflow: TextOverflow.ellipsis,
                           maxLines: 1,
                           style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: 'Visão Geral'),
              Tab(text: 'Assinatura'),
              Tab(text: 'WhatsApp'),
              Tab(text: 'Ações'),
            ],
          ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildSubscriptionTab(),
                _buildWhatsAppTab(),
                _buildActionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final owner = widget.shop['users'] as Map<String, dynamic>?;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildInfoTile('Proprietário', owner?['email'] ?? 'N/A', Icons.person_outline),
        _buildInfoTile('Telefone', widget.shop['phone'] ?? 'N/A', Icons.phone_outlined),
        _buildInfoTile('Endereço', widget.shop['address'] ?? 'N/A', Icons.location_on_outlined),
        _buildInfoTile('Cidade/UF', '${widget.shop['city'] ?? 'N/A'} - ${widget.shop['state'] ?? 'N/A'}', Icons.map_outlined),
        _buildInfoTile('Cadastro', widget.shop['created_at'] != null ? FormatUtils.formatDate(DateTime.parse(widget.shop['created_at'])) : 'N/A', Icons.calendar_today_outlined),
        const Divider(height: 40),
        const Text('Estatísticas (30 dias)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard('Agendamentos', '24', Colors.blue),
            const SizedBox(width: 16),
            _buildStatCard('Profissionais', '3', Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildSubscriptionTab() {
    final sub = widget.shop['subscription'] as Map<String, dynamic>?;
    final plan = sub?['plano'] ?? 'free';
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              const Text('Plano Atual', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Text(plan.toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _showChangePlanDialog,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
                child: const Text('Alterar Plano'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Histórico de Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: Supabase.instance.client.from('subscription_history').stream(primaryKey: ['id']).eq('shop_id', widget.shop['id']).order('changed_at'),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final history = snapshot.data!;
            if (history.isEmpty) return const Text('Nenhum histórico encontrado', style: TextStyle(color: Colors.grey, fontSize: 12));
            
            return Column(
              children: history.map((h) => ListTile(
                dense: true,
                title: Text('${h['old_plan']} → ${h['new_plan']}'),
                subtitle: Text(FormatUtils.formatDateTime(DateTime.parse(h['changed_at']))),
                trailing: Text(h['source'] ?? 'manual', style: const TextStyle(fontSize: 10)),
              )).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWhatsAppTab() {
    return const Center(child: Text('Configurações de WhatsApp em breve'));
  }

  Widget _buildActionsTab() {
    final owner = widget.shop['users'] as Map<String, dynamic>?;
    final isActive = owner?['is_active'] ?? true;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          title: Text(isActive ? 'Bloquear Loja' : 'Desbloquear Loja'),
          subtitle: Text(isActive ? 'Impede o acesso do dono e agendamentos' : 'Restaura o acesso total'),
          leading: Icon(isActive ? Icons.block : Icons.check_circle_outline, color: isActive ? Colors.red : Colors.green),
          onTap: () async {
            final admin = Supabase.instance.client.auth.currentUser;
            if (admin == null) return;
            await _adminService.toggleShopBlock(widget.shop['id'], owner!['id'], isActive, admin.id);
            if (mounted) Navigator.pop(context);
          },
        ),
        const Divider(),
        ListTile(
          title: const Text('Enviar Comunicado Direto'),
          leading: const Icon(Icons.campaign_outlined),
          onTap: () {
            // TODO: Implementar envio de comunicado
          },
        ),
      ],
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showChangePlanDialog() {
    final sub = widget.shop['subscription'] as Map<String, dynamic>?;
    final currentPlan = sub?['plano'] ?? 'free';
    String selectedPlan = currentPlan;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Trocar Plano'),
          content: DropdownButtonFormField<String>(
            value: selectedPlan,
            items: const [
              DropdownMenuItem(value: 'free', child: Text('Free')),
              DropdownMenuItem(value: 'start', child: Text('Start')),
              DropdownMenuItem(value: 'plus', child: Text('Plus')),
              DropdownMenuItem(value: 'pro', child: Text('Pro')),
            ],
            onChanged: (v) => setState(() => selectedPlan = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final admin = Supabase.instance.client.auth.currentUser;
                if (admin == null) return;
                await _adminService.changeShopPlan(widget.shop['id'], currentPlan, selectedPlan, admin.id);
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}
