import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/widgets/plan_gate_widget.dart';
import '../business/subscription_service.dart';
import '../../widgets/upgrade_modal.dart';
import 'nfse_service.dart';
import 'nfse_config_screen.dart';
import 'nfse_historico_screen.dart';
import 'widgets/nfse_progress_modal.dart';

class NfseDashboardScreen extends StatefulWidget {
  const NfseDashboardScreen({super.key});

  @override
  State<NfseDashboardScreen> createState() => _NfseDashboardScreenState();
}

class _NfseDashboardScreenState extends State<NfseDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _service = NfseService();
  late TabController _tabController;

  String? _shopId;
  bool _isLoading = true;
  bool _hasConfig = false;

  // Status de adesão municipal
  bool _checkingAdesao = false;
  bool? _municipioAderiu;
  String? _codigoMunicipio;
  String? _municipioMotivoFalha;

  // Status operacional da API gov.br
  bool _checkingApiStatus = false;
  bool? _apiOperacional;   // null = verificando, true = ok, false = down
  int?  _apiLatencyMs;     // tempo de resposta em ms (para exibir)
  String? _apiStatusMsg;

  NfseDashboardMetrics? _metrics;
  List<AppointmentPendente> _pendentes = [];
  List<NfseEmissao> _historico = [];

  final Set<String> _selecionados = {};
  bool _emitindoLote = false;

  late int _mesSelecionado;
  late int _anoSelecionado;

  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFmt = DateFormat('dd/MM/yy HH:mm', 'pt_BR');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _mesSelecionado = now.month;
    _anoSelecionado = now.year;
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      String? id = await SessionService.getShopId();
      if (id == null || id.isEmpty) return;
      _shopId = id;

      final config = await _service.getConfig(_shopId!);
      _hasConfig = config != null && config.ativo;

      if (config != null) {
        _codigoMunicipio = config.codigoMunicipio;
        // Verificar adesão municipal e status da API em paralelo
        _checkAdesaoMunicipal(config.codigoMunicipio);
        _checkApiStatus(config.ambiente);
      }

      if (_hasConfig) {
        // Carregamento independente para garantir que falhas parciais não quebrem a tela
        try {
          // Passar filtros para as métricas (o serviço precisará de ajuste se quiser filtrar métricas por data)
          _metrics = await _service.getDashboardMetrics(_shopId!);
        } catch (e) {
          debugPrint('⚠️ Erro ao carregar métricas: $e');
        }

        try {
          _pendentes = await _service.getNotasPendentes(_shopId!);
        } catch (e) {
          debugPrint('❌ Erro ao carregar agendamentos pendentes: $e');
        }

        try {
          _historico = await _service.getHistorico(
            _shopId!,
            month: _mesSelecionado,
            year: _anoSelecionado,
          );
        } catch (e) {
          debugPrint('⚠️ Erro ao carregar histórico: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ [NfseDashboardScreen] _load: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkApiStatus(String ambiente) async {
    if (!mounted) return;
    setState(() {
      _checkingApiStatus = true;
      _apiOperacional = null;
      _apiLatencyMs = null;
      _apiStatusMsg = null;
    });
    // Pinga o endpoint de parâmetros municipais com código genérico.
    // Qualquer resposta HTTP (mesmo 4xx) indica que a API está no ar.
    // Timeout = down.
    final url = ambiente == 'producao'
        ? 'https://api.nfse.gov.br/v1/parametros_municipais/0000000'
        : 'https://api.producaorestrita.nfse.gov.br/v1/parametros_municipais/0000000';
    try {
      final stopwatch = Stopwatch()..start();
      final resp = await _service.httpGet(url)
          .timeout(const Duration(seconds: 8));
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      if (mounted) {
        setState(() {
          _apiLatencyMs = ms;
          if (resp >= 100 && resp < 600) {
            _apiOperacional = true;
            _apiStatusMsg = ms > 3000
                ? 'Resposta lenta (${ms}ms) — API pode estar degradada.'
                : 'Operacional (${ms}ms)';
          } else {
            _apiOperacional = false;
            _apiStatusMsg = 'API respondeu com código inesperado ($resp).';
          }
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _apiOperacional = false;
          _apiStatusMsg = 'API indisponível: ${e.toString().replaceAll('TimeoutException', 'Timeout')}';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingApiStatus = false);
    }
  }

  Future<void> _checkAdesaoMunicipal(String codigoMunicipio) async {
    if (!mounted) return;
    setState(() {
      _checkingAdesao = true;
      _municipioAderiu = null;
      _municipioMotivoFalha = null;
    });
    try {
      final result = await _service.verificarAdesaoMunicipal(codigoMunicipio);
      if (mounted) {
        setState(() {
          _municipioAderiu = result.aderiu;
          _municipioMotivoFalha = result.motivo;
        });
      }
    } finally {
      if (mounted) setState(() => _checkingAdesao = false);
    }
  }

  Future<void> _emitirUma(AppointmentPendente appointment) async {
    final confirm = await _showConfirmDialog(
      title: 'Emitir NFS-e',
      message:
          'Emitir nota fiscal para o serviço "${appointment.serviceName ?? 'Serviço'}" '
          'de ${appointment.clientName ?? 'cliente'}?\n\n'
          'Valor: ${_currency.format(appointment.valorTotal)}',
    );
    if (!confirm) return;

    final steps = [
      NfseProgressStep(label: 'Validando dados do cliente', isCurrent: true),
      NfseProgressStep(label: 'Gerando pacote XML (ABRASF)', isDone: false),
      NfseProgressStep(label: 'Transmitindo para a SEFIN/Itabirito', isDone: false),
      NfseProgressStep(label: 'Aguardando autorização final', isDone: false),
    ];

    String? currentError;
    bool finalizadoComSucesso = false;

    StateSetter? setModalState;

    // Mostra o modal de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (modalCtx) => StatefulBuilder(
        builder: (ctx, ss) {
          setModalState = ss;
          return NfseProgressModal(
            title: 'Emitindo Nota Fiscal',
            steps: steps,
            errorMessage: currentError,
          );
        },
      ),
    );

    void refreshModal() {
      if (mounted) setState(() {});
      if (setModalState != null) setModalState!(() {});
    }

    try {
      // Pequeno delay para percepção visual das etapas iniciais
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      refreshModal(); // Inicia primeira etapa visual
      
      steps[0].isDone = true;
      steps[1].isCurrent = true;
      refreshModal();

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      steps[1].isDone = true;
      steps[2].isCurrent = true;
      refreshModal();

      // Chamada real da API
      final result = await _service.emitirNota(appointment.id);

      if (!mounted) return;
      if (result.sucesso) {
        steps[2].isDone = true;
        steps[3].isDone = true;
        finalizadoComSucesso = true;
        refreshModal();
        
        // Fecha o modal após 1 segundo de sucesso e recarrega
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showResultSnackbar(true, null);
          await _load();
        }
      } else {
        steps[2].isError = true;
        currentError = result.erro;
        refreshModal();
        // O modal permanece aberto exibindo o erro e o botão de fechar.
      }
    } catch (e) {
      if (mounted) {
        steps[2].isError = true;
        currentError = 'Erro inesperado: $e';
        refreshModal();
      }
    }
  }

  Future<void> _emitirSelecionadas() async {
    if (_selecionados.isEmpty) return;

    final confirm = await _showConfirmDialog(
      title: 'Emitir em Lote',
      message: 'Emitir NFS-e para ${_selecionados.length} agendamento(s) selecionado(s)?',
    );
    if (!confirm) return;

    setState(() => _emitindoLote = true);
    try {
      final results = await _service.emitirNotasEmLote(_selecionados.toList());
      final sucessos = results.where((r) => r.sucesso).length;
      final falhas = results.length - sucessos;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              falhas == 0
                  ? '$sucessos nota(s) emitida(s) com sucesso!'
                  : '$sucessos emitida(s), $falhas com erro.',
            ),
            backgroundColor: falhas == 0 ? Colors.green : Colors.orange,
          ),
        );
        _selecionados.clear();
        await _load();
      }
    } finally {
      if (mounted) setState(() => _emitindoLote = false);
    }
  }

  Future<void> _cancelarNota(NfseEmissao nota) async {
    final motivoCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar NFS-e'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nota nº ${nota.numeroNfse ?? nota.id.substring(0, 8)}'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo do cancelamento',
                border: OutlineInputBorder(),
                hintText: 'Descreva o motivo...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          ElevatedButton(
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancelar Nota', style: TextStyle(color: Colors.white)),
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
                await Future.delayed(const Duration(milliseconds: 600));
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
                await Future.delayed(const Duration(milliseconds: 600));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text(
          'Gestão Fiscal (NFS-e)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppColors.primaryPurple,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'Histórico Completo',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NfseHistoricoScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Configurações Fiscais',
            onPressed: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const NfseConfigScreen()),
              );
              if (changed == true) await _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
        bottom: _hasConfig
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Pendentes'),
                        if (_pendentes.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_pendentes.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Histórico'),
                ],
              )
            : null,
      ),
      body: PlanGateWidget(
        requiredPlan: SubscriptionPlan.pro,
        featureLabel: 'Dashboard de NFS-e',
        onUpgradeTap: () => UpgradeModal.show(
          context,
          featureName: 'Dashboard Gestão Fiscal',
          requiredPlan: 'Pro',
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !_hasConfig
                ? _buildNoConfigState()
                : Column(
                    children: [
                      _buildStatusBanner(),
                      _buildFilterBar(),
                      _buildMetricsCards(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildPendentesTab(),
                            _buildHistoricoTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  // ─── STATUS BANNER ─────────────────────────────────

  Widget _buildStatusBanner() {
    final rows = <Widget>[];

    // ── Linha 1: status da API gov.br ──────────────────────────────────────
    if (_checkingApiStatus) {
      rows.add(_statusRow(
        icon: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: 'API NFS-e gov.br',
        value: 'Verificando...',
        valueColor: Colors.grey.shade500,
      ));
    } else if (_apiOperacional == true) {
      final slow = (_apiLatencyMs ?? 0) > 3000;
      rows.add(_statusRow(
        icon: Icon(
          slow ? Icons.warning_amber_rounded : Icons.circle,
          size: 12,
          color: slow ? Colors.orange : Colors.green,
        ),
        label: 'API NFS-e gov.br',
        value: _apiStatusMsg ?? 'Operacional',
        valueColor: slow ? Colors.orange.shade700 : Colors.green.shade700,
      ));
    } else if (_apiOperacional == false) {
      rows.add(_statusRow(
        icon: const Icon(Icons.circle, size: 12, color: Colors.red),
        label: 'API NFS-e gov.br',
        value: _apiStatusMsg ?? 'Indisponível',
        valueColor: Colors.red.shade700,
        action: TextButton.icon(
          onPressed: () {
            if (_codigoMunicipio != null) {
              final cfg = _hasConfig ? 'producao' : 'homologacao';
              _checkApiStatus(cfg);
            }
          },
          icon: const Icon(Icons.refresh_rounded, size: 13),
          label: const Text('Tentar novamente', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ));
    }

    // ── Linha 2: adesão municipal ───────────────────────────────────────────
    if (_checkingAdesao) {
      rows.add(_statusRow(
        icon: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: 'Município ${_codigoMunicipio ?? ''}',
        value: 'Verificando adesão...',
        valueColor: Colors.grey.shade500,
      ));
    } else if (_municipioAderiu == true) {
      rows.add(_statusRow(
        icon: const Icon(Icons.circle, size: 12, color: Colors.green),
        label: 'Município ${_codigoMunicipio ?? ''}',
        value: 'Aderiu ao padrão nacional',
        valueColor: Colors.green.shade700,
      ));
    } else if (_municipioAderiu == false) {
      rows.add(_statusRow(
        icon: const Icon(Icons.circle, size: 12, color: Colors.orange),
        label: 'Município ${_codigoMunicipio ?? ''}',
        value: _municipioMotivoFalha ?? 'Não aderiu — emita pelo portal da prefeitura',
        valueColor: Colors.orange.shade800,
        action: TextButton.icon(
          onPressed: () {
            if (_codigoMunicipio != null) _checkAdesaoMunicipal(_codigoMunicipio!);
          },
          icon: const Icon(Icons.refresh_rounded, size: 13),
          label: const Text('Verificar novamente', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange.shade800,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded,
                  size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Text(
                'STATUS DO SISTEMA',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  Widget _statusRow({
    required Widget icon,
    required String label,
    required String value,
    required Color valueColor,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          const Text('—', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: valueColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }


  // ─── NO CONFIG STATE ──────────────────────────────

  Widget _buildNoConfigState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Módulo NFS-e não configurado',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure seus dados fiscais para começar a emitir notas de serviço eletrônicas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const NfseConfigScreen()),
                );
                if (changed == true) await _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.settings_rounded, color: Colors.white),
              label: const Text('Configurar Agora',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── METRICS CARDS ─────────────────────────

  Widget _buildMetricsCards() {
    final m = _metrics;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          _buildMetricCard(
            label: 'Serviços\nRealizados',
            value: '${m?.totalServicosRealizados ?? 0}',
            icon: Icons.check_circle_outline,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          _buildMetricCard(
            label: 'Notas\nEmitidas',
            value: '${m?.totalNotasEmitidas ?? 0}',
            icon: Icons.receipt_long_rounded,
            color: Colors.green,
          ),
          const SizedBox(width: 8),
          _buildMetricCard(
            label: 'Pendentes\nde NFS-e',
            value: '${m?.totalPendentes ?? 0}',
            icon: Icons.pending_actions_rounded,
            color: Colors.orange,
            highlight: (m?.totalPendentes ?? 0) > 0,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: highlight ? color.withValues(alpha: 0.08) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? color.withValues(alpha: 0.3) : Colors.grey.shade200,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: highlight ? color : Colors.black87,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  // ─── PENDENTES TAB ─────────────────────────

  Widget _buildPendentesTab() {
    if (_pendentes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded, size: 48, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhum serviço pendente!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Todos os serviços concluídos já têm nota emitida.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_selecionados.isNotEmpty) _buildLoteBar(),
        _buildSelectAllBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
              itemCount: _pendentes.length,
              itemBuilder: (_, i) => _buildPendenteItem(_pendentes[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoteBar() {
    return Container(
      color: AppColors.primaryPurple.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${_selecionados.length} selecionado(s)',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.primaryPurple,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _emitindoLote ? null : _emitirSelecionadas,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: _emitindoLote
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 16),
            label: const Text('Emitir Selecionadas',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectAllBar() {
    final allSelected = _selecionados.length == _pendentes.length;
    return InkWell(
      onTap: () {
        setState(() {
          if (allSelected) {
            _selecionados.clear();
          } else {
            _selecionados.addAll(_pendentes.map((p) => p.id));
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white,
        child: Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: _selecionados.isNotEmpty && !allSelected,
              onChanged: (_) {
                setState(() {
                  if (allSelected) {
                    _selecionados.clear();
                  } else {
                    _selecionados.addAll(_pendentes.map((p) => p.id));
                  }
                });
              },
              activeColor: AppColors.primaryPurple,
            ),
            const Text(
              'Selecionar todos',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text(
              '${_pendentes.length} pendente(s)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendenteItem(AppointmentPendente ap) {
    final isSelected = _selecionados.contains(ap.id);
    final isDinheiro = ap.isDinheiro;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? AppColors.primaryPurple.withValues(alpha: 0.4)
              : isDinheiro
                  ? Colors.green.shade200
                  : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: ap.nfseAutorizada ? null : () {
          setState(() {
            if (isSelected) {
              _selecionados.remove(ap.id);
            } else {
              _selecionados.add(ap.id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: ap.nfseAutorizada ? null : (v) {
                  setState(() {
                    if (v == true) {
                      _selecionados.add(ap.id);
                    } else {
                      _selecionados.remove(ap.id);
                    }
                  });
                },
                activeColor: AppColors.primaryPurple,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ap.clientName ?? 'Cliente',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDinheiro)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_money,
                                    size: 11, color: Colors.green.shade700),
                                Text(
                                  'Dinheiro',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        if (ap.nfseAutorizada)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded,
                                      size: 11, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'NF-e EMITIDA',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ap.serviceName ?? 'Serviço',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _currency.format(ap.valorTotal),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        if (ap.scheduledAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _dateFmt.format(ap.scheduledAt!),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: (ap.nfseAutorizada || _emitindoLote) ? null : () => _emitirUma(ap),
                style: TextButton.styleFrom(
                  foregroundColor: ap.nfseAutorizada ? Colors.grey : AppColors.primaryPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: ap.nfseAutorizada ? Colors.grey.shade300 : AppColors.primaryPurple)),
                ),
                child: Text(ap.nfseAutorizada ? 'Enviada' : 'Emitir',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HISTÓRICO TAB ─────────────────────────

  Widget _buildHistoricoTab() {
    if (_historico.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Nenhuma nota no histórico.',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: _historico.length,
        itemBuilder: (_, i) => _buildHistoricoItem(_historico[i]),
      ),
    );
  }

  Widget _buildHistoricoItem(NfseEmissao nota) {
    final statusColor = _statusColor(nota.status);
    final statusLabel = _statusLabel(nota.status);

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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (nota.numeroNfse != null)
                  Text(
                    'NFS-e nº ${nota.numeroNfse}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                const Spacer(),
                Text(
                  _currency.format(nota.valorServico),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nota.tomadorNome != null)
                        Text(nota.tomadorNome!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                      if (nota.createdAt != null)
                        Text(
                          _dateFmt.format(nota.createdAt!),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      if (nota.motivoRejeicao != null && nota.status != 'autorizada')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            nota.motivoRejeicao!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (nota.pdfUrl != null)
                      IconButton(
                        icon: Icon(Icons.picture_as_pdf_rounded,
                            color: Colors.red.shade400, size: 20),
                        tooltip: 'Baixar PDF',
                        onPressed: () => _abrirUrl(nota.pdfUrl!),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    if (nota.status == 'autorizada')
                      IconButton(
                        icon: Icon(Icons.cancel_outlined,
                            color: Colors.red.shade400, size: 20),
                        tooltip: 'Cancelar nota',
                        onPressed: () => _cancelarNota(nota),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'autorizada':
        return Colors.green;
      case 'rejeitada':
        return Colors.red;
      case 'cancelada':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'autorizada':
        return 'Autorizada';
      case 'rejeitada':
        return 'Rejeitada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Pendente';
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showResultSnackbar(bool sucesso, String? erro) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sucesso ? 'Nota emitida com sucesso!' : 'Erro: ${erro ?? 'Falha ao emitir.'}'),
        backgroundColor: sucesso ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── FILTRO DE DATA ────────────────────────

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildDropdownFilter<int>(
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
            child: _buildDropdownFilter<int>(
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
    );
  }

  Widget _buildDropdownFilter<T>({
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
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
