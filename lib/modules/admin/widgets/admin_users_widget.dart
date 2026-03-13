import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D27),
      ),
      child: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, email ou CPF...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF4F8EF7)),
                filled: true,
                fillColor: const Color(0xFF1A1D27),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF4F8EF7)),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
  
          // Users List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').orderBy('nome').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
  
                var users = snapshot.data!.docs;
                if (_searchQuery.isNotEmpty) {
                  users = users.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final nome = (data['nome'] ?? '').toString().toLowerCase();
                    final email = (data['email'] ?? '').toString().toLowerCase();
                    final docId = (data['documento'] ?? '').toString().toLowerCase();
                    final query = _searchQuery.toLowerCase();
                    return nome.contains(query) || email.contains(query) || docId.contains(query);
                  }).toList();
                }
  
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1D27),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (context, index) => Divider(color: Colors.white.withOpacity(0.04), height: 1),
                    itemBuilder: (context, index) {
                      final doc = users[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final nome = data['nome'] ?? 'Sem nome';
                      final email = data['email'] ?? '';
                      final tipo = data['tipo'] ?? 'cliente';
  
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4F8EF7).withOpacity(0.1),
                          child: Text(nome.isNotEmpty ? nome[0].toUpperCase() : '?',
                              style: const TextStyle(color: Color(0xFF4F8EF7), fontWeight: FontWeight.bold)),
                        ),
                        title: Text(nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (tipo == 'dono' || tipo == 'business')
                                    ? const Color(0xFF7C5CFC).withOpacity(0.1)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tipo.toUpperCase(),
                                style: TextStyle(
                                  color: (tipo == 'dono' || tipo == 'business') ? const Color(0xFF7C5CFC) : Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.grey),
                              onSelected: (value) {
                                if (value == 'edit') _editUser(doc);
                                if (value == 'raw') _showRawData(doc);
                                if (value == 'delete') _deleteUser(doc);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                                const PopupMenuItem(value: 'raw', child: Text('Ver Dados Brutos')),
                                const PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: Colors.red))),
                              ],
                            ),
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
      ),
    );
  }


  Future<void> _showRawData(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dados Brutos do Usuário'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(data),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nome = data['nome'] ?? 'este usuário';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Usuário?'),
        content: Text('Tem certeza que deseja excluir permanetemente o usuário "$nome"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('users').doc(doc.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário excluído com sucesso.')),
        );
      }
    }
  }

  Future<void> _editUser(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nomeController = TextEditingController(text: data['nome'] ?? '');
    final emailController = TextEditingController(text: data['email'] ?? '');
    final telefoneController = TextEditingController(text: data['telefone'] ?? '');
    final documentoController = TextEditingController(text: data['documento'] ?? '');
    String? currentTipo = data['tipo'] ?? 'cliente';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Usuário'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeController,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefoneController,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: documentoController,
                decoration: const InputDecoration(labelText: 'CPF/CNPJ'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: currentTipo,
                decoration: const InputDecoration(labelText: 'Tipo de Conta'),
                items: const [
                  DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
                  DropdownMenuItem(value: 'dono', child: Text('Dono de Negócio')),
                ],
                onChanged: (val) => currentTipo = val,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .update({
                'nome': nomeController.text,
                'email': emailController.text,
                'telefone': telefoneController.text,
                'documento': documentoController.text,
                'tipo': currentTipo,
              });
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Usuário atualizado!')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
