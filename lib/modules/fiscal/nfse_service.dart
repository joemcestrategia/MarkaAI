import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/session_service.dart';

// ─────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────

class NfseConfig {
  final String? id;
  final String shopId;
  final String cnpj;
  final String inscricaoMunicipal;
  final String codigoMunicipio;
  final String codigoServicoLc116;
  final String? codigoTributacaoMunicipio;
  final String? codigoNbs;
  final double aliquotaIss;
  final int regimeTributario;
  final String ambiente;
  final int exigibilidadeIss;
  final bool incentivadorCultural;
  final double descontoIncondicional;
  final double descontoCondicional;
  final bool emitirAutomaticoDinheiro;
  final bool ativo;

  const NfseConfig({
    this.id,
    required this.shopId,
    required this.cnpj,
    required this.inscricaoMunicipal,
    required this.codigoMunicipio,
    required this.codigoServicoLc116,
    this.codigoTributacaoMunicipio,
    this.codigoNbs,
    required this.aliquotaIss,
    required this.regimeTributario,
    this.ambiente = 'homologacao',
    this.exigibilidadeIss = 1,
    this.incentivadorCultural = false,
    this.descontoIncondicional = 0.0,
    this.descontoCondicional = 0.0,
    this.emitirAutomaticoDinheiro = false,
    this.ativo = true,
  });

  factory NfseConfig.fromMap(Map<String, dynamic> map) {
    return NfseConfig(
      id: map['id'] as String?,
      shopId: map['shop_id'] as String,
      cnpj: map['cnpj'] as String? ?? '',
      inscricaoMunicipal: map['inscricao_municipal'] as String? ?? '',
      codigoMunicipio: map['codigo_municipio'] as String? ?? '',
      codigoServicoLc116: map['codigo_servico_lc116'] as String? ?? '',
      codigoTributacaoMunicipio: map['codigo_tributacao_municipio'] as String?,
      codigoNbs: map['codigo_nbs'] as String?,
      aliquotaIss: (map['aliquota_iss'] as num?)?.toDouble() ?? 0.0,
      regimeTributario: (map['regime_tributario'] as int?) ?? 1,
      ambiente: map['ambiente'] as String? ?? 'homologacao',
      exigibilidadeIss: (map['exigibilidade_iss'] as int?) ?? 1,
      incentivadorCultural: map['incentivador_cultural'] as bool? ?? false,
      descontoIncondicional: (map['desconto_incondicional'] as num?)?.toDouble() ?? 0.0,
      descontoCondicional: (map['desconto_condicional'] as num?)?.toDouble() ?? 0.0,
      emitirAutomaticoDinheiro: map['emitir_automatico_dinheiro'] as bool? ?? false,
      ativo: map['ativo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shop_id': shopId,
      'cnpj': cnpj,
      'inscricao_municipal': inscricaoMunicipal,
      'codigo_municipio': codigoMunicipio,
      'codigo_servico_lc116': codigoServicoLc116,
      if (codigoTributacaoMunicipio != null) 'codigo_tributacao_municipio': codigoTributacaoMunicipio,
      if (codigoNbs != null) 'codigo_nbs': codigoNbs,
      'aliquota_iss': aliquotaIss,
      'regime_tributario': regimeTributario,
      'ambiente': ambiente,
      'exigibilidade_iss': exigibilidadeIss,
      'incentivador_cultural': incentivadorCultural,
      'desconto_incondicional': descontoIncondicional,
      'desconto_condicional': descontoCondicional,
      'emitir_automatico_dinheiro': emitirAutomaticoDinheiro,
      'ativo': ativo,
    };
  }

  NfseConfig copyWith({
    String? id,
    String? shopId,
    String? cnpj,
    String? inscricaoMunicipal,
    String? codigoMunicipio,
    String? codigoServicoLc116,
    String? codigoTributacaoMunicipio,
    String? codigoNbs,
    double? aliquotaIss,
    int? regimeTributario,
    String? ambiente,
    int? exigibilidadeIss,
    bool? incentivadorCultural,
    double? descontoIncondicional,
    double? descontoCondicional,
    bool? emitirAutomaticoDinheiro,
    bool? ativo,
  }) {
    return NfseConfig(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      cnpj: cnpj ?? this.cnpj,
      inscricaoMunicipal: inscricaoMunicipal ?? this.inscricaoMunicipal,
      codigoMunicipio: codigoMunicipio ?? this.codigoMunicipio,
      codigoServicoLc116: codigoServicoLc116 ?? this.codigoServicoLc116,
      codigoTributacaoMunicipio: codigoTributacaoMunicipio ?? this.codigoTributacaoMunicipio,
      codigoNbs: codigoNbs ?? this.codigoNbs,
      aliquotaIss: aliquotaIss ?? this.aliquotaIss,
      regimeTributario: regimeTributario ?? this.regimeTributario,
      ambiente: ambiente ?? this.ambiente,
      exigibilidadeIss: exigibilidadeIss ?? this.exigibilidadeIss,
      incentivadorCultural: incentivadorCultural ?? this.incentivadorCultural,
      descontoIncondicional: descontoIncondicional ?? this.descontoIncondicional,
      descontoCondicional: descontoCondicional ?? this.descontoCondicional,
      emitirAutomaticoDinheiro: emitirAutomaticoDinheiro ?? this.emitirAutomaticoDinheiro,
      ativo: ativo ?? this.ativo,
    );
  }
}

class NfseEmissao {
  final String id;
  final String shopId;
  final String? appointmentId;
  final String? numeroNfse;
  final String? chaveAcesso;
  final String status;
  final double valorServico;
  final String? tomadorCpfCnpj;
  final String? tomadorNome;
  final String? xmlDps;
  final String? xmlNfse;
  final String? pdfUrl;
  final String? codigoVerificacao;
  final String? motivoRejeicao;
  final DateTime? createdAt;
  final String? serviceName;
  final String? clientName;
  final String? paymentMethod;

  const NfseEmissao({
    required this.id,
    required this.shopId,
    this.appointmentId,
    this.numeroNfse,
    this.chaveAcesso,
    required this.status,
    required this.valorServico,
    this.tomadorCpfCnpj,
    this.tomadorNome,
    this.xmlDps,
    this.xmlNfse,
    this.pdfUrl,
    this.codigoVerificacao,
    this.motivoRejeicao,
    this.createdAt,
    this.serviceName,
    this.clientName,
    this.paymentMethod,
  });

  factory NfseEmissao.fromMap(Map<String, dynamic> map) {
    return NfseEmissao(
      id: map['id'] as String,
      shopId: map['shop_id'] as String,
      appointmentId: map['appointment_id'] as String?,
      numeroNfse: map['numero_nfse'] as String?,
      chaveAcesso: map['chave_acesso'] as String?,
      status: map['status'] as String? ?? 'pendente',
      valorServico: (map['valor_servico'] as num?)?.toDouble() ?? 0.0,
      tomadorCpfCnpj: map['tomador_cpf_cnpj'] as String?,
      tomadorNome: map['tomador_nome'] as String?,
      xmlDps: map['xml_dps'] as String?,
      xmlNfse: map['xml_nfse'] as String?,
      pdfUrl: map['pdf_url'] as String?,
      codigoVerificacao: map['codigo_verificacao'] as String?,
      motivoRejeicao: map['motivo_rejeicao'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      serviceName: map['service_name'] as String?,
      clientName: map['client_name'] as String?,
      paymentMethod: map['payment_method'] as String?,
    );
  }
}

class AppointmentPendente {
  final String id;
  final String? clientName;
  final String? serviceName;
  final double valorTotal;
  final String? paymentMethod;
  final DateTime? scheduledAt;
  final bool nfseAutorizada;

  const AppointmentPendente({
    required this.id,
    this.clientName,
    this.serviceName,
    required this.valorTotal,
    this.paymentMethod,
    this.scheduledAt,
    this.nfseAutorizada = false,
  });

  factory AppointmentPendente.fromMap(Map<String, dynamic> map, {bool autorizada = false}) {
    return AppointmentPendente(
      id: map['id'] as String,
      clientName: map['client_name'] as String?,
      serviceName: map['service_name'] as String?,
      valorTotal: (map['total_value'] ?? map['total_price'] ?? map['total_payable'] ?? 0.0 as num).toDouble(),
      paymentMethod: map['payment_method'] as String?,
      scheduledAt: map['scheduled_at'] != null ? DateTime.tryParse(map['scheduled_at'].toString()) : null,
      nfseAutorizada: autorizada,
    );
  }

  bool get isDinheiro => paymentMethod?.toLowerCase().contains('dinheiro') ?? false;
}

class NfseDashboardMetrics {
  final int totalServicosRealizados;
  final int totalNotasEmitidas;
  final int totalPendentes;

  const NfseDashboardMetrics({
    required this.totalServicosRealizados,
    required this.totalNotasEmitidas,
    required this.totalPendentes,
  });
}

class NfseEmissaoResult {
  final String appointmentId;
  final bool sucesso;
  final String? erro;

  const NfseEmissaoResult({
    required this.appointmentId,
    required this.sucesso,
    this.erro,
  });
}

// ─────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────

class NfseService {
  static final NfseService _instance = NfseService._internal();
  factory NfseService() => _instance;
  NfseService._internal();

  final _client = Supabase.instance.client;

  // ─── CONFIGURAÇÃO ATIVA ────────────────────

  /// Retorna true se o shop tem configuração fiscal ativa.
  /// Não lança exceção — safe para uso em fluxos principais.
  Future<bool> configuracaoAtiva(String shopId) async {
    try {
      final data = await _client
          .from('nfse_config')
          .select('id')
          .eq('shop_id', shopId)
          .eq('ativo', true)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  // ─── ADESÃO MUNICIPAL ────────────────────────

  /// Verifica se o município aderiu ao padrão nacional via
  /// GET https://api.nfse.gov.br/v1/parametros_municipais/{codigoMunicipio}
  /// 404 → não aderiu. Erros de rede retornam true (não bloqueiam).
  Future<({bool aderiu, String? motivo})> verificarAdesaoMunicipal(
    String codigoMunicipio,
  ) async {
    try {
      final uri = Uri.parse(
        'https://api.nfse.gov.br/v1/parametros_municipais/$codigoMunicipio',
      );
      final resp = await http.get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 404) {
        return (
          aderiu: false,
          motivo:
              'O município $codigoMunicipio ainda não aderiu ao padrão nacional '
              'de NFS-e. A nota deve ser emitida pelo portal da prefeitura.',
        );
      }
      return (aderiu: true, motivo: null);
    } catch (_) {
      // Falha de rede → não bloqueia a emissão
      return (aderiu: true, motivo: null);
    }
  }

  // ─── CONFIG ────────────────────────────────

  Future<NfseConfig?> getConfig(String shopId) async {
    try {
      final data = await _client
          .from('nfse_config')
          .select()
          .eq('shop_id', shopId)
          .maybeSingle();
      if (data == null) return null;
      return NfseConfig.fromMap(data);
    } catch (e) {
      debugPrint('❌ [NfseService] getConfig: $e');
      return null;
    }
  }

  Future<void> saveConfig(NfseConfig config) async {
    try {
      final map = config.toMap();
      if (config.id != null) {
        await _client.from('nfse_config').update(map).eq('id', config.id!);
      } else {
        await _client.from('nfse_config').insert(map);
      }
    } catch (e) {
      debugPrint('❌ [NfseService] saveConfig: $e');
      rethrow;
    }
  }

  // ─── EMISSÃO ───────────────────────────────

  Future<NfseEmissaoResult> emitirNota(String appointmentId) async {
    try {
      final shopId = await _getShopId();
      if (shopId == null) {
        return NfseEmissaoResult(
          appointmentId: appointmentId,
          sucesso: false,
          erro: 'Shop ID não encontrado.',
        );
      }

      final response = await _client.functions.invoke(
        'emitir-nfse',
        body: {
          'appointment_id': appointmentId,
          'shop_id': shopId,
        },
      );

      if (response.status >= 400) {
        final errorData = response.data;
        final msg = errorData is Map ? errorData['error']?.toString() : 'Erro ao emitir nota.';
        return NfseEmissaoResult(
          appointmentId: appointmentId,
          sucesso: false,
          erro: msg,
        );
      }

      return NfseEmissaoResult(appointmentId: appointmentId, sucesso: true);
    } catch (e) {
      debugPrint('❌ [NfseService] emitirNota($appointmentId): $e');
      return NfseEmissaoResult(
        appointmentId: appointmentId,
        sucesso: false,
        erro: e.toString(),
      );
    }
  }

  Future<List<NfseEmissaoResult>> emitirNotasEmLote(List<String> appointmentIds) async {
    final results = <NfseEmissaoResult>[];
    for (final id in appointmentIds) {
      final result = await emitirNota(id);
      results.add(result);
    }
    return results;
  }

  Future<void> cancelarNota(String nfseId, String motivo) async {
    final response = await _client.functions.invoke(
      'cancelar-nfse',
      body: {
        'nfse_id': nfseId,
        'motivo': motivo,
      },
    );

    if (response.status >= 400) {
      final errorData = response.data;
      final msg = errorData is Map ? errorData['error']?.toString() : 'Erro ao cancelar nota.';
      throw Exception(msg);
    }
  }

  /// Alias para compatibilidade com o contrato público da interface.
  Future<List<NfseEmissao>> listarNotas(String shopId, {int? month, int? year}) => 
      getHistorico(shopId, month: month, year: year);

  /// Hook não-bloqueante: deve ser chamado quando um agendamento é marcado
  /// como 'concluido'. Nunca lança exceção nem interrompe o fluxo principal.
  /// Retorna null silenciosamente se a config fiscal não estiver ativa.
  Future<NfseEmissaoResult?> emitirNotaAposAgendamento({
    required String appointmentId,
    required String shopId,
  }) async {
    try {
      final ativo = await configuracaoAtiva(shopId);
      if (!ativo) return null;
      return await emitirNota(appointmentId);
    } catch (e) {
      debugPrint('⚠️ [NfseService] emitirNotaAposAgendamento silenciado: $e');
      return null;
    }
  }

  // ─── MÉTRICAS ──────────────────────────────

  Future<NfseDashboardMetrics> getDashboardMetrics(String shopId) async {
    try {
      final now = DateTime.now();
      final mesInicio = DateTime(now.year, now.month, 1);
      final mesFim = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

      final servicos = await _client
          .from('appointments')
          .select('id')
          .eq('shop_id', shopId)
          .eq('status', 'concluido')
          .gte('scheduled_at', mesInicio.toIso8601String())
          .lte('scheduled_at', mesFim.toIso8601String());

      final totalServicos = (servicos as List).length;

      final notas = await _client
          .from('nfse_emissoes')
          .select('id')
          .eq('shop_id', shopId)
          .eq('status', 'autorizada')
          .gte('created_at', mesInicio.toIso8601String())
          .lte('created_at', mesFim.toIso8601String());

      final totalNotas = (notas as List).length;

      final pendentes = await getNotasPendentes(shopId);

      return NfseDashboardMetrics(
        totalServicosRealizados: totalServicos,
        totalNotasEmitidas: totalNotas,
        totalPendentes: pendentes.length,
      );
    } catch (e) {
      debugPrint('❌ [NfseService] getDashboardMetrics: $e');
      return const NfseDashboardMetrics(
        totalServicosRealizados: 0,
        totalNotasEmitidas: 0,
        totalPendentes: 0,
      );
    }
  }

  Future<List<AppointmentPendente>> getNotasPendentes(String shopId) async {
    try {
      // 1. Buscar IDs de agendamentos que já possuem nota autorizada
      final autorizados = await _client
          .from('nfse_emissoes')
          .select('appointment_id')
          .eq('shop_id', shopId)
          .eq('status', 'autorizada');

      final autorizadosIds = (autorizados as List)
          .map((e) => e['appointment_id'] as String?)
          .whereType<String>()
          .toSet();

      // 2. Buscar agendamentos concluídos
      // Nota: Buscamos campos de valor alternativos para garantir compatibilidade
      final agendamentos = await _client
          .from('appointments')
          .select('id, client_name, service_name, total_value, total_price, total_payable, payment_method, scheduled_at')
          .eq('shop_id', shopId)
          .eq('status', 'concluido')
          .order('scheduled_at', ascending: false)
          .limit(200);

      final todos = (agendamentos as List).map((e) {
        final map = e as Map<String, dynamic>;
        final id = map['id'] as String;
        
        // Parsing robusto de valor total
        double valor = 0.0;
        try {
          final rawValor = map['total_value'] ?? map['total_price'] ?? map['total_payable'] ?? 0.0;
          valor = (rawValor as num).toDouble();
        } catch (_) {}

        return AppointmentPendente(
          id: id,
          clientName: map['client_name'] as String?,
          serviceName: map['service_name'] as String?,
          valorTotal: valor,
          paymentMethod: map['payment_method'] as String?,
          scheduledAt: map['scheduled_at'] != null ? DateTime.tryParse(map['scheduled_at'].toString()) : null,
          nfseAutorizada: autorizadosIds.contains(id),
        );
      }).toList();

      return todos;
    } catch (e) {
      debugPrint('❌ [NfseService] getNotasPendentes: $e');
      return [];
    }
  }

  Future<List<NfseEmissao>> getHistorico(String shopId, {int? month, int? year}) async {
    try {
      dynamic query = _client
          .from('nfse_emissoes')
          .select()
          .eq('shop_id', shopId)
          .neq('status', 'pendente');

      if (month != null && year != null) {
        final start = DateTime(year, month, 1);
        final end = DateTime(year, month + 1, 0, 23, 59, 59);
        query = query
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String());
      } else {
        query = query.limit(100);
      }

      final data = await query.order('created_at', ascending: false);

      return (data as List)
          .map((e) => NfseEmissao.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ [NfseService] getHistorico: $e');
      return [];
    }
  }

  // ─── HELPERS ───────────────────────────────

  /// Executa um GET e retorna apenas o status HTTP.
  /// Usado pelo dashboard para verificar se a API gov.br está operacional.
  Future<int> httpGet(String url) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );
    return resp.statusCode;
  }

  Future<String?> _getShopId() async {
    String? id = await SessionService.getShopId();
    if (id == null || id.isEmpty) {
      final user = _client.auth.currentUser;
      if (user != null) {
        final doc = await _client
            .from('users')
            .select('shop_id')
            .eq('id', user.id)
            .maybeSingle();
        if (doc != null) id = doc['shop_id'] as String?;
      }
    }
    return id;
  }
}
