import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class AdminUsersWidget extends StatefulWidget {
  const AdminUsersWidget({super.key});

  @override
  State<AdminUsersWidget> createState() => _AdminUsersWidgetState();
}

class _AdminUsersWidgetState extends State<AdminUsersWidget> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    return Column(
      children: [
        // Search Bar - Slightly more compact
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: TextField(
            style: TextStyle(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, email ou CPF...',
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14),
              prefixIcon: Icon(Icons.search, color: cs.primary, size: 20),
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
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        // Users List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.from('users').stream(primaryKey: ['id']).order('name'),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}'));
              }

              var users = snapshot.data ?? [];
              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                users = users.where((data) {
                  final nome = (data['name'] ?? data['nome'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final docId = (data['documento'] ?? '').toString().toLowerCase();
                  return nome.contains(query) || email.contains(query) || docId.contains(query);
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
                  itemCount: users.length,
                  separatorBuilder: (context, index) => Divider(color: borderColor, height: 1),
                  itemBuilder: (context, index) {
                    final data = users[index];
                    final id = data['id'];
                    final nome = data['name'] ?? 'Sem nome';
                    final email = data['email'] ?? '';
                    final tipo = data['role'] ?? 'cliente';

                    return ListTile(
                      onTap: () => _showUserDetails(data),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Hero(
                        tag: 'avatar-$id',
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primary.withValues(alpha: 0.1),
                          child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                              style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                      title: Text(nome, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(email, style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (tipo == 'dono' || tipo == 'business')
                                  ? cs.tertiary.withValues(alpha: 0.1)
                                  : textColor.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tipo.toUpperCase(),
                              style: TextStyle(
                                color: (tipo == 'dono' || tipo == 'business') ? cs.tertiary : textColor.withValues(alpha: 0.5),
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

  Future<void> _showUserDetails(Map<String, dynamic> data) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;
    final borderColor = cs.onSurface.withValues(alpha: 0.1);

    final id = data['id'];
    final nomeController = TextEditingController(text: data['name'] ?? '');
    final emailController = TextEditingController(text: data['email'] ?? '');
    final telefoneController = TextEditingController(text: data['phone'] ?? '');
    final documentoController = TextEditingController(text: data['documento'] ?? '');
    String? currentTipo = data['role'] ?? 'cliente';
    bool isEditing = false;

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
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'avatar-$id',
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: cs.primary.withValues(alpha: 0.1),
                        child: Text(
                          (data['name'] as String? ?? '?').isNotEmpty ? data['name'][0].toUpperCase() : '?',
                          style: TextStyle(color: cs.primary, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name'] ?? 'Sem nome',
                            style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            data['email'] ?? 'Sem email',
                            style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13),
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
                  _buildDetailRow('UID', id.toString(), Icons.vpn_key_outlined, textColor),
                  _buildDetailRow('Telefone', data['phone'] ?? 'Não informado', Icons.phone_outlined, textColor),
                  _buildDetailRow('CPF/CNPJ', data['documento'] ?? 'Não informado', Icons.badge_outlined, textColor),
                  _buildDetailRow('Tipo', (data['role'] ?? 'cliente').toUpperCase(), Icons.person_outline, textColor),
                  _buildDetailRow('Criado em', data['created_at']?.toString().split('.')[0] ?? 'N/A', Icons.calendar_today_outlined, textColor),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setModalState(() => isEditing = true),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('EDITAR DADOS', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.primary,
                            side: BorderSide(color: cs.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => _showRawData(data),
                        icon: Icon(Icons.code, color: textColor.withValues(alpha: 0.4), size: 18),
                        tooltip: 'Ver JSON',
                      ),
                      IconButton(
                        onPressed: () => _deleteUser(data),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        tooltip: 'Excluir Usuário',
                      ),
                    ],
                  ),
                ] else ...[
                  _buildEditField('Nome Completo', nomeController, textColor),
                  _buildEditField('Email', emailController, textColor),
                  _buildEditField('Telefone', telefoneController, textColor),
                  _buildEditField('CPF/CNPJ', documentoController, textColor),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    dropdownColor: cardColor,
                    value: currentTipo,
                    style: TextStyle(color: textColor, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Tipo de Conta',
                      labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
                      DropdownMenuItem(value: 'dono', child: Text('Dono de Negócio')),
                      DropdownMenuItem(value: 'admin', child: Text('Administrador')),
                      DropdownMenuItem(value: 'business', child: Text('Business')),
                      DropdownMenuItem(value: 'funcionario', child: Text('Funcionário')),
                    ],
                    onChanged: (val) => setModalState(() => currentTipo = val),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => setModalState(() => isEditing = false),
                          child: Text('CANCELAR', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              await Supabase.instance.client
                                  .from('users')
                                  .update({
                                'name': nomeController.text,
                                'email': emailController.text,
                                'phone': telefoneController.text,
                                'documento': documentoController.text,
                                'role': currentTipo,
                              }).eq('id', id);
                              
                              setModalState(() => isEditing = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Usuário atualizado com sucesso!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Erro ao atualizar: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('SALVAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color textColor) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 1),
              Text(value, style: TextStyle(color: textColor, fontSize: 13)),
            ],
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

  Future<void> _showRawData(Map<String, dynamic> data) async {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: Text('Dados Brutos', style: TextStyle(color: theme.textTheme.bodyLarge?.color)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(data),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> data) async {
    final id = data['id'];
    final nome = data['name'] ?? 'este usuário';
    final theme = Theme.of(context);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardColor,
        surfaceTintColor: Colors.transparent,
        title: const Text('Excluir Usuário?'),
        content: Text('Tem certeza que deseja excluir permanetemente o usuário "$nome"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCELAR', style: TextStyle(color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.5))),
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
      await Supabase.instance.client.from('users').delete().eq('id', id);
      if (mounted) {
        Navigator.pop(context); // Close details modal
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário excluído com sucesso.')),
        );
      }
    }
  }
}
