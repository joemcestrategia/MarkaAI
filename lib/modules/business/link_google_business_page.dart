import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/theme/app_colors.dart';

class LinkGoogleBusinessPage extends StatefulWidget {
  final String shopId;

  const LinkGoogleBusinessPage({super.key, required this.shopId});

  @override
  State<LinkGoogleBusinessPage> createState() => _LinkGoogleBusinessPageState();
}

class _LinkGoogleBusinessPageState extends State<LinkGoogleBusinessPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _hasSearched = false;
  List<Map<String, dynamic>> _searchResults = [];
  String? _linkedPlaceId;
  Map<String, dynamic>? _linkedPlace;

  @override
  void initState() {
    super.initState();
    _loadLinkedBusiness();
  }

  Future<void> _loadLinkedBusiness() async {
    try {
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();

      if (shopDoc.exists) {
        final data = shopDoc.data();
        final googleBusiness = data?['google_business'] as Map<String, dynamic>?;
        
        if (googleBusiness != null && googleBusiness['place_id'] != null) {
          setState(() {
            _linkedPlaceId = googleBusiness['place_id'];
            _linkedPlace = googleBusiness;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar Google Business vinculado: $e');
    }
  }

  Future<void> _searchBusiness() async {
    final query = _searchController.text.trim();
    
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o nome do seu negócio')),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = false;
      _searchResults = [];
    });

    try {
      final response = await http.post(
        Uri.parse('https://us-central1-wismart-118c3.cloudfunctions.net/searchGoogleBusiness'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          setState(() {
            _searchResults = List<Map<String, dynamic>>.from(data['results']);
            _hasSearched = true;
          });
        } else {
          _showError('Erro na busca: ${data['error']}');
        }
      } else {
        _showError('Erro ao buscar: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Erro ao conectar: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _linkBusiness(Map<String, dynamic> place) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Vinculação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Este é o seu negócio?', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(place['name'], style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              place['address'] ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.orange, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${place['rating']} (${place['user_ratings_total']} avaliações)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
            ),
            child: const Text('SIM, Ã‰ MEU NEGÃ“CIO'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'google_business': {
          'place_id': place['place_id'],
          'name': place['name'],
          'address': place['address'],
          'rating': place['rating'],
          'user_ratings_total': place['user_ratings_total'],
          'linked_at': FieldValue.serverTimestamp(),
        }
      });

      setState(() {
        _linkedPlaceId = place['place_id'];
        _linkedPlace = place;
        _searchResults = [];
        _searchController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Business vinculado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Erro ao vincular: $e');
    }
  }

  Future<void> _unlinkBusiness() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular Google Business'),
        content: const Text('Tem certeza que deseja desvincular seu Google Business?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('SIM, DESVINCULAR'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'google_business': FieldValue.delete(),
      });

      setState(() {
        _linkedPlaceId = null;
        _linkedPlace = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Google Business desvinculado'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      _showError('Erro ao desvincular: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Meu Negócio'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informação
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Vincule seu Google Meu Negócio para exibir suas avaliações na página da loja',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Se já está vinculado
            if (_linkedPlaceId != null) ...[
              const Text(
                'Negócio Vinculado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _linkedPlace?['name'] ?? 'Negócio Vinculado',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_linkedPlace?['address'] != null)
                                  Text(
                                    _linkedPlace!['address'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_linkedPlace?['rating'] != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.orange, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              '${_linkedPlace!['rating']} (${_linkedPlace!['user_ratings_total']} avaliações)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _unlinkBusiness,
                          icon: const Icon(Icons.link_off),
                          label: const Text('DESVINCULAR'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Campo de busca
              const Text(
                'Pesquisar Negócio',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Digite o nome do seu negócio...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onSubmitted: (_) => _searchBusiness(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSearching ? null : _searchBusiness,
                  icon: const Icon(Icons.search),
                  label: const Text('BUSCAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Resultados da busca
              if (_hasSearched) ...[
                Text(
                  _searchResults.isEmpty
                      ? 'Nenhum resultado encontrado'
                      : 'Resultados (${_searchResults.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              ..._searchResults.map((place) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  title: Text(
                    place['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (place['address'] != null)
                        Text(
                          place['address'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.orange, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${place['rating']} (${place['user_ratings_total']} avaliações)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _linkBusiness(place),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('VINCULAR'),
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}


