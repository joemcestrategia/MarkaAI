import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/widgets/plan_gate_widget.dart';
import '../business/subscription_service.dart';
import '../../widgets/upgrade_modal.dart';
import 'nfse_service.dart';

class NfseConfigScreen extends StatefulWidget {
  const NfseConfigScreen({super.key});

  @override
  State<NfseConfigScreen> createState() => _NfseConfigScreenState();
}

class _NfseConfigScreenState extends State<NfseConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = NfseService();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _shopId;
  NfseConfig? _existingConfig;

  final _cnpjCtrl = TextEditingController();
  final _inscricaoCtrl = TextEditingController();
  final _codigoMunicipioCtrl = TextEditingController();
  final _codigoServicoCtrl = TextEditingController();
  final _codigoTributacaoCtrl = TextEditingController();
  final _codigoNbsCtrl = TextEditingController();
  final _aliquotaCtrl = TextEditingController();
  String? _presetSelecionado;
  int _regimeTributario = 1;
  bool _emitirAutomaticoDinheiro = false;
  bool _ambienteProducao = false;
  bool _ativo = true;

  // Município
  final _nomeMunicipioCtrl = TextEditingController();
  bool _buscandoMunicipio = false;
  String? _municipioNomeResolvido;

  // Consulta CNPJ
  bool _buscandoCnpj = false;
  Map<String, dynamic>? _cnpjDados;

  static const _regimes = [
    (1, 'Simples Nacional'),
    (2, 'Simples Nacional – Excesso de Sublimite'),
    (3, 'Regime Normal'),
    (4, 'Simples Nacional – MEI'),
  ];

  // BIBLIOTECA DE PRESETS - ITABIRITO/MG
  static const _presetsItabirito = {
    'estetica': {
      'label': 'Salão de Beleza / Estética / Trancista',
      'lc116': '06.01.01',
      'nbs': '126021000',
      'tributacao': '960250100',
      'aliquota': '2.01',
      'help': 'Padrão para cabeleireiros, trancistas e serviços de estética corporal.'
    },
    'limpeza': {
      'label': 'Faxina / Conservação / Limpeza',
      'lc116': '07.10.01',
      'nbs': '102021000',
      'tributacao': '812140000',
      'aliquota': '5.00',
      'help': 'Usado para serviços domésticos e conservação de imóveis.'
    },
    'saude': {
      'label': 'Saúde (Psicólogo / Terapeuta / Médico)',
      'lc116': '04.09.01',
      'nbs': '104011500',
      'tributacao': '865000300',
      'aliquota': '2.00',
      'help': 'Aplicável a clínicas e profissionais de saúde autônomos.'
    },
    'organizer': {
      'label': 'Personal Organizer / Organização',
      'lc116': '17.02.01',
      'nbs': '109051000',
      'tributacao': '821999900',
      'aliquota': '2.00',
      'help': 'Serviços de organização e apoio administrativo.'
    },
  };

  void _aplicarPreset(String key) {
    final p = _presetsItabirito[key];
    if (p == null) return;
    setState(() {
      _presetSelecionado = key;
      _codigoServicoCtrl.text = p['lc116']!;
      _codigoNbsCtrl.text = p['nbs']!;
      _codigoTributacaoCtrl.text = p['tributacao']!;
      _aliquotaCtrl.text = p['aliquota']!;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Configuração para "${p['label']}" aplicada!')),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _cnpjCtrl.dispose();
    _inscricaoCtrl.dispose();
    _codigoMunicipioCtrl.dispose();
    _codigoServicoCtrl.dispose();
    _codigoTributacaoCtrl.dispose();
    _codigoNbsCtrl.dispose();
    _aliquotaCtrl.dispose();
    _nomeMunicipioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      String? id = await SessionService.getShopId();
      if (id == null || id.isEmpty) return;

      setState(() => _shopId = id);

      final config = await _service.getConfig(id);
      if (config != null && mounted) {
        _existingConfig = config;
        _cnpjCtrl.text = config.cnpj;
        _inscricaoCtrl.text = config.inscricaoMunicipal;
        _codigoMunicipioCtrl.text = config.codigoMunicipio;
        _codigoServicoCtrl.text = config.codigoServicoLc116;
        _codigoTributacaoCtrl.text = config.codigoTributacaoMunicipio ?? '';
        _codigoNbsCtrl.text = config.codigoNbs ?? '';
        _aliquotaCtrl.text = config.aliquotaIss.toStringAsFixed(2);
        _regimeTributario = config.regimeTributario;
        _emitirAutomaticoDinheiro = config.emitirAutomaticoDinheiro;
        _ambienteProducao = config.ambiente == 'producao';
        _ativo = config.ativo;
      }
    } catch (e) {
      debugPrint('❌ [NfseConfigScreen] _loadConfig: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── BUSCA DE CNPJ (BrasilAPI) ────────────────────────────────────────────

  Future<void> _buscarCnpj() async {
    final digits = _cnpjCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o CNPJ completo (14 dígitos) antes de buscar.')),
      );
      return;
    }
    setState(() {
      _buscandoCnpj = true;
      _cnpjDados = null;
    });
    try {
      final uri = Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$digits');
      final resp = await http.get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // Preenche código IBGE do município automaticamente
        final ibge = data['codigo_municipio_ibge']?.toString();
        final municipio = data['municipio']?.toString() ?? '';
        final uf = data['uf']?.toString() ?? '';
        if (ibge != null && ibge.isNotEmpty) {
          _codigoMunicipioCtrl.text = ibge;
          setState(() => _municipioNomeResolvido = '$municipio — $uf');
        }
        setState(() => _cnpjDados = data);
      } else if (resp.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CNPJ não encontrado na Receita Federal.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao consultar CNPJ (HTTP ${resp.statusCode}).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha na consulta: ${e.toString().split(':').first}')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCnpj = false);
    }
  }

  // ─── BUSCA DE MUNICÍPIO (BrasilAPI/IBGE) ─────────────────────────────────

  Future<void> _buscarMunicipio() async {
    final q = _nomeMunicipioCtrl.text.trim();
    if (q.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite pelo menos 3 letras do nome.')),
      );
      return;
    }
    setState(() => _buscandoMunicipio = true);
    try {
      // A API do IBGE não suporta ?nome=, então buscamos a lista completa e filtramos localmente.
      final uri = Uri.parse('https://servicodados.ibge.gov.br/api/v1/localidades/municipios');
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final todos = jsonDecode(resp.body) as List;
        if (!mounted) return;
        
        final lowerQ = q.toLowerCase();
        // Remove acentos simples para busca suave
        String removeAcentos(String str) {
          return str.replaceAll(RegExp(r'[áàâã]'), 'a')
                    .replaceAll(RegExp(r'[éèê]'), 'e')
                    .replaceAll(RegExp(r'[íï]'), 'i')
                    .replaceAll(RegExp(r'[óôõ]'), 'o')
                    .replaceAll(RegExp(r'[úü]'), 'u')
                    .replaceAll('ç', 'c');
        }
        
        final cleanQ = removeAcentos(lowerQ);
        
        final lista = todos.where((m) {
          final nome = m['nome']?.toString().toLowerCase() ?? '';
          return removeAcentos(nome).contains(cleanQ);
        }).toList();

        if (lista.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Nenhum município encontrado para "$q".')),
          );
          return;
        }
        // Se um único resultado, preenche automaticamente
        if (lista.length == 1) {
          final m = lista.first as Map;
          _codigoMunicipioCtrl.text = m['id'].toString();
          setState(() => _municipioNomeResolvido =
              '${m['nome']} — ${m['microrregiao']?['mesorregiao']?['UF']?['sigla'] ?? ''}');
          return;
        }
        // Múltiplos resultados → mostrar picker
        final selecionado = await showDialog<Map>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Selecione o Município'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final m = lista[i] as Map;
                  final uf = m['microrregiao']?['mesorregiao']?['UF']?['sigla'] ?? '';
                  return ListTile(
                    title: Text('${m['nome']} — $uf'),
                    subtitle: Text('IBGE: ${m['id']}', style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, m),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
        if (selecionado != null && mounted) {
          final uf = selecionado['microrregiao']?['mesorregiao']?['UF']?['sigla'] ?? '';
          _codigoMunicipioCtrl.text = selecionado['id'].toString();
          setState(() => _municipioNomeResolvido = '${selecionado['nome']} — $uf');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar município: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoMunicipio = false);
    }
  }

  void _showHelp(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primaryPurple),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title, 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
              ),
            ),
          ],
        ),
        content: Text(content, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  // ─── SALVAR CONFIGURAÇÃO ──────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_shopId == null) return;

    setState(() => _isSaving = true);
    try {
      final config = NfseConfig(
        id: _existingConfig?.id,
        shopId: _shopId!,
        cnpj: _cnpjCtrl.text.trim(),
        inscricaoMunicipal: _inscricaoCtrl.text.trim(),
        codigoMunicipio: _codigoMunicipioCtrl.text.trim(),
        codigoServicoLc116: _codigoServicoCtrl.text.trim(),
        codigoTributacaoMunicipio: _codigoTributacaoCtrl.text.trim().isEmpty ? null : _codigoTributacaoCtrl.text.trim(),
        codigoNbs: _codigoNbsCtrl.text.trim().isEmpty ? null : _codigoNbsCtrl.text.trim(),
        aliquotaIss: double.tryParse(_aliquotaCtrl.text.replaceAll(',', '.')) ?? 0.0,
        regimeTributario: _regimeTributario,
        ambiente: _ambienteProducao ? 'producao' : 'homologacao',
        emitirAutomaticoDinheiro: _emitirAutomaticoDinheiro,
        ativo: _ativo,
      );

      await _service.saveConfig(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuração fiscal salva com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── SIMULAÇÃO CHECKLIST FISCAL (DRY RUN) ──────────────────────────────────

  Future<void> _testarConfiguracao() async {
    if (_shopId == null) return;
    
    // Precisamos de um agendamento real para testar (mesmo que seja o último do shop)
    setState(() => _isSaving = true); // Reutilizando flag de loading
    try {
      final resp = await http.post(
        Uri.parse('https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/emitir-nfse'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA',
        },
        body: jsonEncode({
          'shop_id': _shopId,
          'dry_run': true,
          'test_mode': true // Modo de busca automática de agendamento para teste
        }),
      );

      if (!mounted) return;
      final result = jsonDecode(resp.body);

      _showSimulationModal(result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha na simulação: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSimulationModal(Map<String, dynamic> result) {
    bool showTech = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.fact_check_rounded, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
              const Text('Checklist Fiscal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (result['sucesso'] == true)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 10),
                        Expanded(child: Text('Tudo pronto! Seus dados estão corretos para emissão.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 10),
                        Expanded(child: Text('Atenção: Encontramos pendências que impedem a emissão.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                ...(result['checklist'] as List? ?? []).map((item) => ListTile(
                  leading: Icon(
                    item['status'] == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
                    color: item['status'] == 'ok' ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  title: Text(item['campo'], style: const TextStyle(fontSize: 14)),
                  subtitle: Text(item['mensagem'], style: TextStyle(fontSize: 12, color: item['status'] == 'ok' ? Colors.grey : Colors.red.shade700)),
                  dense: true,
                )),
                if (showTech) ...[
                  const Divider(height: 32),
                  const Text('VISÃO TÉCNICA (XML)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey.shade100,
                    child: Text(
                      result['xml_preview'] ?? 'XML não gerado.',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setModalState(() => showTech = !showTech),
              child: Text(showTech ? 'Esconder XML' : 'Ver Detalhes Técnicos'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
              child: const Text('Fechar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        title: const Text(
          'Configuração Fiscal (NFS-e)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppColors.primaryPurple,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                label: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: PlanGateWidget(
        requiredPlan: SubscriptionPlan.pro,
        featureLabel: 'Configurações de NFS-e',
        onUpgradeTap: () => UpgradeModal.show(
          context,
          featureName: 'Emissão de NFS-e Integrada',
          requiredPlan: 'Pro',
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    _buildAmbienteCard(),
                    const SizedBox(height: 16),
                    _buildHelpGuide(),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Assistente de Configuração',
                      children: [
                        const Text(
                          'Selecione seu ramo de atividade para preencher os códigos automaticamente conforme as regras de Itabirito/MG.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _presetSelecionado,
                          decoration: InputDecoration(
                            labelText: 'Seu Ramo de Atividade',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _presetsItabirito.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value['label']!, style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) => v != null ? _aplicarPreset(v) : null,
                        ),
                        if (_presetSelecionado != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _presetsItabirito[_presetSelecionado]!['help']!,
                              style: const TextStyle(fontSize: 11, color: AppColors.primaryPurple, fontStyle: FontStyle.italic),
                            ),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading || _isSaving ? null : _testarConfiguracao,
                            icon: const Icon(Icons.fact_check_rounded, size: 18),
                            label: const Text('Simular Checklist Fiscal'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryPurple,
                              side: const BorderSide(color: AppColors.primaryPurple),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.business_rounded,
                      title: 'Dados do Prestador',
                      children: [
                        _buildField(
                          controller: _cnpjCtrl,
                          label: 'CNPJ',
                          hint: '00.000.000/0000-00',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _CnpjInputFormatter(),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'CNPJ obrigatório';
                            if (v.replaceAll(RegExp(r'\D'), '').length != 14) return 'CNPJ inválido';
                            return null;
                          },
                          suffixIcon: _buscandoCnpj
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.manage_search_rounded),
                                  tooltip: 'Consultar CNPJ na Receita Federal',
                                  color: AppColors.primaryPurple,
                                  onPressed: _buscarCnpj,
                                ),
                        ),
                        if (_cnpjDados != null) _buildCnpjInfoCard(_cnpjDados!),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _inscricaoCtrl,
                          label: 'Inscrição Municipal',
                          hint: 'Ex: 12345678',
                          onHelp: () => _showHelp('Inscrição Municipal', 'É o número de registro da sua empresa na prefeitura. Você encontra este dado no seu Alvará de Funcionamento ou no seu comprovante de MEI.'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Campo obrigatório' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildField(
                                controller: _codigoMunicipioCtrl,
                                label: 'Código IBGE do Município',
                                hint: 'Ex: 3550308',
                                onHelp: () => _showHelp('Código IBGE', 'É o código único que identifica sua cidade. Para Itabirito, o código é 3131901. Você pode consultar o código de qualquer cidade no site do IBGE.'),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                validator: (v) => (v == null || v.isEmpty) ? 'Campo obrigatório' : null,
                              ),
                            ),
                          ],
                        ),
                        if (_municipioNomeResolvido != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.place_rounded, size: 13, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  _municipioNomeResolvido!,
                                  style: const TextStyle(fontSize: 12, color: Colors.green),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _nomeMunicipioCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Buscar município por nome',
                                  hintText: 'Ex: São Paulo',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  labelStyle: const TextStyle(fontSize: 12),
                                ),
                                style: const TextStyle(fontSize: 13),
                                onFieldSubmitted: (_) => _buscarMunicipio(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _buscandoMunicipio ? null : _buscarMunicipio,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryPurple,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _buscandoMunicipio
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.search_rounded,
                                        color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.receipt_long_rounded,
                      title: 'Dados do Serviço',
                      children: [
                        _buildField(
                          controller: _codigoServicoCtrl,
                          label: 'Código LC 116',
                          hint: 'Ex: 7.09',
                          onHelp: () => _showHelp('Código LC 116', 'Define a categoria do serviço prestado segundo a Lei Nacional. Para Salões de Beleza e Barbearias, o código padrão é 06.01 (Barbearia, Cabeleireiros, Manicuros, Pedicuros).'),
                          validator: (v) => (v == null || v.isEmpty) ? 'Campo obrigatório' : null,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _codigoNbsCtrl,
                          label: 'Código NBS',
                          hint: 'Ex: 01040001 (cabeleireiros)',
                          onHelp: () => _showHelp('NBS', 'Nomenclatura Brasileira de Serviços. É uma classificação obrigatória para a reforma tributária. Para Estética/Cabeleireiros, use 01040001.'),
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          controller: _aliquotaCtrl,
                          label: 'Alíquota ISS (%)',
                          hint: 'Ex: 5.00',
                          onHelp: () => _showHelp('Alíquota ISS', 'É a porcentagem que a prefeitura cobra de imposto sobre cada serviço. Geralmente varia entre 2% e 5% conforme sua cidade e regime tributário.'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Campo obrigatório';
                            final val = double.tryParse(v.replaceAll(',', '.'));
                            if (val == null || val < 0 || val > 100) return 'Alíquota inválida (0–100)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildRegimeDropdown(
                          onHelp: () => _showHelp('Regime Tributário', 'Indica como sua empresa paga impostos. \n- MEI: Para quem fatura até 81k/ano. \n- Simples Nacional: Para pequenas empresas.'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSection(
                      icon: Icons.tune_rounded,
                      title: 'Comportamento',
                      children: [
                        _buildSwitch(
                          title: 'Emitir NFS-e automaticamente para pagamentos em Dinheiro',
                          subtitle: 'Se desativado, esses agendamentos ficam na aba Pendentes para emissão manual.',
                          value: _emitirAutomaticoDinheiro,
                          onChanged: (v) => setState(() => _emitirAutomaticoDinheiro = v),
                        ),
                        _buildSwitch(
                          title: 'Módulo fiscal ativo',
                          subtitle: 'Desativar impede novas emissões mas preserva o histórico.',
                          value: _ativo,
                          onChanged: (v) => setState(() => _ativo = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
        ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _save,
              backgroundColor: AppColors.primaryPurple,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text('Salvar Configuração',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
    );
  }

  Widget _buildAmbienteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _ambienteProducao
              ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
              : [const Color(0xFF1565C0), const Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _ambienteProducao ? Icons.verified_rounded : Icons.science_rounded,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ambienteProducao ? 'Ambiente de Produção' : 'Ambiente de Homologação (Testes)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _ambienteProducao
                      ? 'Notas emitidas têm validade jurídica.'
                      : 'Notas são fictícias. Use para validar a integração.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _ambienteProducao,
            onChanged: (v) => setState(() => _ambienteProducao = v),
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.green.shade300,
            inactiveTrackColor: Colors.white30,
            inactiveThumbColor: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _buildHelpGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: Colors.amber.shade800, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Onde encontro esses dados?',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consulte seu Certificado de MEI, Alvará ou peça ajuda ao seu contador. Toque no ícone de informação (?) ao lado de cada campo para entender o que preencher.',
                  style: TextStyle(color: Colors.black87, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryPurple, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCnpjInfoCard(Map<String, dynamic> d) {
    final razao = d['razao_social']?.toString() ?? '';
    final fantasia = d['nome_fantasia']?.toString() ?? '';
    final situacao = d['descricao_situacao_cadastral']?.toString() ?? '';
    final porte = d['descricao_porte']?.toString() ?? '';
    final municipio = d['municipio']?.toString() ?? '';
    final uf = d['uf']?.toString() ?? '';
    final ativa = (d['situacao_cadastral']?.toString() ?? '') == '2';

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ativa ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ativa ? Colors.green.shade200 : Colors.orange.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.business_rounded,
                size: 15,
                color: ativa ? Colors.green.shade700 : Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  razao,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: ativa ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
          if (fantasia.isNotEmpty) ...[  
            const SizedBox(height: 2),
            Text(
              fantasia,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _cnpjChip(
                icon: Icons.place_rounded,
                label: '$municipio — $uf',
                color: Colors.blue,
              ),
              if (situacao.isNotEmpty)
                _cnpjChip(
                  icon: ativa
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  label: situacao,
                  color: ativa ? Colors.green : Colors.orange,
                ),
              if (porte.isNotEmpty)
                _cnpjChip(
                  icon: Icons.storefront_rounded,
                  label: porte,
                  color: Colors.purple,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Município e código IBGE preenchidos automaticamente.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _cnpjChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.9)),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    VoidCallback? onHelp,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
            if (onHelp != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onHelp,
                child: Icon(Icons.help_outline_rounded, size: 16, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            suffixIcon: suffixIcon,
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildRegimeDropdown({VoidCallback? onHelp}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Regime Tributário', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
            if (onHelp != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onHelp,
                child: Icon(Icons.help_outline_rounded, size: 16, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: _regimeTributario,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: _regimes.map((r) {
            return DropdownMenuItem<int>(
              value: r.$1,
              child: Text(r.$2, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _regimeTributario = v);
          },
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primaryPurple,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// FORMATTER CNPJ
// ─────────────────────────────────────────────

class _CnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 14; i++) {
      if (i == 2 || i == 5) buf.write('.');
      if (i == 8) buf.write('/');
      if (i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    final str = buf.toString();
    return TextEditingValue(
      text: str,
      selection: TextSelection.collapsed(offset: str.length),
    );
  }
}
