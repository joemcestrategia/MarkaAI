import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientSearchWidget extends StatefulWidget {
  final Function(Map<String, dynamic> clientData) onClientSelected;
  const ClientSearchWidget({super.key, required this.onClientSelected});

  @override
  State<ClientSearchWidget> createState() => _ClientSearchWidgetState();
}

class _ClientSearchWidgetState extends State<ClientSearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _clients = [];
  bool _isLoading = false;
  Map<String, dynamic>? _selectedClient;

  Future<void> _searchClients(String query) async {
    if (query.isEmpty) {
      setState(() => _clients = []);
      return;
    }
    setState(() => _isLoading = true);
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('tipo', isEqualTo: 'cliente')
        .orderBy('nome')
        .startAt([query])
        .endAt(['$query\uf8ff'])
        .limit(5)
        .get();

    setState(() {
      _clients = snapshot.docs;
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
                  Text(_selectedClient!['nome'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(_selectedClient!['telefone'] ?? "",
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
                final data = _clients[index].data() as Map<String, dynamic>;
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(data['nome'] ?? "Sem nome"),
                  subtitle: Text(data['telefone'] ?? ""),
                  onTap: () {
                    final selected = {
                      'id': _clients[index].id,
                      'nome': data['nome'],
                      'telefone': data['telefone']
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
