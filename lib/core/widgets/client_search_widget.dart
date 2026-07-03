import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClientSearchWidget extends StatefulWidget {
  final Function(Map<String, dynamic> clientData) onClientSelected;
  const ClientSearchWidget({super.key, required this.onClientSelected});

  @override
  State<ClientSearchWidget> createState() => _ClientSearchWidgetState();
}

class _ClientSearchWidgetState extends State<ClientSearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _clients = [];
  bool _isLoading = false;
  Map<String, dynamic>? _selectedClient;

  Future<void> _searchClients(String query) async {
    if (query.isEmpty) {
      setState(() => _clients = []);
      return;
    }
    setState(() => _isLoading = true);
    final snapshot = await Supabase.instance.client
        .from('users')
        .select()
        .eq('role', 'cliente')
        .ilike('name', '${query.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%')
        .order('name')
        .limit(5);

    setState(() {
      _clients = List<Map<String, dynamic>>.from(snapshot);
      _isLoading = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedClient = null;
      _searchController.clear();
      _clients = [];
    });
    widget.onClientSelected({});
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedClient != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedClient!['name'] ?? "",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_selectedClient!['phone'] ?? "",
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: _clearSelection,
            )
          ],
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (val) => _searchClients(val),
          decoration: InputDecoration(
            labelText: "Buscar Cliente por Nome",
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (_clients.isNotEmpty)
          Container(
            height: 150,
            decoration:
                BoxDecoration(border: Border.all(color: Colors.grey[300]!)),
            child: ListView.builder(
              itemCount: _clients.length,
              itemBuilder: (context, index) {
                final data = _clients[index];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(data['name'] ?? "Sem nome"),
                  subtitle: Text(data['phone'] ?? ""),
                  onTap: () {
                    final selected = {
                      'id': data['id'],
                      'name': data['name'],
                      'phone': data['phone']
                    };
                    setState(() {
                      _selectedClient = selected;
                      _clients = [];
                    });
                    widget.onClientSelected(selected);
                  },
                );
              },
            ),
          )
      ],
    );
  }
}
