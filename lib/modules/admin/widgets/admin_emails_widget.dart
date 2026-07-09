import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:markaai/core/constants/api_keys.dart';

class AdminEmailsWidget extends StatefulWidget {
  const AdminEmailsWidget({super.key});

  @override
  State<AdminEmailsWidget> createState() => _AdminEmailsWidgetState();
}

class _AdminEmailsWidgetState extends State<AdminEmailsWidget> {
  List<Map<String, dynamic>> _emails = [];
  bool _loading = true;
  String? _error;
  int _page = 0;
  bool _hasMore = true;
  static const int _pageSize = 25;

  static const Map<String, Map<String, dynamic>> _statusConfig = {
    'delivered':        {'label': 'Entregue',  'color': 0xFF16A34A},
    'sent':             {'label': 'Enviado',   'color': 0xFF2563EB},
    'opened':           {'label': 'Aberto',    'color': 0xFF0D9488},
    'clicked':          {'label': 'Clicado',   'color': 0xFF7C3AED},
    'delivery_delayed': {'label': 'Atrasado',  'color': 0xFFEA580C},
    'bounced':          {'label': 'Bounce',    'color': 0xFFDC2626},
    'complained':       {'label': 'Spam',      'color': 0xFFDC2626},
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
      final accessToken = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
      const supabaseUrl = ApiKeys.supabaseUrl;
      final offset = page * _pageSize;
      final uri = Uri.parse('$supabaseUrl/functions/v1/admin-resend-emails?limit=$_pageSize&offset=$offset');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      });

      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _emails = list;
          _page = page;
          _hasMore = list.length == _pageSize;
        });
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() { _error = body['error']?.toString() ?? 'Erro HTTP ${res.statusCode}'; });
      }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Stats
    final delivered = _emails.where((e) => ['delivered','opened','clicked'].contains(e['last_event'])).length;
    final bounced   = _emails.where((e) => ['bounced','complained'].contains(e['last_event'])).length;
    final delayed   = _emails.where((e) => e['last_event'] == 'delivery_delayed').length;

    return Column(children: [
      // Cards de estatísticas
      Container(
        color: cs.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _statMini('Total', _emails.length.toString(), isDark ? Colors.grey.shade400 : Colors.grey.shade700, cs),
          const SizedBox(width: 8),
          _statMini('Entregues', delivered.toString(), const Color(0xFF16A34A), cs),
          const SizedBox(width: 8),
          _statMini('Bounces', bounced.toString(), const Color(0xFFDC2626), cs),
          const SizedBox(width: 8),
          _statMini('Atrasados', delayed.toString(), const Color(0xFFEA580C), cs),
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
          : _emails.isEmpty
            ? Center(child: Text('Nenhum email encontrado.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))))
            : ListView.separated(
                itemCount: _emails.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.1)),
                itemBuilder: (_, i) {
                  final e = _emails[i];
                  final toList = (e['to'] as List?)?.join(', ') ?? '';
                  final subject = e['subject']?.toString() ?? '';
                  final status  = e['last_event']?.toString() ?? 'sent';
                  final date    = e['created_at']?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(toList, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                    subtitle: Text(subject, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8)), overflow: TextOverflow.ellipsis),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      _statusChip(status),
                      const SizedBox(height: 3),
                      Text(_formatDate(date), style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
                    ]),
                  );
                },
              ),
      ),

      // Paginação com SafeArea para evitar corte por navegação Android
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
