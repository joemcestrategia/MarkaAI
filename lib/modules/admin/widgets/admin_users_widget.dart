import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';

class AdminUsersWidget extends StatefulWidget {
  const AdminUsersWidget({super.key});

  @override
  State<AdminUsersWidget> createState() => _AdminUsersWidgetState();
}

class _AdminUsersWidgetState extends State<AdminUsersWidget> {
  String _searchQuery = '';
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Filters
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome ou email...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String?>(
                value: _typeFilter,
                hint: const Text('Tipo'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(value: 'cliente', child: Text('Clientes')),
                  DropdownMenuItem(value: 'dono', child: Text('Donos')),
                ],
                onChanged: (value) => setState(() => _typeFilter = value),
              ),
            ],
          ),
        ),

        // Users List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .orderBy('criado_em', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var users = snapshot.data!.docs;

              // Apply filters
              if (_searchQuery.isNotEmpty) {
                users = users.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final nome = (data['nome'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final query = _searchQuery.toLowerCase();
                  return nome.contains(query) || email.contains(query);
                }).toList();
              }

              if (_typeFilter != null) {
                users = users.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final tipo = (data['tipo'] ?? '').toString();
                  return tipo == _typeFilter;
                }).toList();
              }

              if (users.isEmpty) {
                return const Center(child: Text('Nenhum usuário encontrado'));
              }

              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = users[index];
                  final data = doc.data() as Map<String, dynamic>;

                  final nome = data['nome'] ?? 'Sem nome';
                  final email = data['email'] ?? '';
                  final tipo = data['tipo'] ?? 'cliente';
                  final photoUrl = data['photoUrl'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child:
                          photoUrl == null ? Text(nome[0].toUpperCase()) : null,
                    ),
                    title: Text(nome),
                    subtitle: Text(email),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(
                            tipo.toUpperCase(),
                            style: const TextStyle(fontSize: 10),
                          ),
                          backgroundColor: tipo == 'dono'
                              ? AppColors.primaryPurple.withValues(alpha: 0.1)
                              : Colors.grey[200],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editUser(doc),
                        ),
                      ],
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

  Future<void> _editUser(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final nomeController = TextEditingController(text: data['nome'] ?? '');
    final telefoneController =
        TextEditingController(text: data['telefone'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Usuário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeController,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: telefoneController,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
          ],
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
                'telefone': telefoneController.text,
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
