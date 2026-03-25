import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

class CustomHolidayModal extends StatefulWidget {
  final String shopId;

  const CustomHolidayModal({super.key, required this.shopId});

  @override
  State<CustomHolidayModal> createState() => _CustomHolidayModalState();
}

class _CustomHolidayModalState extends State<CustomHolidayModal> {
  DateTime? _selectedDate;
  final _nameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryPurple,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (_selectedDate == null) return;
    
    setState(() => _isLoading = true);
    try {
      final iso = _selectedDate!.toIso8601String().split('T')[0];
      final supabase = Supabase.instance.client;
      
      // No Supabase, geralmente atualizamos o json b diretamente ou via function
      // Tentaremos obter o dado atual e atualizar locally para simplificar ou usar rpc
      final res = await supabase.from('shops').select('custom_holidays').eq('id', widget.shopId).single();
      List<dynamic> list = List.from(res['custom_holidays'] ?? []);
      
      list.add({
        'date': iso,
        'name': _nameController.text.trim().isEmpty ? "Folga Customizada" : _nameController.text.trim(),
      });

      await supabase.from('shops').update({'custom_holidays': list}).eq('id', widget.shopId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feriado personalizado adicionado!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _remove(String iso) async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final res = await supabase.from('shops').select('custom_holidays').eq('id', widget.shopId).single();
      List<dynamic> list = List.from(res['custom_holidays'] ?? []);
      
      list.removeWhere((item) => item['date'] == iso);

      await supabase.from('shops').update({'custom_holidays': list}).eq('id', widget.shopId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Folgas Customizadas",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "Adicione datas especiais além dos feriados nacionais.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: "Nome (ex: Aniversário da Cidade)",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                        if (_selectedDate != null)
                          Text(" ${DateFormat('dd/MM').format(_selectedDate!)}"),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: (_isLoading || _selectedDate == null) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("ADICIONAR DATA", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
            const Text("Já adicionados:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            _buildCustomHolidaysList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomHolidaysList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('shops').stream(primaryKey: ['id']).eq('id', widget.shopId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty) return const SizedBox();
        
        final data = snapshot.data!.first;
        final List<dynamic> list = data['custom_holidays'] ?? [];
        
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text("Nenhuma folga personalizada.", style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          );
        }
        
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final date = DateTime.tryParse(item['date'] ?? '') ?? DateTime.now();
              return ListTile(
                dense: true,
                leading: const Icon(Icons.star, color: Colors.blue, size: 20),
                title: Text(item['name'] ?? "Folga"),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: _isLoading ? null : () => _remove(item['date']),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
