import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

class HolidayDecisionModal extends StatefulWidget {
  final String shopId;
  final DateTime date;
  final Map<String, dynamic> shopData;
  final String? holidayName;

  const HolidayDecisionModal({
    super.key,
    required this.shopId,
    required this.date,
    required this.shopData,
    this.holidayName,
  });

  @override
  State<HolidayDecisionModal> createState() => _HolidayDecisionModalState();
}

class _HolidayDecisionModalState extends State<HolidayDecisionModal> {
  String _decision = 'sem_impacto'; // 'fechado', 'escala', 'sem_impacto'
  List<String> _selectedEmployeeIds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final iso = widget.date.toIso8601String().split('T')[0];
    final configurados = widget.shopData['configured_holidays'] ?? {};
    
    if (configurados.containsKey(iso)) {
      final config = configurados[iso];
      if (config == 'fechado') {
        _decision = 'fechado';
      } else if (config == 'sem_impacto') {
        _decision = 'sem_impacto';
      } else if (config is Map && config.containsKey('escala')) {
        _decision = 'escala';
        _selectedEmployeeIds = List<String>.from(config['escala']);
      }
    } else {
      final pendentes = widget.shopData['pending_holidays'] ?? [];
      final autoBlock = widget.shopData['config']?['auto_block_holidays'] ?? false;
      if (autoBlock && pendentes.contains(iso)) {
        _decision = 'fechado';
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      final iso = widget.date.toIso8601String().split('T')[0];
      final supabase = Supabase.instance.client;
      
      dynamic decisaoPayload;
      if (_decision == 'escala') {
        decisaoPayload = {'escala': _selectedEmployeeIds};
      } else {
        decisaoPayload = _decision;
      }

      // No Supabase, atualizamos o json b configured_holidays na tabela shops
      final res = await supabase.from('shops').select('configured_holidays').eq('id', widget.shopId).single();
      Map<String, dynamic> currentConfig = Map<String, dynamic>.from(res['configured_holidays'] ?? {});
      currentConfig[iso] = decisaoPayload;

      await supabase.from('shops').update({'configured_holidays': currentConfig}).eq('id', widget.shopId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Decisão salva com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(widget.date);
    
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
            const SizedBox(height: 20),
            Text(
              widget.holidayName != null ? "O que faremos no feriado:" : "O que faremos em:",
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            if (widget.holidayName != null)
              Text(
                widget.holidayName!,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            Text(
              dateStr.capitalize(),
              style: TextStyle(
                fontSize: widget.holidayName != null ? 14 : 18,
                fontWeight: widget.holidayName != null ? FontWeight.normal : FontWeight.bold,
                color: widget.holidayName != null ? Colors.grey[600] : Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            _buildOption(
              value: 'fechado',
              title: "Fechado",
              subtitle: "Ninguém poderá agendar neste dia.",
              icon: Icons.block,
              color: Colors.grey[800]!,
            ),
            _buildOption(
              value: 'escala',
              title: "Escala Reduzida",
              subtitle: "Apenas alguns profissionais trabalharão.",
              icon: Icons.people_outline,
              color: Colors.orange,
            ),
            if (_decision == 'escala') _buildEmployeeSelector(),
            _buildOption(
              value: 'sem_impacto',
              title: "Funcionamento Normal",
              subtitle: "Dia útil normal para todos da equipe.",
              icon: Icons.check_circle_outline,
              color: Colors.green,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("SALVAR DECISÃO", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _decision == value;
    return GestureDetector(
      onTap: () => setState(() => _decision = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client.from('employees').stream(primaryKey: ['id']).eq('shop_id', widget.shopId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final employees = snapshot.data!;
          if (employees.isEmpty) return const Text("Nenhum profissional cadastrado.");
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Quem trabalhará?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              ...employees.map((emp) {
                final id = emp['id'].toString();
                final name = emp['name'] ?? emp['nome'] ?? "Sem nome";
                final isSelected = _selectedEmployeeIds.contains(id);
                return CheckboxListTile(
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  value: isSelected,
                  activeColor: AppColors.primaryPurple,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedEmployeeIds.add(id);
                      } else {
                        _selectedEmployeeIds.remove(id);
                      }
                    });
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
