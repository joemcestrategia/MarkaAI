import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';

class MyClientsPage extends StatefulWidget {
  const MyClientsPage({super.key});

  @override
  State<MyClientsPage> createState() => _MyClientsPageState();
}

class _MyClientsPageState extends State<MyClientsPage> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title:
            const Text("Meus Clientes", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryPurple),
      ),
      body: Column(
        children: [
          // --- BARRA DE BUSCA ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Buscar por nome ou telefone...",
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.primaryPurple),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // --- LISTA REAL TIME ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('tipo', isEqualTo: 'cliente')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Erro ao carregar"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Filtragem local para busca dinâmica
                final clients = snapshot.data!.docs.where((doc) {
                  final name = (doc['nome'] ?? "").toString().toLowerCase();
                  final phone = (doc['telefone'] ?? "").toString();
                  return name.contains(_searchQuery) ||
                      phone.contains(_searchQuery);
                }).toList();

                if (clients.isEmpty) {
                  return const Center(
                      child: Text("Nenhum cliente encontrado."));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: clients.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final data = clients[index].data() as Map<String, dynamic>;
                    final docId = clients[index].id;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      onTap: () => _showClientDetails(context, data),
                      leading: Hero(
                        tag: docId,
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor:
                              AppColors.primaryPurple.withValues(alpha: 0.1),
                          backgroundImage: (data['foto_perfil'] != null &&
                                  data['foto_perfil'] != "")
                              ? NetworkImage(data['foto_perfil'])
                              : null,
                          child: (data['foto_perfil'] == null ||
                                  data['foto_perfil'] == "")
                              ? const Icon(Icons.person,
                                  color: AppColors.primaryPurple)
                              : null,
                        ),
                      ),
                      title: Text(
                        data['nome'] ?? "Sem nome",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Text(data['telefone'] ?? "Sem contato"),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.grey),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- JANELA DE DETALHES DO CLIENTE ---
  void _showClientDetails(BuildContext context, Map<String, dynamic> client) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: (client['foto_perfil'] != null &&
                        client['foto_perfil'] != "")
                    ? NetworkImage(client['foto_perfil'])
                    : null,
                child: (client['foto_perfil'] == null ||
                        client['foto_perfil'] == "")
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(client['nome'],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              Text(client['telefone'],
                  style: const TextStyle(color: Colors.grey, fontSize: 16)),
              const Divider(height: 40),

              // Estatísticas Rápidas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Frequência", "4 cortes"),
                  _buildStatItem("Total Gasto", "R\$ 220,00"),
                ],
              ),

              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Histórico Recente",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),

              // Exemplo de histórico (No futuro vira um StreamBuilder de agendamentos)
              ListTile(
                leading: const Icon(Icons.history, color: Colors.blue),
                title: const Text("Corte Social + Barba"),
                subtitle: const Text("15 de Dezembro, 2025"),
                trailing: const Text("R\$ 65,00",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryPurple)),
      ],
    );
  }
}
