import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../core/theme/app_colors.dart';
import '../../core/services/shop_data_cache_service.dart';

class CategoryManagementPage extends StatefulWidget {
  final String shopId;

  const CategoryManagementPage({super.key, required this.shopId});

  @override
  State<CategoryManagementPage> createState() => _CategoryManagementPageState();
}

class _CategoryManagementPageState extends State<CategoryManagementPage> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;

  Future<void> _addCategory() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);

    try {
      await sb.Supabase.instance.client.from('categories').insert({
        'name': _nameController.text.trim(),
        'shop_id': widget.shopId,
        'ordem': 0, // Poderia ser incrementado futuramente
        'created_at': DateTime.now().toIso8601String(),
      });
      ShopDataCacheService().invalidate(widget.shopId, 'services');
      _nameController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Categoria adicionada!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao adicionar: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editCategory(Map<String, dynamic> data) async {
    _nameController.text = data['name'] ?? data['nome'] ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Editar Categoria"),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: "Nome"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.trim().isEmpty) return;
              await sb.Supabase.instance.client
                  .from('categories')
                  .update({'name': _nameController.text.trim()})
                  .eq('id', data['id']);
              ShopDataCacheService().invalidate(widget.shopId, 'services');
              if (mounted) Navigator.pop(context);
              _nameController.clear();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
            child: const Text("Salvar"),
          ),
        ],
      ),
    ).then((_) => _nameController.clear());
  }

  Future<void> _deleteCategory(Map<String, dynamic> data) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir Categoria?"),
        content: const Text("Isso não excluirá os serviços vinculados, mas eles ficarão sem categoria."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Excluir"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await sb.Supabase.instance.client
          .from('categories')
          .delete()
          .eq('id', data['id']);
      ShopDataCacheService().invalidate(widget.shopId, 'services');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Gerenciar Categorias"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Campo para nova categoria
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: "Nome da nova categoria...",
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _addCategory(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          onPressed: _addCategory,
                          icon: const Icon(Icons.add_circle, color: AppColors.primaryPurple, size: 32),
                        ),
                ],
              ),
            ),
          ),

          // Lista de categorias
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: sb.Supabase.instance.client
                  .from('categories')
                  .stream(primaryKey: ['id'])
                  .eq('shop_id', widget.shopId)
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Erro: ${snapshot.error}"));
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!;

                if (docs.isEmpty) {
                  return const Center(child: Text("Nenhuma categoria cadastrada.", style: TextStyle(color: Colors.grey)));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ListTile(
                        title: Text(data['name'] ?? data['nome'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.blue), onPressed: () => _editCategory(data)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _deleteCategory(data)),
                          ],
                        ),
                      ),
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
}
