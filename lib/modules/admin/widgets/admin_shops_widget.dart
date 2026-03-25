import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminShopsWidget extends StatefulWidget {
  const AdminShopsWidget({super.key});

  @override
  State<AdminShopsWidget> createState() => _AdminShopsWidgetState();
}

class _AdminShopsWidgetState extends State<AdminShopsWidget> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final borderColor = textColor.withValues(alpha: 0.06);

    return Column(
      children: [
        // Search Bar - Slightly more compact
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: TextField(
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, slug ou plano...',
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF4F8EF7), size: 20),
              filled: true,
              fillColor: cardColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4F8EF7), width: 1.5),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        // Shops List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.from('shops').stream(primaryKey: ['id']).order('name'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}'));
              }

              var shops = snapshot.data ?? [];
              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                shops = shops.where((data) {
                  final nome = (data['name'] ?? data['nome'] ?? '').toString().toLowerCase();
                  final slug = (data['slug'] ?? '').toString().toLowerCase();
                  final plan = (data['plan_id'] ?? data['plan'] ?? '').toString().toLowerCase();
                  return nome.contains(query) || slug.contains(query) || plan.contains(query);
                }).toList();
              }

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
                    final data = shops[index];
                    final id = data['id'];
                    final nome = data['name'] ?? data['nome'] ?? 'Sem nome';
                    final slug = data['slug'] ?? '';
                    final plan = (data['plan_id'] ?? data['plan'] ?? 'free').toString();
                    final isTrial = data['trial_active'] == true;
                    final photoUrl = data['logoUrl'];
                    
                    final boostExpiresStr = data['boost_expires_at'] as String?;
                    bool isBoosted = false;
                    if (boostExpiresStr != null) {
                      final expiresAt = DateTime.tryParse(boostExpiresStr);
                      isBoosted = expiresAt != null && expiresAt.isAfter(DateTime.now());
                    }

                    return ListTile(
                      onTap: () => _showShopDetails(data),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Hero(
                        tag: 'shop-logo-$id',
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF4F8EF7).withValues(alpha: 0.1),
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null ? const Icon(Icons.storefront_rounded, color: Color(0xFF4F8EF7), size: 18) : null,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(nome, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          if (isBoosted) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                              ),
                              child: const Text(
                                'BOOST',
                                style: TextStyle(color: Colors.amber, fontSize: 7, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text('/$slug', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (plan != 'free')
                                  ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                                  : textColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isTrial ? 'TRIAL' : plan.toUpperCase(),
                              style: TextStyle(
                                color: (plan != 'free') ? const Color(0xFF22C55E) : textColor.withValues(alpha: 0.5),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: textColor.withValues(alpha: 0.3), size: 18),
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

  Future<void> _showShopDetails(Map<String, dynamic> data) async {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final borderColor = textColor.withValues(alpha: 0.06);

    final id = data['id'];
    final nomeController = TextEditingController(text: data['name'] ?? data['nome'] ?? '');
    final telefoneController = TextEditingController(text: data['phone'] ?? data['telefone'] ?? '');
    final slugController = TextEditingController(text: data['slug'] ?? '');
    bool isEditing = false;
    final photoUrl = data['logoUrl'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: cardColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: borderColor),
          ),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.all(24),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: 'shop-logo-$id',
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFF4F8EF7).withValues(alpha: 0.1),
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null ? const Icon(Icons.storefront_rounded, color: Color(0xFF4F8EF7), size: 24) : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['name'] ?? data['nome'] ?? 'Sem nome',
                              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '/${data['slug'] ?? 'sem-slug'}',
                              style: const TextStyle(color: Color(0xFF4F8EF7), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: textColor.withValues(alpha: 0.4)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Divider(color: borderColor),
                  const SizedBox(height: 16),

                  if (!isEditing) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow('UID', id.toString(), Icons.vpn_key_outlined, textColor),
                              _buildDetailRow('Telefone', data['phone'] ?? data['telefone'] ?? 'Não informado', Icons.phone_outlined, textColor),
                              _buildDetailRow('Email', data['email'] ?? 'Não informado', Icons.email_outlined, textColor),
                              _buildDetailRow('Plano Atual', (data['plan_id'] ?? data['plan'] ?? 'free').toString().toUpperCase(), Icons.stars_outlined, textColor),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailRow('Endereço', data['address'] ?? data['endereco'] ?? 'Não informado', Icons.location_on_outlined, textColor),
                              _buildDetailRow('Criado em', (data['created_at'] ?? data['criado_em'])?.toString().split('.')[0] ?? 'N/A', Icons.calendar_today_outlined, textColor),
                              _buildDetailRow('Trial Ativo', (data['trial_active'] == true ? 'SIM' : 'NÃO'), Icons.timer_outlined, textColor),
                              if (data['trial_end_date'] != null)
                                _buildDetailRow('Fim do Trial', data['trial_end_date'].toString().split('.')[0], Icons.event_busy_outlined, textColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('AÇÕES RÁPIDAS', style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildActionButton('Editar', Icons.edit_outlined, textColor.withValues(alpha: 0.05), textColor, () => setModalState(() => isEditing = true)),
                        _buildActionButton('Plano', Icons.stars_outlined, const Color(0xFF22C55E).withValues(alpha: 0.1), const Color(0xFF22C55E), () => _changePlan(data)),
                        _buildActionButton('Boost', Icons.rocket_launch_outlined, Colors.amber.withValues(alpha: 0.1), Colors.amber, () => _addBoost(data)),
                        _buildActionButton('Trial', Icons.timer_outlined, const Color(0xFF7C5CFC).withValues(alpha: 0.1), const Color(0xFF7C5CFC), () => _liberarTrial(data)),
                        _buildActionButton('Excluir', Icons.delete_outline, Colors.red.withValues(alpha: 0.1), Colors.redAccent, () => _deleteShop(data)),
                      ],
                    ),
                  ] else ...[
                    _buildEditField('Nome do Negócio', nomeController, textColor),
                    _buildEditField('Slug (URL)', slugController, textColor),
                    _buildEditField('Telefone', telefoneController, textColor),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => setModalState(() => isEditing = false),
                            child: Text('CANCELAR', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              await Supabase.instance.client.from('shops').update({
                                'name': nomeController.text,
                                'slug': slugController.text,
                                'phone': telefoneController.text,
                              }).eq('id', id);
                              
                              setModalState(() => isEditing = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Negócio atualizado com sucesso!')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4F8EF7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('SALVAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF4F8EF7).withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 1),
                Text(value, style: TextStyle(color: textColor, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: TextStyle(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: textColor.withValues(alpha: 0.1))),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF4F8EF7))),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color bgColor, Color iconColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: iconColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: iconColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _addBoost(Map<String, dynamic> data) async {
    String? selectedDuration = '7';
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final id = data['id'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: cardColor,
          surfaceTintColor: Colors.transparent,
          title: Text('Adicionar Boost', style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Selecione a duração do boost:',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6))),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: cardColor,
                style: TextStyle(color: textColor),
                value: selectedDuration,
                items: const [
                  DropdownMenuItem(value: '7', child: Text('7 dias')),
                  DropdownMenuItem(value: '14', child: Text('14 dias')),
                  DropdownMenuItem(value: '30', child: Text('30 dias')),
                ],
                onChanged: (value) =>
                    setModalState(() => selectedDuration = value),
                decoration: InputDecoration(
                  labelText: 'Duração',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: textColor.withValues(alpha: 0.1))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR',
                  style: TextStyle(color: textColor.withValues(alpha: 0.5))),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final days = int.parse(selectedDuration!);
                  final expiresAt = DateTime.now().add(Duration(days: days));

                  await Supabase.instance.client
                      .from('shops')
                      .update({
                    'boost_expires_at': expiresAt.toIso8601String(),
                    'is_boosted': true,
                  }).eq('id', id);

                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Boost de $days dias adicionado!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao adicionar boost: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8EF7), elevation: 0),
              child: const Text('ADICIONAR'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePlan(Map<String, dynamic> data) async {
    String? selectedPlan = data['plan_id'] ?? data['plan'] ?? 'free';
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final id = data['id'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: cardColor,
          surfaceTintColor: Colors.transparent,
          title: Text('Alterar Plano', style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Selecione o novo plano:',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6))),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: cardColor,
                style: TextStyle(color: textColor),
                value: selectedPlan,
                items: const [
                  DropdownMenuItem(value: 'free', child: Text('Free')),
                  DropdownMenuItem(value: 'start', child: Text('Start')),
                  DropdownMenuItem(value: 'plus', child: Text('Plus')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                ],
                onChanged: (value) => setModalState(() => selectedPlan = value),
                decoration: InputDecoration(
                  labelText: 'Plano',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: textColor.withValues(alpha: 0.1))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR',
                  style: TextStyle(color: textColor.withValues(alpha: 0.5))),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await Supabase.instance.client
                      .from('shops')
                      .update({
                    'plan_id': selectedPlan,
                    'trial_active': false,
                    'subscription': null,
                  }).eq('id', id);

                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Plano alterado para ${selectedPlan!.toUpperCase()}!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao alterar plano: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8EF7), elevation: 0),
              child: const Text('SALVAR'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteShop(Map<String, dynamic> data) async {
    final id = data['id'];
    final nome = data['name'] ?? data['nome'] ?? 'este negócio';
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        title: Text('Excluir Negócio?', style: TextStyle(color: textColor)),
        content: Text('Tem certeza que deseja excluir permanetemente o negócio "$nome"? Esta ação não pode ser desfeita.', style: TextStyle(color: textColor.withValues(alpha: 0.6))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCELAR', style: TextStyle(color: textColor.withValues(alpha: 0.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, elevation: 0),
            child: const Text('EXCLUIR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.from('shops').delete().eq('id', id);
      if (mounted) {
        Navigator.pop(context); // Close details modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Negócio excluído com sucesso.')),
        );
      }
    }
  }

  Future<void> _liberarTrial(Map<String, dynamic> data) async {
    String? selectedPlan = 'start';
    String? selectedDuration = '30';
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final id = data['id'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: cardColor,
          surfaceTintColor: Colors.transparent,
          title: Text('Liberar Trial Customizado',
              style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Escolha o plano e a duração do teste gratuito.',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6))),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                dropdownColor: cardColor,
                style: TextStyle(color: textColor),
                value: selectedPlan,
                items: const [
                  DropdownMenuItem(value: 'start', child: Text('Start')),
                  DropdownMenuItem(value: 'plus', child: Text('Plus')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                ],
                onChanged: (value) => setModalState(() => selectedPlan = value),
                decoration: InputDecoration(
                  labelText: 'Plano',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: textColor.withValues(alpha: 0.1))),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                dropdownColor: cardColor,
                style: TextStyle(color: textColor),
                value: selectedDuration,
                items: const [
                  DropdownMenuItem(value: '7', child: Text('7 dias')),
                  DropdownMenuItem(value: '15', child: Text('15 dias')),
                  DropdownMenuItem(value: '30', child: Text('30 dias (1 mês)')),
                  DropdownMenuItem(value: '60', child: Text('60 dias (2 meses)')),
                  DropdownMenuItem(value: '90', child: Text('90 dias (3 meses)')),
                ],
                onChanged: (value) =>
                    setModalState(() => selectedDuration = value),
                decoration: InputDecoration(
                  labelText: 'Duração',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.4)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: textColor.withValues(alpha: 0.1))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR',
                  style: TextStyle(color: textColor.withValues(alpha: 0.5))),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final days = int.parse(selectedDuration!);
                  final endDate = DateTime.now().add(Duration(days: days));

                  await Supabase.instance.client
                      .from('shops')
                      .update({
                    'plan_id': selectedPlan,
                    'trial_active': true,
                    'trial_plan': selectedPlan,
                    'trial_end_date': endDate.toIso8601String(),
                    'trial_used': true,
                    'subscription': null,
                  }).eq('id', id);

                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Trial de $days dias do plano ${selectedPlan!.toUpperCase()} liberado!')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao liberar trial: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F8EF7), elevation: 0),
              child: const Text('CONFIRMAR'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    if (status.contains('confirmado')) return Icons.check_circle_outline;
    if (status.contains('concluido')) return Icons.done_all;
    if (status.contains('cancelado')) return Icons.cancel_outlined;
    return Icons.schedule;
  }

  Color _getStatusColor(String status) {
    if (status.contains('confirmado') || status.contains('concluido')) return Colors.green;
    if (status.contains('cancelado')) return Colors.red;
    return Colors.orange;
  }
}
