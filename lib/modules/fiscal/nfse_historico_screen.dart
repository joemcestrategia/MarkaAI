import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import 'nfse_service.dart';
import 'package:markaai/modules/fiscal/widgets/nfse_progress_modal.dart';

class NfseHistoricoScreen extends StatefulWidget {
  const NfseHistoricoScreen({super.key});

  @override
  State<NfseHistoricoScreen> createState() => _NfseHistoricoScreenState();
}

class _NfseHistoricoScreenState extends State<NfseHistoricoScreen> {
  final _service = NfseService();

  bool _isLoading = true;
  List<NfseEmissao> _notas = [];
  List<NfseEmissao> _filtradas = [];

  String _filtroStatus = 'todos';
  final _searchCtrl = TextEditingController();

  late int _mesSelecionado;
  late int _anoSelecionado;

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFmt  = DateFormat('dd/MM/yy HH:mm', 'pt_BR');

  static const _statusOpcoes = [
    ('todos',      'Todos'),
    ('autorizada', 'Autorizadas'),
    ('cancelada',  'Canceladas'),
    ('rejeitada',  'Rejeitadas'),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mesSelecionado = now.month;
    _anoSelecionado = now.year;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final shopId = await SessionService.getShopId();
      if (shopId == null || shopId.isEmpty) return;
      final notas = await _service.listarNotas(
        shopId,
        month: _mesSelecionado,
        year: _anoSelecionado,
      );
      _notas = notas;
      _aplicarFiltros();
    } catch (e) {
      debugPrint('❌ [NfseHistoricoScreen] _load: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _aplicarFiltros() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtradas = _notas.where((n) {
        final statusOk = _filtroStatus == 'todos' || n.status == _filtroStatus;
        if (!statusOk) return false;
        if (q.isEmpty) return true;
        return (n.tomadorNome?.toLowerCase().contains(q) ?? false) ||
               (n.numeroNfse?.contains(q) ?? false) ||
               (n.chaveAcesso?.contains(q) ?? false);
      }).toList();
    });
  }

  Future<void> _cancelarNota(NfseEmissao nota) async {
    final motivoCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar NFS-e',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nota nº ${nota.numeroNfse ?? nota.id.substring(0, 8)}  •  '
              '${_currency.format(nota.valorServico)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Motivo (mín. 15 caracteres)',
                border: OutlineInputBorder(),
                hintText: 'Descreva o motivo do cancelamento...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          StatefulBuilder(
            builder: (ctx2, ss) => ValueListenableBuilder<TextEditingValue>(
              valueListenable: motivoCtrl,
              builder: (_, val, __) => ElevatedButton(
                onPressed: val.text.trim().length < 15
                    ? null
                    : () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Cancelar Nota',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // ─── MODAL DE PROGRESSO ───
    final steps = [
      NfseProgressStep(label: 'Preparando cancelamento...', isCurrent: true),
      NfseProgressStep(label: 'Comunicando com a prefeitura...'),
      NfseProgressStep(label: 'Finalizando processo...'),
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctxModal, setModalState) {
          Future.microtask(() async {
            if (!steps[0].isDone) {
              try {
                // Passo 1: Início
                await Future.delayed(const Duration(milliseconds: 800));
                setModalState(() {
                  steps[0].isDone = true;
                  steps[1].isCurrent = true;
                });

                // Passo 2: Chamada real ao Backend
                await _service.cancelarNota(nota.id, motivoCtrl.text.trim());
                
                setModalState(() {
                  steps[1].isDone = true;
                  steps[2].isCurrent = true;
                });

                // Passo 3: Finalização
                await Future.delayed(const Duration(milliseconds: 800));
                setModalState(() {
                  steps[2].isDone = true;
                });

                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted && context.mounted) {
                  Navigator.pop(ctxModal); // Fecha modal
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nota cancelada com sucesso.'), backgroundColor: Colors.green),
                  );
                  _load();
                }
              } catch (e) {
                if (mounted) {
                  setModalState(() {
                    final current = steps.indexWhere((s) => s.isCurrent);
                    if (current != -1) {
                      steps[current].isError = true;
                      steps[current].isCurrent = false;
                    }
                  });
                }
                // Aguarda um pouco para o usuário ver o erro na modal antes de permitir fechar ou dar o feedback
                debugPrint('❌ Erro no cancelamento: $e');
              }
            }
          });

          return NfseProgressModal(
            title: 'Cancelando NFS-e',
            steps: steps,
            errorMessage: steps.any((s) => s.isError) ? 'Falha ao cancelar: Verifique as regras da prefeitura.' : null,
          );
        },
      ),
    );
  }

  bool _podeCanvelar(NfseEmissao nota) {
    if (nota.status != 'autorizada') return false;
    if (nota.createdAt == null) return false;
    return DateTime.now().difference(nota.createdAt!).inHours < 24;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text(
          'Histórico de NFS-e',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppColors.primaryPurple,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFiltros(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtradas.isEmpty
                    ? _buildVazia()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: _filtradas.length,
                          itemBuilder: (_, i) => _buildItem(_filtradas[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ─── FILTROS ───────────────────────────────

  Widget _buildFiltros() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          // Busca
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => _aplicarFiltros(),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, nº da nota ou chave...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _aplicarFiltros();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const SizedBox(height: 10),
          // Seletores de Mês/Ano
          Row(
            children: [
              Expanded(
                child: _buildDropdown<int>(
                  label: 'Mês',
                  value: _mesSelecionado,
                  items: List.generate(12, (i) => (i + 1, _mesNome(i + 1))),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _mesSelecionado = val);
                      _load();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown<int>(
                  label: 'Ano',
                  value: _anoSelecionado,
                  items: List.generate(5, (i) => (DateTime.now().year - i, (DateTime.now().year - i).toString())),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _anoSelecionado = val);
                      _load();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Chips de status
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _statusOpcoes.map((opcao) {
                final (valor, label) = opcao;
                final selecionado = _filtroStatus == valor;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                        color: selecionado ? Colors.white : Colors.black87,
                      ),
                    ),
                    selected: selecionado,
                    selectedColor: _chipColor(valor),
                    backgroundColor: Colors.grey.shade100,
                    onSelected: (_) {
                      setState(() => _filtroStatus = valor);
                      _aplicarFiltros();
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          // Contador
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_filtradas.length} nota(s)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Color _chipColor(String status) {
    switch (status) {
      case 'autorizada': return Colors.green;
      case 'cancelada':  return Colors.grey;
      case 'rejeitada':  return Colors.red;
      default:           return AppColors.primaryPurple;
    }
  }

  // ─── ITEM ──────────────────────────────────

  Widget _buildItem(NfseEmissao nota) {
    final statusColor = _statusColor(nota.status);
    final statusLabel = _statusLabel(nota.status);
    final podeCancelar = _podeCanvelar(nota);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linha 1: status + número + valor
            Row(
              children: [
                _statusBadge(statusLabel, statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: nota.numeroNfse != null
                      ? Text(
                          'NFS-e nº ${nota.numeroNfse}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        )
                      : Text(
                          nota.id.substring(0, 12).toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontFamily: 'monospace'),
                        ),
                ),
                Text(
                  _currency.format(nota.valorServico),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Linha 2: tomador + data
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    nota.tomadorNome ?? 'Consumidor Final',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (nota.createdAt != null)
                  Text(
                    _dateFmt.format(nota.createdAt!),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
            // Linha 3: motivo rejeição (se houver)
            if (nota.motivoRejeicao != null &&
                nota.status == 'rejeitada') ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      nota.motivoRejeicao!,
                      style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            // Linha 4: código de verificação (se houver)
            if (nota.codigoVerificacao != null &&
                nota.status == 'autorizada') ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.qr_code_rounded, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Código: ${nota.codigoVerificacao}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            // Linha 5: ações
            if (nota.pdfUrl != null || podeCancelar) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (nota.pdfUrl != null)
                    _actionButton(
                      icon: Icons.picture_as_pdf_rounded,
                      label: 'Baixar PDF',
                      color: Colors.red.shade600,
                      onTap: () => _abrirUrl(nota.pdfUrl!),
                    ),
                  if (nota.pdfUrl != null && podeCancelar)
                    const SizedBox(width: 8),
                  if (podeCancelar)
                    _actionButton(
                      icon: Icons.cancel_outlined,
                      label: 'Cancelar',
                      color: Colors.red.shade400,
                      onTap: () => _cancelarNota(nota),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ─── VAZIA ─────────────────────────────────

  Widget _buildVazia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              _filtroStatus == 'todos'
                  ? 'Nenhuma nota emitida ainda.'
                  : 'Nenhuma nota com status "${_statusLabel(_filtroStatus)}".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'autorizada': return Colors.green;
      case 'rejeitada':  return Colors.red;
      case 'cancelada':  return Colors.grey;
      default:           return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'autorizada': return 'Autorizada';
      case 'rejeitada':  return 'Rejeitada';
      case 'cancelada':  return 'Cancelada';
      default:           return 'Pendente';
    }
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── WIDGETS DE FILTRO ─────────────────────

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primaryPurple),
          style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item.$1,
              child: Text(item.$2),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _mesNome(int mes) {
    const nomes = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return nomes[mes];
  }
}
