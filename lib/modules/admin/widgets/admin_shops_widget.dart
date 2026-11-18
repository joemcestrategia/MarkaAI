import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/format_utils.dart';
import 'package:markaai/modules/admin/services/admin_service.dart';

class AdminShopsWidget extends StatefulWidget {
  const AdminShopsWidget({super.key});

  @override
  State<AdminShopsWidget> createState() => _AdminShopsWidgetState();
}

class _AdminShopsWidgetState extends State<AdminShopsWidget> {
  String _searchQuery = '';
  String _selectedPlan = 'all';
  bool _showBlocked = false;
  late Future<List<Map<String, dynamic>>> _shopsFuture;

  @override
  void initState() {
    super.initState();
    _shopsFuture = _buildQuery();
  }

  void _updateFilters() {
    setState(() {
      _shopsFuture = _buildQuery();
    });
  }

  Future<void> _openWhatsApp(String? rawPhone, String shopName) async {
    if (rawPhone == null || rawPhone.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta loja não possui número de telefone cadastrado.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    String cleanPhone = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Número de telefone inválido.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!cleanPhone.startsWith('55') && (cleanPhone.length == 10 || cleanPhone.length == 11)) {
      cleanPhone = '55$cleanPhone';
    }

    final messageText =
'''Olá! Tudo bem? 👋

Aqui é da equipe da *MarkaAI*! 🚀

Vi o cadastro do seu espaço (*$shopName*) em nossa plataforma e passei para saber se você está precisando de algum suporte com as configurações da sua agenda, pagamentos ou recursos do seu plano.

Como podemos te ajudar hoje? Ficamos à total disposição! 💬✨''';

    _showWhatsAppChooser(cleanPhone, shopName, messageText);
  }

  void _showWhatsAppChooser(String cleanPhone, String shopName, String messageText) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat, color: Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Escolha o WhatsApp para contato',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        shopName,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Opção 1: WhatsApp Pessoal
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE8F5E9),
                child: Icon(Icons.person, color: Color(0xFF2E7D32)),
              ),
              title: const Text('WhatsApp Pessoal (Normal)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Abrir no seu WhatsApp pessoal instalado ou padrão', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsAppOption(
                  type: 'personal',
                  cleanPhone: cleanPhone,
                  messageText: messageText,
                );
              },
            ),

            // Opção 2: WhatsApp Business
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE0F2FE),
                child: Icon(Icons.business_center, color: Color(0xFF0284C7)),
              ),
              title: const Text('WhatsApp Business', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Abrir no aplicativo WhatsApp Business', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsAppOption(
                  type: 'business',
                  cleanPhone: cleanPhone,
                  messageText: messageText,
                );
              },
            ),

            // Opção 3: WhatsApp Web (Navegador)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF3E8FF),
                child: Icon(Icons.language, color: Color(0xFF7E22CE)),
              ),
              title: const Text('WhatsApp Web (Navegador)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Abrir diretamente na aba do navegador (web.whatsapp.com)', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsAppOption(
                  type: 'web',
                  cleanPhone: cleanPhone,
                  messageText: messageText,
                );
              },
            ),

            // Opção 4: Copiar Mensagem e Link
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF3F4F6),
                child: Icon(Icons.copy, color: Colors.grey),
              ),
              title: const Text('Copiar Mensagem e Link', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Copia o texto formatado para colar onde desejar', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _launchWhatsAppOption(
                  type: 'copy',
                  cleanPhone: cleanPhone,
                  messageText: messageText,
                );
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _launchWhatsAppOption({
    required String type,
    required String cleanPhone,
    required String messageText,
  }) async {
    final encodedMessage = Uri.encodeComponent(messageText);

    if (type == 'copy') {
      await Clipboard.setData(
        ClipboardData(text: '$messageText\n\nLink direto: https://wa.me/$cleanPhone'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📋 Mensagem e link copiados com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    if (type == 'web') {
      final webUrl = Uri.parse('https://web.whatsapp.com/send?phone=$cleanPhone&text=$encodedMessage');
      try {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao abrir WhatsApp Web: $e'), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    if (type == 'personal') {
      // 1. Tenta scheme do WhatsApp normal/pessoal
      final intentUri = Uri.parse(
        'intent://send?phone=$cleanPhone&text=$encodedMessage#Intent;package=com.whatsapp;scheme=whatsapp;end',
      );
      final schemeUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMessage');
      final fallbackUrl = Uri.parse('https://api.whatsapp.com/send?phone=$cleanPhone&text=$encodedMessage');

      bool launched = false;
      try {
        launched = await launchUrl(intentUri, mode: LaunchMode.externalApplication);
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(schemeUri, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }

      if (!launched) {
        try {
          launched = await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o WhatsApp Pessoal.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (type == 'business') {
      // 2. Tenta WhatsApp Business
      final businessIntent = Uri.parse(
        'intent://send?phone=$cleanPhone&text=$encodedMessage#Intent;package=com.whatsapp.w4b;scheme=whatsapp;end',
      );
      final waMeUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');

      bool launched = false;
      try {
        launched = await launchUrl(businessIntent, mode: LaunchMode.externalApplication);
      } catch (_) {}

      if (!launched) {
        try {
          launched = await launchUrl(waMeUrl, mode: LaunchMode.externalApplication);
        } catch (_) {}
      }

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o WhatsApp Business.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
  }

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
                  onChanged: (value) { _searchQuery = value; _updateFilters(); },
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
                    DropdownMenuItem(value: 'starter', child: Text('Start')),
                    DropdownMenuItem(value: 'plus', child: Text('Plus')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  ],
                  onChanged: (value) { _selectedPlan = value!; _updateFilters(); },
                ),
              ),
              const SizedBox(width: 16),
              FilterChip(
                label: const Text('Bloqueados'),
                selected: _showBlocked,
                onSelected: (value) { _showBlocked = value; _updateFilters(); },
                selectedColor: cs.error.withValues(alpha: 0.2),
                checkmarkColor: cs.error,
                labelStyle: TextStyle(color: _showBlocked ? cs.error : cs.onSurface),
              ),
            ],
          ),
        ),

        // Listagem
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _shopsFuture,
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
                    final plan = (shop['plan_id'] ?? shop['plan'] ?? 'free').toString().toLowerCase();
                    final isTrial = shop['trial_active'] == true;
                    final isBoosted = shop['is_boosted'] == true;
                    final isActive = owner?['is_active'] ?? true;
                    final phone = (shop['phone'] ?? owner?['phone'])?.toString();

                    return ListTile(
                      onTap: () => _showShopDetails(shop),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                        backgroundImage: shop['logo_url'] != null ? NetworkImage(shop['logo_url']) : null,
                        child: shop['logo_url'] == null ? const Icon(Icons.store_rounded, color: AppColors.primaryPurple) : null,
                      ),
                      title: Text(shop['name'] ?? 'Sem nome', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owner?['email'] ?? 'Sem dono', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12)),
                          if (phone != null && phone.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _openWhatsApp(phone, shop['name'] ?? 'Loja'),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.chat_outlined, size: 14, color: Colors.green),
                                    const SizedBox(width: 5),
                                    Text(
                                      phone,
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isBoosted) _buildBoostChip(),
                          if (isBoosted) const SizedBox(width: 8),
                          _buildPlanChip(plan, isTrial),
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
        .select('*');

    if (_selectedPlan != 'all') {
      query = query.filter('plan_id', 'eq', _selectedPlan);
    }

    final response = await query.order('name');
    final shopsList = List<Map<String, dynamic>>.from(response);

    if (shopsList.isNotEmpty) {
      final shopIds = shopsList.map((s) => s['id']).toList();
      var usersQuery = Supabase.instance.client
          .from('users')
          .select('id, email, phone, is_active, shop_id')
          .inFilter('shop_id', shopIds)
          .eq('role', 'dono');
          
      final usersResponse = await usersQuery;
      final usersList = List<Map<String, dynamic>>.from(usersResponse);

      for (var shop in shopsList) {
        final owner = usersList.where((u) => u['shop_id'] == shop['id']).firstOrNull;
        shop['users'] = owner;
      }
      
      shopsList.removeWhere((shop) {
        final owner = shop['users'];
        
        if (_showBlocked && (owner == null || owner['is_active'] != false)) {
          return true;
        }
        
        if (_searchQuery.isNotEmpty) {
          final queryLower = _searchQuery.toLowerCase();
          final nameMatch = (shop['name'] ?? '').toString().toLowerCase().contains(queryLower);
          final slugMatch = (shop['slug'] ?? '').toString().toLowerCase().contains(queryLower);
          final emailMatch = owner != null && (owner['email'] ?? '').toString().toLowerCase().contains(queryLower);
          final phoneMatch = (shop['phone'] ?? '').toString().contains(queryLower);
          
          if (!nameMatch && !slugMatch && !emailMatch && !phoneMatch) {
            return true;
          }
        }
        
        return false;
      });
    }

    return shopsList;
  }

  Widget _buildPlanChip(String plan, bool isTrial) {
    Color color;
    switch (plan.toLowerCase()) {
      case 'pro': color = Colors.purple; break;
      case 'plus': color = Colors.blue; break;
      case 'starter': color = AppColors.gold; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(isTrial ? 'TRIAL ${plan.toUpperCase()}' : plan.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildBoostChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: Colors.orange, size: 12),
          SizedBox(width: 4),
          Text('BOOST', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showShopDetails(Map<String, dynamic> shop) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShopDetailsDrawer(
        shop: shop,
        onWhatsAppClick: (phone, name) => _openWhatsApp(phone, name),
        onUpdated: () => _updateFilters(),
      ),
    );
  }
}

class _ShopDetailsDrawer extends StatefulWidget {
  final Map<String, dynamic> shop;
  final void Function(String? phone, String name) onWhatsAppClick;
  final VoidCallback onUpdated;

  const _ShopDetailsDrawer({
    required this.shop,
    required this.onWhatsAppClick,
    required this.onUpdated,
  });

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
    final phone = widget.shop['phone'] ?? owner?['phone'];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildInfoTile('Proprietário', owner?['email'] ?? 'N/A', Icons.person_outline),
        _buildPhoneTile(phone, widget.shop['name'] ?? 'Loja'),
        _buildInfoTile('Endereço', widget.shop['address'] ?? 'N/A', Icons.location_on_outlined),
        _buildInfoTile('Cidade/UF', '${widget.shop['city'] ?? 'N/A'} - ${widget.shop['state'] ?? 'N/A'}', Icons.map_outlined),
        _buildInfoTile('Cadastro', widget.shop['created_at'] != null ? FormatUtils.formatDate(DateTime.parse(widget.shop['created_at'])) : 'N/A', Icons.calendar_today_outlined),
        const Divider(height: 40),
        const Text('Estatísticas (30 dias)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 16),
        FutureBuilder<List<dynamic>>(
          future: Future.wait([
            Supabase.instance.client
                .from('appointments')
                .select('id')
                .eq('shop_id', widget.shop['id'])
                .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String()),
            Supabase.instance.client
                .from('employees')
                .select('id')
                .eq('shop_id', widget.shop['id'])
          ]),
          builder: (context, snapshot) {
            final apptsCount = snapshot.hasData ? (snapshot.data![0] as List).length.toString() : '...';
            final empsCount = snapshot.hasData ? (snapshot.data![1] as List).length.toString() : '...';
            return Row(
              children: [
                _buildStatCard('Agendamentos', apptsCount, Colors.blue),
                const SizedBox(width: 16),
                _buildStatCard('Profissionais', empsCount, Colors.purple),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPhoneTile(String? rawPhone, String shopName) {
    final hasPhone = rawPhone != null && rawPhone.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Telefone', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(hasPhone ? rawPhone : 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (hasPhone)
            ElevatedButton.icon(
              onPressed: () => widget.onWhatsAppClick(rawPhone, shopName),
              icon: const Icon(Icons.chat, size: 16),
              label: const Text('WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTab() {
    final plan = (widget.shop['plan_id'] ?? widget.shop['plan'] ?? 'free').toString().toLowerCase();
    final isTrial = widget.shop['trial_active'] == true;
    final sub = widget.shop['subscription'] as Map<String, dynamic>?;
    final trialEndStr = sub?['trial_ends_at'] ?? sub?['trial_end_date'];
    final isBoosted = widget.shop['is_boosted'] == true;
    final boostExpiresStr = widget.shop['boost_expires_at'];

    String statusText = isTrial ? 'TRIAL ${plan.toUpperCase()}' : plan.toUpperCase();
    
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
              Text(statusText, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primaryPurple)),
              if (isTrial && trialEndStr != null) ...[
                const SizedBox(height: 8),
                Text('Expira em: ${FormatUtils.formatDate(DateTime.parse(trialEndStr))}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
              if (isBoosted) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Text('BOOST ATIVO', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (boostExpiresStr != null) ...[
                  const SizedBox(height: 4),
                  Text('Expira em: ${FormatUtils.formatDate(DateTime.parse(boostExpiresStr))}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showChangePlanDialog,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    label: const Text('Alterar Plano'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showApplyTrialDialog,
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    label: const Text('Conceder Trial'),
                  ),
                ],
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
    final currentPlan = (widget.shop['plan_id'] ?? sub?['plano'] ?? 'free').toString();
    String selectedPlan = currentPlan;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Trocar Plano Definitivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecione o novo plano permanente para a loja:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedPlan,
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Free (Gratuito)')),
                  DropdownMenuItem(value: 'starter', child: Text('Start (Iniciante)')),
                  DropdownMenuItem(value: 'plus', child: Text('Plus (Mais popular)')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro (Completo)')),
                ],
                onChanged: (v) => setState(() => selectedPlan = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final admin = Supabase.instance.client.auth.currentUser;
                if (admin == null) return;
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final dialogNav = Navigator.of(dialogCtx);

                await _adminService.changeShopPlan(widget.shop['id'], currentPlan, selectedPlan, admin.id);
                if (mounted) {
                  dialogNav.pop();
                  navigator.pop();
                  widget.onUpdated();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Plano alterado para ${selectedPlan.toUpperCase()} com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showApplyTrialDialog() {
    String selectedPlan = 'plus';
    int durationDays = 30;
    final reasonController = TextEditingController(text: 'Cortesia comercial / suporte');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.card_giftcard, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text('Conceder Período Trial'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selecione o plano pago e o tempo de teste que deseja liberar para este espaço:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                const Text('Plano a ser testado:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedPlan,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'starter', child: Text('Starter')),
                    DropdownMenuItem(value: 'plus', child: Text('Plus (Mais popular)')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro (Completo)')),
                  ],
                  onChanged: (v) => setModalState(() => selectedPlan = v!),
                ),
                const SizedBox(height: 16),
                const Text('Duração do Trial:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [7, 15, 30, 60].map((days) {
                    final isSel = durationDays == days;
                    return ChoiceChip(
                      label: Text('$days dias'),
                      selected: isSel,
                      onSelected: (_) => setModalState(() => durationDays = days),
                      selectedColor: Colors.deepOrange.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: isSel ? Colors.deepOrange : Colors.black87,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Motivo / Justificativa:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    hintText: 'Ex: Contato comercial, extensão de teste...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final admin = Supabase.instance.client.auth.currentUser;
                if (admin == null) return;
                
                final currentPlan = (widget.shop['plan_id'] ?? 'free').toString();
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final dialogNav = Navigator.of(dialogCtx);
                
                await _adminService.applyShopTrial(
                  shopId: widget.shop['id'],
                  oldPlan: currentPlan,
                  targetPlan: selectedPlan,
                  durationDays: durationDays,
                  adminId: admin.id,
                  reason: reasonController.text.trim(),
                );
                
                if (mounted) {
                  dialogNav.pop();
                  navigator.pop();
                  widget.onUpdated();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('🎉 Trial de $durationDays dias do plano ${selectedPlan.toUpperCase()} ativado com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar Trial'),
            ),
          ],
        ),
      ),
    );
  }
}
