import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminWhatsappWidget extends StatefulWidget {
  const AdminWhatsappWidget({super.key});

  @override
  State<AdminWhatsappWidget> createState() => _AdminWhatsappWidgetState();
}

class _AdminWhatsappWidgetState extends State<AdminWhatsappWidget> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  bool _hasMore = true;
  static const int _pageSize = 25;
  DateTime _selectedDate = DateTime.now();

  static const Map<String, Map<String, dynamic>> _statusConfig = {
    'success': {'label': 'Sucesso', 'color': 0xFF16A34A},
    'error': {'label': 'Erro', 'color': 0xFFDC2626},
    'pending': {'label': 'Pendente', 'color': 0xFF2563EB},
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 0}) async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      final offset = page * _pageSize;
      
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).toUtc().toIso8601String();
      final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999).toUtc().toIso8601String();

      final res = await Supabase.instance.client
          .from('whatsapp_send_log')
          .select('*, shops(name)')
          .gte('sent_at', startOfDay)
          .lte('sent_at', endOfDay)
          .order('sent_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      if (!mounted) return;
      final list = res.cast<Map<String, dynamic>>();
      setState(() {
        _logs = list;
        _page = page;
        _hasMore = list.length == _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} '
             '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  Widget _statusChip(String status) {
    final cfg = _statusConfig[status] ?? {'label': status, 'color': 0xFF6B7280};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color(cfg['color'] as int).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color(cfg['color'] as int).withValues(alpha: 0.4)),
      ),
      child: Text(
        cfg['label'] as String,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(cfg['color'] as int)),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> e) {
    final msg = e['message']?.toString() ?? 'Sem mensagem';
    final resJson = e['response_json']?.toString() ?? 'Sem JSON de resposta';
    final reqPayload = e['request_payload']?.toString() ?? 'Sem payload (mensagens antigas não possuem)';
    
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Detalhes do Envio', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Mensagem / ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              SelectableText(msg, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Parâmetros Enviados (Payload)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.blue.withValues(alpha: 0.1),
                width: double.infinity,
                child: SelectableText(reqPayload, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 16),
              const Text('Resposta da Meta (JSON)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.withValues(alpha: 0.1),
                width: double.infinity,
                child: SelectableText(resJson, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Stats
    final success = _logs.where((e) => e['status'] == 'success').length;
    final error   = _logs.where((e) => e['status'] == 'error').length;

    return Column(children: [
      // Filtro de Data
      Container(
        color: cs.surface,
        padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Filtro por Data', style: TextStyle(fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text('${_selectedDate.day.toString().padLeft(2,'0')}/${_selectedDate.month.toString().padLeft(2,'0')}/${_selectedDate.year}'),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null && mounted) {
                  setState(() => _selectedDate = date);
                  _load(page: 0);
                }
              },
            ),
          ],
        ),
      ),
      Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.1)),

      // Cards de estatísticas
      Container(
        color: cs.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _statMini('Total (Pág)', _logs.length.toString(), isDark ? Colors.grey.shade400 : Colors.grey.shade700, cs),
          const SizedBox(width: 8),
          _statMini('Sucesso', success.toString(), const Color(0xFF16A34A), cs),
          const SizedBox(width: 8),
          _statMini('Erros', error.toString(), const Color(0xFFDC2626), cs),
        ]),
      ),
      Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.1)),

      // Conteúdo principal
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 40),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _load(page: _page),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
              ]),
            ))
          : _logs.isEmpty
            ? Center(child: Text('Nenhum log encontrado.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))))
            : ListView.separated(
                itemCount: _logs.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.1)),
                itemBuilder: (_, i) {
                  final e = _logs[i];
                  final shopName = (e['shops'] != null) ? e['shops']['name'] : 'Sem Loja';
                  final phone = e['to_phone']?.toString() ?? '';
                  final template = e['template_name']?.toString() ?? 'unknown';
                  final status  = e['status']?.toString() ?? 'pending';
                  final date    = e['sent_at']?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    onTap: () => _showDetails(e),
                    title: Text(phone, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                    subtitle: Text("$shopName - $template", style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8)), overflow: TextOverflow.ellipsis),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _statusChip(status),
                      const SizedBox(height: 3),
                      Text(_formatDate(date), style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
                    ]),
                  );
                },
              ),
      ),

      // Paginação
      if (!_loading && _error == null)
        Container(
          color: cs.surface,
          child: SafeArea(
            bottom: true,
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton.icon(
                  onPressed: _page > 0 ? () => _load(page: _page - 1) : null,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Anterior'),
                ),
                Text('Página ${_page + 1}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                TextButton.icon(
                  onPressed: _hasMore ? () => _load(page: _page + 1) : null,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Próxima'),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _statMini(String label, String value, Color color, ColorScheme cs) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
      ]),
    ));
  }
}

