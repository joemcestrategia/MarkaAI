import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class MyClientsPage extends StatefulWidget {
  const MyClientsPage({super.key});

  @override
  State<MyClientsPage> createState() => _MyClientsPageState();
}

class _MyClientsPageState extends State<MyClientsPage> {
  String? _shopId;
  bool _isLoading = true;
  String _searchQuery = "";
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final id = await SessionService.getShopId();
    if (id == null || !mounted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final data = await Supabase.instance.client
        .from('users')
        .select()
        .eq('shop_id', id)
        .eq('role', 'cliente');

    if (mounted) {
      setState(() {
        _shopId = id;
        _clients = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_shopId == null) {
      return const Scaffold(body: Center(child: Text("Loja nao identificada.")));
    }

    final filtered = _clients.where((c) {
      final name = (c['name'] ?? "").toString().toLowerCase();
      final email = (c['email'] ?? "").toString().toLowerCase();
      return name.contains(_searchQuery) || email.contains(_searchQuery);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Meus Clientes"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Buscar cliente...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text("Nenhum cliente encontrado."))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final client = filtered[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(client['name'] ?? "Sem Nome"),
                        subtitle: Text(client['email'] ?? client['phone'] ?? ""),
                        onTap: () => _showClientDetails(client),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showClientDetails(Map<String, dynamic> client) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryPurple,
                child: Icon(Icons.person, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(client['name'] ?? "Cliente",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(client['email'] ?? "Email nao cadastrado"),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Telefone", client['phone'] ?? "---"),
                  _buildStatItem("Tipo", client['role'] ?? "cliente"),
                ],
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryPurple)),
      ],
    );
  }
}
