import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import 'package:markaai/core/utils/string_utils.dart';
import 'anamnesis/client_anamnesis_page.dart';
import 'client_register_page.dart';

// Tags pré-definidas para classificação de clientes
const _kPresetTags = [
  {'label': 'VIP', 'emoji': '👑', 'color': 0xFFFFAB00},
  {'label': 'Sumido', 'emoji': '💨', 'color': 0xFF757575},
  {'label': 'Problemático', 'emoji': '⚠️', 'color': 0xFFE53935},
  {'label': 'Novo', 'emoji': '🆕', 'color': 0xFF2E7D32},
];

class ClientDetailsPage extends StatefulWidget {
  final Map<String, dynamic> clientData;
  final String clientId;
  final VoidCallback onClose;
  final String? shopIdOverride;

  /// Chamado após editar ou excluir um cliente manual, para a tela pai
  /// recarregar a lista de clientes.
  final VoidCallback? onChanged;

  /// Chamado imediatamente quando o cliente manual é excluído, permitindo
  /// remoção otimista instantânea na lista pai.
  final VoidCallback? onDeleted;

  const ClientDetailsPage({
    super.key,
    required this.clientData,
    required this.clientId,
    required this.onClose,
    this.shopIdOverride,
    this.onChanged,
    this.onDeleted,
  });

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  String? shopId;
  bool _isLoading = true;
  bool _showTagEditor = false;
  bool _kpisCollapsed = false;
  List<String> _manualTags = [];
  final TextEditingController _customTagController = TextEditingController();
  late TabController _tabController;

  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  Future<List<Map<String, dynamic>>>? _historyFuture;

  // Ficha de Anamnese (Pro)
  bool _anamnesisFilled = false;
  bool _anamnesisChecked = false;

  // Duplicidade de cliente manual (conta própria criada no app com o mesmo telefone)
  bool _hasAuthDuplicate = false;
  String _authDuplicateName = '';
  String _authDuplicateUserId = '';
  String _authDuplicatePhone = '';
  String _authDuplicateCpf = '';
  String _authDuplicateCity = '';
  bool _authDuplicateCompatible = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShopId();
    _fetchFullClientData(); // Busca dados completos (CPF, Endereço, etc) ao iniciar
    if (_manualShopClientId != null) {
      _hasAuthDuplicate = widget.clientData['has_auth_account'] == true;
      if (_hasAuthDuplicate) _kpisCollapsed = true;
      _authDuplicateName =
          (widget.clientData['matched_auth_name'] ?? '').toString();
      _authDuplicateUserId =
          (widget.clientData['matched_auth_id'] ?? '').toString();
      _authDuplicateCpf =
          (widget.clientData['matched_auth_cpf'] ?? '').toString();
      _authDuplicateCity =
          (widget.clientData['matched_auth_city'] ?? '').toString();
      _checkManualDuplicateAccount();
    }
  }

  static String _maskCpf(String? raw) {
    final d = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return '';
    return '***.${d.substring(3, 6)}.${d.substring(6, 9)}-**';
  }

  static String _normalizePhoneDigits(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 12 && digits.startsWith('55')) {
      digits = digits.substring(2);
    }
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  static Set<String> _phoneSearchVariants(String raw) {
    final variants = <String>{};
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty && trimmed != 'Não informado') variants.add(trimmed);
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) variants.add(digits);
    final norm = _normalizePhoneDigits(raw);
    if (norm.isNotEmpty) {
      variants.add(norm);
      variants.add('55$norm');
      if (norm.length == 11) {
        variants.add(
            '(${norm.substring(0, 2)}) ${norm.substring(2, 7)}-${norm.substring(7)}');
      } else if (norm.length == 10) {
        variants.add(
            '(${norm.substring(0, 2)}) ${norm.substring(2, 6)}-${norm.substring(6)}');
      }
    }
    return variants;
  }

  static bool _isCompatibleClientName(String nameA, String nameB) {
    List<String> tokenize(String s) {
      final clean = StringUtils.removeDiacritics(s)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .trim();
      if (clean.isEmpty) return [];
      const stopWords = {'de', 'da', 'do', 'das', 'dos', 'e'};
      return clean
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && !stopWords.contains(t))
          .toList();
    }

    final tokensA = tokenize(nameA);
    final tokensB = tokenize(nameB);
    if (tokensA.isEmpty || tokensB.isEmpty) return false;
    if (tokensA.first != tokensB.first) return false;
    if (tokensA.length >= 2 && tokensB.length >= 2) {
      final lastA = tokensA.sublist(1).toSet();
      final lastB = tokensB.sublist(1).toSet();
      return lastA.intersection(lastB).isNotEmpty;
    }
    return true;
  }

  static bool _isCompatibleCpf(String? cpfA, String? cpfB) {
    final a = (cpfA ?? '').replaceAll(RegExp(r'\D'), '');
    final b = (cpfB ?? '').replaceAll(RegExp(r'\D'), '');
    if (a.length == 11 && b.length == 11) {
      return a == b;
    }
    return true;
  }

  Future<void> _checkManualDuplicateAccount() async {
    if (_manualShopClientId == null) return;
    final rawPhone =
        (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
            .toString();
    final normPhone = _normalizePhoneDigits(rawPhone);
    if (normPhone.length < 8) return;

    try {
      final candidates = _phoneSearchVariants(rawPhone).toList();
      if (candidates.isEmpty) return;
      final usersFound = await _supabase
          .from('users')
          .select('id, name, phone, email, cpf, city, state')
          .inFilter('phone', candidates)
          .limit(10);

      final manualName =
          (widget.clientData['nome'] ?? widget.clientData['name'] ?? '')
              .toString();
      final manualCpf = widget.clientData['cpf']?.toString();

      Map<String, dynamic>? bestMatch;
      bool bestCompatible = false;

      for (final row in usersFound) {
        if (_normalizePhoneDigits((row['phone'] ?? '').toString()) !=
            normPhone) {
          continue;
        }
        final compatible = _isCompatibleCpf(
                manualCpf, row['cpf']?.toString()) &&
            _isCompatibleClientName(manualName, (row['name'] ?? '').toString());
        if (bestMatch == null || (compatible && !bestCompatible)) {
          bestMatch = Map<String, dynamic>.from(row as Map);
          bestCompatible = compatible;
          if (bestCompatible) break;
        }
      }

      if (!mounted) return;
      if (bestMatch != null) {
        final city = (bestMatch['city'] ?? '').toString();
        final state = (bestMatch['state'] ?? '').toString();
        setState(() {
          _hasAuthDuplicate = true;
          _kpisCollapsed = true;
          _authDuplicateName = (bestMatch!['name'] ?? '').toString();
          _authDuplicateUserId = (bestMatch['id'] ?? '').toString();
          _authDuplicatePhone = (bestMatch['phone'] ?? '').toString();
          _authDuplicateCpf = (bestMatch['cpf'] ?? '').toString();
          _authDuplicateCity =
              city.isNotEmpty && state.isNotEmpty ? '$city - $state' : city;
          _authDuplicateCompatible = bestCompatible;
        });
      } else if (_hasAuthDuplicate && _authDuplicateUserId.isNotEmpty) {
        // Caso já viesse pré-preenchido via clientData
        setState(() {
          _authDuplicateCompatible =
              _isCompatibleClientName(manualName, _authDuplicateName);
        });
      }
    } catch (e) {
      debugPrint('Erro ao verificar conta duplicada para cliente manual: $e');
    }
  }

  /// ID (shop_clients.id) somente se este for um cadastro MANUAL do lojista,
  /// sem conta Auth. Para qualquer cliente que criou a própria conta retorna
  /// null: nesse caso o lojista NÃO pode editar nem excluir.
  String? get _manualShopClientId {
    if (widget.clientData['is_manual_client'] != true) return null;
    const prefix = 'manual_sc_';
    if (!widget.clientId.startsWith(prefix)) return null;
    final id = widget.clientId.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  Future<void> _editManualClient() async {
    final id = _manualShopClientId;
    if (id == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClientRegisterPage(
          isBusinessAdding: true,
          manualClientId: id,
        ),
      ),
    );
    if (changed == true) {
      await _refreshManualClientData();
      widget.onChanged?.call();
    }
  }

  /// Recarrega os dados do cadastro manual após edição.
  Future<void> _refreshManualClientData() async {
    final id = _manualShopClientId;
    if (id == null) return;
    try {
      final doc = await _supabase
          .from('shop_clients')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (doc == null || !mounted) return;
      setState(() {
        final nome = (doc['nome'] ?? '').toString();
        widget.clientData['nome'] = nome;
        widget.clientData['name'] = nome;
        widget.clientData['telefone'] = (doc['telefone'] ?? '').toString();
        widget.clientData['email'] = doc['email'] ?? '';
        widget.clientData['cpf'] = doc['cpf'] ?? '';
        widget.clientData['birthDate'] = doc['birth_date'] ?? '';
        widget.clientData['zipCode'] = doc['zip_code'] ?? '';
        widget.clientData['street'] = doc['street'] ?? '';
        widget.clientData['number'] = doc['number'] ?? '';
        widget.clientData['neighborhood'] = doc['neighborhood'] ?? '';
        widget.clientData['city'] = doc['city'] ?? '';
        widget.clientData['state'] = doc['state'] ?? '';
        final photo = (doc['photo_url'] ?? '').toString();
        widget.clientData['photo_url'] = photo;
        widget.clientData['foto'] = photo;
        widget.clientData['foto_perfil'] = photo;
      });
      _refreshHistory();
      await _checkManualDuplicateAccount();
    } catch (e) {
      debugPrint('Erro ao recarregar cliente manual: $e');
    }
  }

  Future<void> _deleteManualClient() async {
    final id = _manualShopClientId;
    if (id == null) return;
    final sid = shopId ?? await SessionService.getShopId();
    if (sid == null) return;

    final nome = (widget.clientData['nome'] ??
            widget.clientData['name'] ??
            'este cliente')
        .toString();
    final rawPhone =
        (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
            .toString();
    final normPhone = _normalizePhoneDigits(rawPhone);
    final phoneVariants = _phoneSearchVariants(rawPhone).toList();

    bool matchesThisManualClient(Map<String, dynamic> row) {
      final rowName = (row['client_name'] ?? '').toString();
      final rowPhone =
          _normalizePhoneDigits((row['client_phone'] ?? '').toString());
      if (normPhone.isNotEmpty && rowPhone != normPhone) return false;
      return _isCompatibleClientName(nome, rowName);
    }

    // 1. Bloquear exclusão se houver agendamentos futuros ativos
    try {
      const inactiveStatuses = {
        'cancelado',
        'cancelled',
        'canceled',
        'rejeitado',
        'recusado',
        'excluido',
        'pre_reserva',
        'concluido',
        'concluído',
        'pago',
        'finalizado',
        'completed',
      };

      var futureQuery = _supabase
          .from('appointments')
          .select('id, scheduled_at, status, client_name, client_phone')
          .eq('shop_id', sid)
          .isFilter('client_id', null)
          .gte('scheduled_at', DateTime.now().toUtc().toIso8601String());

      if (phoneVariants.isNotEmpty) {
        futureQuery = futureQuery.inFilter('client_phone', phoneVariants);
      } else {
        futureQuery = futureQuery.eq('client_name', nome);
      }

      final futureRows = await futureQuery.limit(50);
      final hasActiveFuture = futureRows.any((r) {
        final st = (r['status'] ?? '').toString().toLowerCase().trim();
        if (inactiveStatuses.contains(st)) return false;
        return matchesThisManualClient(Map<String, dynamic>.from(r as Map));
      });

      if (hasActiveFuture) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.orange.withValues(alpha: 0.12),
                      child: Icon(Icons.event_busy_rounded,
                          size: 28, color: Colors.orange.shade800),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Agendamento futuro ativo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$nome possui agendamento(s) futuro(s) em aberto.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cancele ou conclua o agendamento futuro antes de excluir este cadastro manual.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Entendi',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Erro ao verificar agendamentos futuros: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao verificar agendamentos: $e'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    if (!mounted) return;
    final bool canTransferToAuth =
        _authDuplicateUserId.isNotEmpty && _authDuplicateCompatible;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.errorRed.withValues(alpha: 0.1),
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 28, color: AppColors.errorRed),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Excluir cadastro manual?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  nome,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryPurple,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        canTransferToAuth
                            ? Icons.sync_alt_rounded
                            : Icons.history_rounded,
                        size: 18,
                        color: AppColors.primaryPurple,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          canTransferToAuth
                              ? 'Os agendamentos anteriores compatíveis serão vinculados automaticamente à conta oficial de $_authDuplicateName no app, removendo apenas este registro manual duplicado.'
                              : 'O histórico financeiro de agendamentos passados da loja será preservado, e este cadastro manual não aparecerá mais na lista.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.errorRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Excluir manual',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      // 2. Verificar agendamentos passados órfãos deste cliente na loja
      var orphanQuery = _supabase
          .from('appointments')
          .select('id, client_name, client_phone')
          .eq('shop_id', sid)
          .isFilter('client_id', null);

      if (phoneVariants.isNotEmpty) {
        orphanQuery = orphanQuery.inFilter('client_phone', phoneVariants);
      } else {
        orphanQuery = orphanQuery.eq('client_name', nome);
      }

      final orphanRows = await orphanQuery.limit(500);
      final orphanIds = orphanRows
          .where((r) =>
              matchesThisManualClient(Map<String, dynamic>.from(r as Map)))
          .map((r) => r['id'])
          .where((rowId) => rowId != null)
          .toList();

      if (orphanIds.isNotEmpty && canTransferToAuth) {
        // Vincula agendamentos órfãos à conta oficial compatível antes de remover o manual
        await _supabase.from('appointments').update(
            {'client_id': _authDuplicateUserId}).inFilter('id', orphanIds);
      }

      if (orphanIds.isNotEmpty && !canTransferToAuth) {
        // Soft-delete: preserva histórico financeiro sem recriar o cliente na lista
        try {
          await _supabase
              .from('shop_clients')
              .update({
                'notes': '[DELETED_MANUAL]',
                'is_deleted': true,
                'last_updated': DateTime.now().toIso8601String(),
              })
              .eq('id', id)
              .eq('is_manual_client', true)
              .isFilter('user_id', null);
        } catch (_) {
          // Fallback caso a coluna is_deleted ainda não exista antes da migração
          await _supabase
              .from('shop_clients')
              .update({
                'notes': '[DELETED_MANUAL]',
                'last_updated': DateTime.now().toIso8601String(),
              })
              .eq('id', id)
              .eq('is_manual_client', true)
              .isFilter('user_id', null);
        }
      } else {
        // Delete físico protegido: só atinge cadastro manual sem conta Auth.
        final deleted = await _supabase
            .from('shop_clients')
            .delete()
            .eq('id', id)
            .eq('is_manual_client', true)
            .isFilter('user_id', null)
            .select('id');

        if (!mounted) return;
        if (deleted.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Este cliente não pode ser excluído (cadastro feito pelo próprio cliente).'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente excluído com sucesso.'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onDeleted?.call();
      widget.onChanged?.call();
      widget.onClose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao excluir cliente: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchFullClientData() async {
    // Cadastro manual do lojista é independente de contas Auth: não mesclar
    // dados de um usuário que por acaso tenha o mesmo telefone.
    if (_manualShopClientId != null) return;
    try {
      // 1. Tenta buscar por ID (UUID)
      Map<String, dynamic>? doc;
      bool isUuid = RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
          .hasMatch(widget.clientId);
      if (isUuid) {
        var query = _supabase.from('users').select().eq('id', widget.clientId);
        doc = await query.maybeSingle();
      }

      // 2. Se não achou por ID (pode ser cliente manual), tenta buscar pelo telefone
      if (doc == null) {
        String? phone =
            widget.clientData['telefone'] ?? widget.clientData['phone'];
        if (phone != null && phone.isNotEmpty) {
          final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
          if (cleanPhone.isNotEmpty) {
            doc = await _supabase
                .from('users')
                .select()
                .eq('phone', cleanPhone)
                .maybeSingle();
          }
        }
      }

      final data = doc;
      if (data != null && mounted) {
        setState(() {
          // Mescla os dados encontrados no clientData local
          widget.clientData['cpf'] = data['cpf'] ?? widget.clientData['cpf'];
          widget.clientData['birthDate'] = data['birth_date'] ??
              data['birthDate'] ??
              widget.clientData['birthDate'];
          widget.clientData['zipCode'] = data['zip_code'] ??
              data['zipCode'] ??
              widget.clientData['zipCode'];
          widget.clientData['street'] =
              data['street'] ?? widget.clientData['street'];
          widget.clientData['neighborhood'] =
              data['neighborhood'] ?? widget.clientData['neighborhood'];
          widget.clientData['city'] = data['city'] ?? widget.clientData['city'];
          widget.clientData['state'] =
              data['state'] ?? widget.clientData['state'];
          widget.clientData['number'] =
              data['number'] ?? widget.clientData['number'];

          // Se o nome no banco for mais completo, atualiza também
          if ((data['name']?.toString() ?? '').isNotEmpty) {
            widget.clientData['nome'] = data['name'];
            widget.clientData['name'] = data['name'];
          }

          // Atualiza foto do Google / perfil (photo_url no banco users)
          final photoFromDb = data['photo_url']?.toString() ?? '';
          if (photoFromDb.isNotEmpty) {
            // Foto do Google tem prioridade — atualiza todos os campos de foto
            widget.clientData['photo_url'] = photoFromDb;
            widget.clientData['foto'] = photoFromDb;
            widget.clientData['foto_perfil'] = photoFromDb;
          }

          // Telefone também
          if ((data['phone']?.toString() ?? '').isNotEmpty) {
            widget.clientData['telefone'] = data['phone'];
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil completo do cliente: $e');
    }
  }

  @override
  void dispose() {
    _customTagController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopId() async {
    final id = widget.shopIdOverride ?? await SessionService.getShopId();
    if (mounted) {
      setState(() {
        shopId = id;
        _isLoading = false;
      });
      if (id != null) {
        _loadTags(id);
        _loadFeatures(id);
        _refreshHistory();
      }
    }
  }

  // ── FICHA DE ANAMNESE (PRO) ───────────────────────────────────────

  String _anamnesisPrimaryKey() {
    final id = widget.clientId;
    final isUuid = RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(id);
    if (isUuid) return id;
    final phone = _anamnesisPhoneKey();
    return phone ?? id;
  }

  String? _anamnesisPhoneKey() {
    final raw =
        (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
            .toString();
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8 ? 'phone_$digits' : null;
  }

  List<String> _anamnesisAltKeys() {
    final primary = _anamnesisPrimaryKey();
    final keys = <String>{widget.clientId};
    final phone = _anamnesisPhoneKey();
    if (phone != null) keys.add(phone);
    keys.remove(primary);
    return keys.toList();
  }

  Future<void> _refreshAnamnesisFlag() async {
    if (shopId == null || !mounted) return;
    final filled = await ClientAnamnesisPage.hasFilledData(
      shopId: shopId!,
      clientKeys: [_anamnesisPrimaryKey(), ..._anamnesisAltKeys()],
    );
    if (mounted) setState(() => _anamnesisFilled = filled);
  }

  Future<void> _openAnamnesis() async {
    if (!_currentFeatures.clientAnamnesis) {
      UpgradeModal.show(
        context,
        featureName: "Ficha de Anamnese",
        requiredPlan: "Pro",
      );
      return;
    }
    if (shopId == null) return;
    final nome =
        (widget.clientData['nome'] ?? widget.clientData['name'] ?? 'Cliente')
            .toString();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClientAnamnesisPage(
          shopId: shopId!,
          clientKey: _anamnesisPrimaryKey(),
          altClientKeys: _anamnesisAltKeys(),
          clientName: nome,
        ),
      ),
    );
    _refreshAnamnesisFlag();
  }

  Future<void> _loadFeatures(String sid) async {
    // Features are now handled by StreamBuilder in build()
  }

  void _refreshHistory() {
    if (shopId == null) return;
    setState(() {
      _historyFuture = _loadClientHistory();
    });
  }

  DateTime _parseEventDate(Map<String, dynamic> event) {
    try {
      final type = event['_type'] as String? ?? 'appointment';
      final raw =
          type == 'activity' ? event['created_at'] : event['scheduled_at'];
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.parse(raw);
    } catch (_) {}
    return DateTime(2000);
  }

  Future<List<Map<String, dynamic>>> _loadClientHistory() async {
    if (shopId == null) return [];
    final supabase = Supabase.instance.client;
    final List<Map<String, dynamic>> combined = [];

    try {
      // Monta os identificadores do cliente para o filtro server-side
      final tel =
          (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
              .toString()
              .replaceAll(RegExp(r'\D'), '');
      final aliases = (widget.clientData['ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();

      // Monta filtro OR no Postgres
      final orParts = <String>['client_id.eq.${widget.clientId}'];
      if (aliases.isNotEmpty) {
        orParts.add('client_id.in.(${aliases.join(',')})');
      }
      if (tel.isNotEmpty) {
        orParts.add('client_phone.eq.$tel');
      }
      // Telefones extras descobertos pelo Painel de Resgate (cliente com múltiplos números)
      final extraPhones =
          (widget.clientData['extra_phones'] as List<dynamic>? ?? [])
              .map((e) => e.toString().replaceAll(RegExp(r'\D'), ''))
              .where((s) => s.isNotEmpty && s != tel)
              .toSet();
      for (final ep in extraPhones) {
        orParts.add('client_phone.eq.$ep');
      }

      // E-mails extras descobertos
      final extraEmails =
          (widget.clientData['extra_emails'] as List<dynamic>? ?? [])
              .map((e) => e.toString().trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toSet();
      for (final em in extraEmails) {
        orParts.add('client_email.eq.$em');
      }

      final apptRows = await supabase
          .from('appointments')
          .select(
            'id, created_at, scheduled_at, status, service_name, professional_name, '
            'total_price, total_value, '
            'payment_method, payment_status, paid_amount, '
            'client_id, client_phone, client_name, is_imported',
          )
          .eq('shop_id', shopId!)
          .or(orParts.join(','))
          .order('scheduled_at', ascending: false);

      // ── DEDUPLICAÇÃO: elimina linhas duplicadas do Setmore ──────────
      // O Setmore gera uma linha por webhook (criação, cancelamento, etc.)
      // para o mesmo horário. Mantemos só a mais recente por (cliente, scheduled_at).
      final rawAppts = List<Map<String, dynamic>>.from(
          apptRows.map((a) => Map<String, dynamic>.from(a as Map)));
      final deduped = _dedupeAppointments(rawAppts);

      for (final a in deduped) {
        combined.add({...a, '_type': 'appointment'});
      }

      // Busca log de atividades para os agendamentos deduplificados
      final apptIds = deduped
          .map((a) => a['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      if (apptIds.isNotEmpty) {
        final logs = await supabase
            .from('shop_activity_log')
            .select()
            .eq('shop_id', shopId!)
            .inFilter('appointment_id', apptIds)
            .order('created_at', ascending: false);

        for (final l in logs) {
          final et = (l['event_type'] as String? ?? '');
          if (et == 'reagendamento' || et == 'pagamento_confirmado') {
            combined.add(
                Map<String, dynamic>.from(l as Map)..['_type'] = 'activity');
          }
        }
      }
    } catch (e) {
      debugPrint('[ClientHistory] Erro ao carregar: $e');
    }

    combined.sort((a, b) => _parseEventDate(b).compareTo(_parseEventDate(a)));
    return combined;
  }

  /// Deduplica agendamentos por `scheduled_at`, mantendo a linha com status
  /// mais "definitivo" (concluido > cancelado > outros) e, em caso de empate
  /// de status, a linha com `created_at` mais recente.
  ///
  /// No contexto do histórico de um cliente específico, TODAS as linhas já
  /// pertencem ao mesmo cliente (filtro OR no banco garante isso). Portanto
  /// a chave é apenas o instante do agendamento — sem precisar incluir o
  /// identificador do cliente, que pode diferir entre linhas do mesmo evento
  /// quando parte veio do Setmore (sem client_id) e parte do MarkaAI (com
  /// client_id linkado ao usuário).
  static List<Map<String, dynamic>> _dedupeAppointments(
      List<Map<String, dynamic>> rows) {
    // Prioridade de status: quanto menor o índice, mais definitivo
    const statusPriority = {
      'concluido': 0,
      'concluído': 0,
      'pago': 0,
      'finalizado': 0,
      'completed': 0,
      'confirmed_by_client': 1,
      'confirmado': 1,
      'agendado': 1,
      'cancelado': 2,
      'cancelled': 2,
      'canceled': 2,
    };

    int statusScore(String s) => statusPriority[s.toLowerCase().trim()] ?? 3;

    final Map<int, Map<String, dynamic>> dedupMap = {};
    for (final row in rows) {
      final scheduledDt =
          DateTime.tryParse(row['scheduled_at']?.toString() ?? '') ??
              DateTime(1970);
      final key = scheduledDt.millisecondsSinceEpoch;

      final existing = dedupMap[key];
      if (existing == null) {
        dedupMap[key] = row;
      } else {
        final existingScore = statusScore(existing['status']?.toString() ?? '');
        final rowScore = statusScore(row['status']?.toString() ?? '');

        // Prefere o status mais definitivo (menor score)
        if (rowScore < existingScore) {
          dedupMap[key] = row;
        } else if (rowScore == existingScore) {
          // Empate de status → mantém o mais recente (created_at)
          final existingCreated =
              DateTime.tryParse(existing['created_at']?.toString() ?? '') ??
                  DateTime(2000);
          final rowCreated =
              DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                  DateTime(2000);
          if (rowCreated.isAfter(existingCreated)) dedupMap[key] = row;
        }
        // rowScore > existingScore → descarta row (existente é mais definitivo)
      }
    }
    return dedupMap.values.toList();
  }

  static const _kTagNormalize = {
    'vip': 'VIP',
    'sumido': 'Sumido',
    'problemático': 'Problemático',
    'problematico': 'Problemático',
    'novo': 'Novo',
  };

  Future<void> _loadTags(String sid) async {
    try {
      final manualId = _manualShopClientId;
      final doc = manualId != null
          ? await _supabase
              .from('shop_clients')
              .select()
              .eq('id', manualId)
              .maybeSingle()
          : await _supabase
              .from('shop_clients')
              .select()
              .eq('shop_id', sid)
              .eq('user_id', widget.clientId)
              .maybeSingle();
      if (mounted && doc != null) {
        final raw =
            List<String>.from(doc['manual_tags'] ?? doc['manualTags'] ?? []);
        final tags =
            raw.map((t) => _kTagNormalize[t.toLowerCase()] ?? t).toList();
        setState(() => _manualTags = tags);
      }
    } catch (e) {
      debugPrint('Erro ao carregar tags: $e');
    }
  }

  Future<void> _saveTags() async {
    if (shopId == null) return;
    final manualId = _manualShopClientId;
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (manualId == null && !uuidRegex.hasMatch(widget.clientId)) return;

    try {
      // Deriva a classificação oficial baseada nas tags manuais
      String? classification;
      if (_manualTags.contains('Problemático') ||
          _manualTags.contains('problematico')) {
        classification = 'problematico';
      } else if (_manualTags.contains('VIP') || _manualTags.contains('vip')) {
        classification = 'vip';
      } else if (_manualTags.contains('Sumido') ||
          _manualTags.contains('sumido')) {
        classification = 'sumido';
      } else if (_manualTags.contains('Novo') || _manualTags.contains('novo')) {
        classification = 'novo';
      }

      if (manualId != null) {
        await _supabase
            .from('shop_clients')
            .update({
              'manual_tags': _manualTags.map((t) => t.trim()).toList(),
              'classification': classification ?? '',
              'classification_override': classification != null,
              'last_updated': DateTime.now().toIso8601String(),
            })
            .eq('id', manualId)
            .eq('is_manual_client', true);
        widget.onChanged?.call();
        return;
      }

      final existing = await _supabase
          .from('shop_clients')
          .select('id')
          .eq('shop_id', shopId!)
          .eq('user_id', widget.clientId)
          .maybeSingle();

      final dataToSave = {
        'shop_id': shopId,
        'user_id': widget.clientId,
        'manual_tags': _manualTags.map((t) => t.trim()).toList(),
        'classification': classification ?? '',
        'classification_override': classification != null,
        'last_updated': DateTime.now().toIso8601String(),
      };

      if (existing != null) {
        await _supabase
            .from('shop_clients')
            .update(dataToSave)
            .eq('id', existing['id']);
      } else {
        await _supabase.from('shop_clients').insert(dataToSave);
      }
    } catch (e) {
      debugPrint('Erro ao salvar tags: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar classificação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePresetTag(String label) {
    setState(() {
      if (_manualTags.contains(label)) {
        _manualTags.remove(label);
      } else {
        // Regra de exclusividade: apenas uma classificação por vez
        final presets = ['VIP', 'Sumido', 'Problemático', 'Novo'];
        if (presets.contains(label)) {
          _manualTags.removeWhere((t) => presets.contains(t));
        }

        _manualTags.add(label);
      }
    });
    _saveTags();
  }

  void _addCustomTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty || _manualTags.contains(t)) return;
    setState(() => _manualTags.add(t));
    _customTagController.clear();
    _saveTags();
  }

  void _removeCustomTag(String tag) {
    setState(() => _manualTags.remove(tag));
    _saveTags();
  }

  String _cleanServiceName(String name) {
    if (name.isEmpty || name == '--') return name;
    // Remove parênteses que contenham "leia" ou "informa" (ex: " (leia as informações)")
    return name
        .replaceAll(
            RegExp(r'\s*\([^)]*(leia|informa)[^)]*\)', caseSensitive: false),
            '')
        .trim();
  }

  // Stream de histórico (passado) — filtra no servidor via .or() para não perder agendamentos antigos
  Stream<List<Map<String, dynamic>>> _getHistoryStream() {
    if (shopId == null) return const Stream.empty();

    // Monta os filtros do cliente uma vez
    final tel =
        (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
            .toString()
            .replaceAll(RegExp(r'\D'), '');
    final aliases = (widget.clientData['ids'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();

    final orParts = <String>['client_id.eq.${widget.clientId}'];
    if (aliases.isNotEmpty) {
      orParts.add('client_id.in.(${aliases.join(',')})');
    }
    if (tel.isNotEmpty) {
      orParts.add('client_phone.eq.$tel');
    }
    // Telefones extras (cliente com múltiplos números — ex: Setmore vs MarkaAI)
    final extraPhones =
        (widget.clientData['extra_phones'] as List<dynamic>? ?? [])
            .map((e) => e.toString().replaceAll(RegExp(r'\D'), ''))
            .where((s) => s.isNotEmpty && s != tel)
            .toSet();
    for (final ep in extraPhones) {
      orParts.add('client_phone.eq.$ep');
    }

    // E-mails extras
    final extraEmails =
        (widget.clientData['extra_emails'] as List<dynamic>? ?? [])
            .map((e) => e.toString().trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
    for (final em in extraEmails) {
      orParts.add('client_email.eq.$em');
    }

    // Usa StreamController para poder fazer query assíncrona filtrada
    // O stream do Supabase (.stream) não suporta .or(), então gerenciamos manualmente
    final controller = StreamController<List<Map<String, dynamic>>>();

    Future<void> fetchAndEmit() async {
      try {
        final rows = await _supabase
            .from('appointments')
            .select(
              'id, created_at, scheduled_at, status, service_name, professional_name, '
              'total_price, total_value, '
              'payment_method, payment_status, paid_amount, '
              'client_id, client_phone, client_name, is_imported, shop_id',
            )
            .eq('shop_id', shopId!)
            .or(orParts.join(','))
            .order('scheduled_at', ascending: false);

        if (!controller.isClosed) {
          controller.add(List<Map<String, dynamic>>.from(rows));
        }
      } catch (e) {
        debugPrint('[HistoryStream] Erro: $e');
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetchAndEmit();

    controller.onCancel = () => controller.close();
    return controller.stream;
  }

  // Stream de próximos agendamentos
  Stream<List<Map<String, dynamic>>> _getUpcomingStream() {
    if (shopId == null) return const Stream.empty();
    final now = DateTime.now();

    final query = _supabase
        .from('appointments')
        .stream(primaryKey: ['id']).eq('shop_id', shopId!);

    return query.map((list) {
      final filtered = list.where((d) {
        final matchesShop = (d['shop_id'] ?? d['shopId']) == shopId;
        if (!matchesShop) return false;

        // Filtro de tempo
        final eventDate = _parseEventDate(d);
        if (eventDate.isBefore(now)) return false; // apenas futuros

        // Lógica unificada de match
        bool isMatch = false;
        if ((d['client_id'] ?? d['clientId']) == widget.clientId) {
          isMatch = true;
        }

        if (!isMatch) {
          final aliases = widget.clientData['ids'] as List<dynamic>?;
          final dId = (d['client_id'] ?? d['clientId'])?.toString();
          if (aliases != null && dId != null && aliases.contains(dId)) {
            isMatch = true;
          }
        }

        if (!isMatch) {
          final tel = (widget.clientData['telefone'] ??
                  widget.clientData['phone'] ??
                  '')
              .toString();
          final cleanTel = tel.replaceAll(RegExp(r'\D'), '');
          if (cleanTel.isNotEmpty) {
            final aptPhone = (d['client_phone'] ?? d['client_telefone'] ?? '')
                .toString()
                .replaceAll(RegExp(r'\D'), '');
            if (aptPhone == cleanTel) isMatch = true;
          } else {
            final nome =
                (widget.clientData['nome'] ?? widget.clientData['name'] ?? '')
                    .toString()
                    .trim();
            final aptName =
                (d['client_name'] ?? d['client_nome'] ?? '').toString().trim();
            if (nome.isNotEmpty &&
                aptName.isNotEmpty &&
                aptName.toLowerCase() == nome.toLowerCase()) {
              isMatch = true;
            }
          }
        }

        return isMatch;
      }).toList();

      filtered.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['scheduled_at'].toString()) ?? DateTime(2000);
        final dateB =
            DateTime.tryParse(b['scheduled_at'].toString()) ?? DateTime(2000);
        return dateA.compareTo(dateB); // ascending: true
      });

      return filtered.take(5).toList();
    });
  }

  /// Exibe a foto do cliente em tamanho maior via Dialog com fundo escuro
  void _showPhotoDialog(BuildContext context, String fotoUrl, String nome) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // Fundo escuro clicável para fechar
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Foto ampliada
                      Hero(
                        tag: 'client_photo_${widget.clientId}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            fotoUrl,
                            width: 260,
                            height: 260,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 260,
                              height: 260,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.person,
                                  size: 80, color: Colors.white54),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Nome do cliente
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      const SizedBox(height: 8),
                      // Dica de fechar
                      const Text(
                        'Toque em qualquer lugar para fechar',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Botão X no canto
                Positioned(
                  top: MediaQuery.of(ctx).padding.top + 8,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple));
    }

    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasData) _currentFeatures = snapshot.data!;
        if (_currentFeatures.clientAnamnesis && !_anamnesisChecked) {
          _anamnesisChecked = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _refreshAnamnesisFlag());
        }

        final nome =
            widget.clientData['nome'] ?? widget.clientData['name'] ?? 'Cliente';

        final foto =
            widget.clientData['photo_url']?.toString().isNotEmpty == true
                ? widget.clientData['photo_url'].toString()
                : widget.clientData['foto']?.toString().isNotEmpty == true
                    ? widget.clientData['foto'].toString()
                    : widget.clientData['foto_perfil']?.toString() ?? '';
        final bool isManual = widget.clientData['origem'] == 'manual';
        final Color themeColor =
            isManual ? Colors.orange : AppColors.primaryPurple;
        final initials = nome.isNotEmpty ? nome[0].toUpperCase() : '?';

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              // ── HEADER COMPACTO ──────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Linha 1: Avatar, nome e botão fechar
                    Row(
                      children: [
                        // Avatar clicável para ver foto em tamanho maior
                        GestureDetector(
                          onTap: foto.isNotEmpty
                              ? () => _showPhotoDialog(context, foto, nome)
                              : null,
                          child: Hero(
                            tag: 'client_photo_${widget.clientId}',
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    themeColor.withValues(alpha: 0.8),
                                    themeColor,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                image: foto.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(foto),
                                        fit: BoxFit.cover)
                                    : null,
                                boxShadow: foto.isNotEmpty
                                    ? [
                                        BoxShadow(
                                          color:
                                              themeColor.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: foto.isEmpty
                                  ? Center(
                                      child: Text(initials,
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white)))
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Nome e tipo
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      nome,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if ((widget.clientData['email'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.email_outlined,
                                          size: 13, color: Colors.blueGrey),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          widget.clientData['email'],
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueGrey),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // Botão Ficha de Anamnese (PRO) — abaixo do e-mail
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: _openAnamnesis,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: (_currentFeatures.clientAnamnesis
                                              ? AppColors.primaryPurple
                                              : Colors.grey)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: (_currentFeatures.clientAnamnesis
                                                ? AppColors.primaryPurple
                                                : Colors.grey)
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _currentFeatures.clientAnamnesis
                                              ? Icons.assignment_outlined
                                              : Icons.lock_outline,
                                          size: 14,
                                          color:
                                              _currentFeatures.clientAnamnesis
                                                  ? AppColors.primaryPurple
                                                  : Colors.grey,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Ficha de Anamnese',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                _currentFeatures.clientAnamnesis
                                                    ? AppColors.primaryPurple
                                                    : Colors.grey,
                                          ),
                                        ),
                                        if (!_currentFeatures
                                            .clientAnamnesis) ...[
                                          const SizedBox(width: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amber[700],
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text('PRO',
                                                style: TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white)),
                                          ),
                                        ] else if (_anamnesisFilled) ...[
                                          const SizedBox(width: 5),
                                          const Icon(Icons.check_circle,
                                              size: 13, color: Colors.green),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Botoes Ação
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ações exclusivas de cadastro MANUAL do lojista
                            if (_manualShopClientId != null) ...[
                              Tooltip(
                                message: 'Editar cadastro manual',
                                child: InkWell(
                                  onTap: _editManualClient,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryPurple
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.edit_outlined,
                                        color: AppColors.primaryPurple,
                                        size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Excluir cadastro manual',
                                child: InkWell(
                                  onTap: _deleteManualClient,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorRed
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: AppColors.errorRed,
                                        size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ] else if (widget.clientData['origem'] ==
                                'app') ...[
                              Tooltip(
                                message:
                                    'Cadastro criado pelo próprio cliente (somente leitura)',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryPurple
                                        .withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primaryPurple
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline,
                                          color: AppColors.primaryPurple,
                                          size: 13),
                                      SizedBox(width: 4),
                                      Text(
                                        'Protegido',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryPurple,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],

                            // Botão fechar
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.grey, size: 20),
                              onPressed: widget.onClose,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Linha 2: Tags ativas em destaque (se existirem)
                    if (_manualTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _manualTags.map((tag) {
                            final preset = _kPresetTags.firstWhere(
                                (p) => p['label'] == tag,
                                orElse: () => {});
                            final color = preset.isNotEmpty
                                ? Color(preset['color'] as int)
                                : AppColors.primaryPurple;
                            final emoji = preset.isNotEmpty
                                ? (preset['emoji'] as String)
                                : '🏷️';
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.5),
                                    width: 1.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(emoji,
                                      style: const TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Text(tag,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: color)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_manualShopClientId != null && _hasAuthDuplicate)
                _buildManualDuplicateComparisonCard(nome),
              if (_manualShopClientId == null &&
                  widget.clientData['has_manual_duplicate'] == true)
                _buildSystemAccountProtectionBanner(),
              if (widget.clientData['ultimoServico'] != null &&
                  widget.clientData['ultimoServico']
                      .toString()
                      .isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_outline_rounded,
                          size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Último serviço: ${widget.clientData['ultimoServico']}",
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── ENDEREÇO (se disponível) ──────────────────────────────────
              Builder(builder: (context) {
                final city =
                    widget.clientData['city']?.toString() ?? '';
                final neighborhood =
                    widget.clientData['neighborhood']?.toString() ?? '';

                if (city.isEmpty && neighborhood.isEmpty) {
                  return const SizedBox.shrink();
                }

                String line1 = '';
                if (neighborhood.isNotEmpty) {
                  line1 = neighborhood;
                  if (city.isNotEmpty) line1 += ' - $city';
                } else if (city.isNotEmpty) {
                  line1 = city;
                }

                String line2 = '';

                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (line1.isNotEmpty)
                              Text(line1,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87)),
                            if (line2.isNotEmpty)
                              Text(line2,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // ── KPI BAR ───────────────────────────────────────────────────
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _getHistoryStream(),
                builder: (context, snap) {
                  final docs = snap.data ?? [];
                  final currency = NumberFormat.currency(
                      locale: 'pt_BR', symbol: 'R\$');

                  // Calcula KPIs
                  double totalGasto = 0;
                  DateTime? lastVisit;
                  DateTime? firstVisit;
                  int completed = 0;
                  int cancelled = 0;
                  String ultimoServico = '--';
                  List<DateTime> completedDates = [];

                  final today = DateTime.now();

                  // Deduplica eventos Setmore usando o mesmo método do histórico visual
                  // → garante que lista e KPIs sempre mostrem os mesmos dados
                  final sortedDocs = _dedupeAppointments(
                      List<Map<String, dynamic>>.from(
                          docs.where((d) => d['_type'] != 'activity')))
                    ..sort((a, b) {
                      final dateA = DateTime.tryParse(
                              a['scheduled_at']?.toString() ?? '') ??
                          DateTime(2000);
                      final dateB = DateTime.tryParse(
                              b['scheduled_at']?.toString() ?? '') ??
                          DateTime(2000);
                      return dateB.compareTo(dateA);
                    });

                  for (final d in sortedDocs) {
                    // Valor: total_price → total_value (sem labor_value para alinhar com o Painel de Resgate)
                    final rawVal =
                        (d['total_price'] ?? d['total_value'] ?? '0')
                            .toString();
                    final cleanVal =
                        rawVal.replaceAll(RegExp(r'[^0-9.]'), '');
                    final val = double.tryParse(cleanVal) ?? 0.0;

                    final rawStatus = (d['status'] ?? '')
                        .toString()
                        .toLowerCase()
                        .trim();
                    final dynDate = d['scheduled_at'];
                    DateTime dt =
                        DateTime.tryParse(dynDate?.toString() ?? '') ??
                            DateTime(2000);

                    bool isPast = !dt.isAfter(today);

                    // ── STATUS VÁLIDOS (idênticos ao banco de dados / Painel de Resgate) ──
                    // Regra: agendamento passado com status válido = visita que ocorreu
                    // 'confirmado' no passado = cliente compareceu mas não foi marcado como concluído
                    bool isValidVisitStatus = rawStatus ==
                            'concluido' ||
                        rawStatus == 'concluído' ||
                        rawStatus == 'pago' ||
                        rawStatus == 'finalizado' ||
                        rawStatus == 'confirmado' ||
                        rawStatus == 'confirmed_by_client' ||
                        rawStatus == 'completed' ||
                        rawStatus ==
                            'agendado'; // Agendamentos antigos que não foram marcados como concluídos

                    bool isCancelled = rawStatus.contains('cancel') ||
                        rawStatus.contains('show') ||
                        rawStatus == 'ausente' ||
                        rawStatus == 'no_show';

                    if (isPast && isValidVisitStatus) {
                      totalGasto += val;
                      completed++;

                      final dtDay = DateTime(dt.year, dt.month, dt.day);
                      completedDates.add(dtDay);

                      if (lastVisit == null || dt.isAfter(lastVisit)) {
                        lastVisit = dt;
                        ultimoServico =
                            d['service_name']?.toString().isNotEmpty ==
                                    true
                                ? _cleanServiceName(
                                    d['service_name'].toString())
                                : '--';
                      }
                      if (firstVisit == null ||
                          dt.isBefore(firstVisit)) {
                        firstVisit = dt;
                      }
                    } else if (isCancelled) {
                      // Só conta cancelados que já passaram (pós-deduplicação: se cancelado
                      // é a versão mais recente do evento, ele realmente foi cancelado)
                      if (isPast) cancelled++;
                    }
                  }

                  final ticketMedio =
                      completed > 0 ? totalGasto / completed : 0.0;
                  final lastVisitStr = lastVisit != null
                      ? DateFormat('dd/MM/yy').format(lastVisit)
                      : '--';
                  final firstVisitStr = firstVisit != null
                      ? DateFormat('dd/MM/yy').format(firstVisit)
                      : '--';
                  final daysSinceLast = lastVisit != null
                      ? DateTime(today.year, today.month, today.day)
                          .difference(DateTime(lastVisit.year,
                              lastVisit.month, lastVisit.day))
                          .inDays
                      : null;
                  final daysSinceStr = daysSinceLast != null
                      ? '$daysSinceLast dias'
                      : '--';

                  // Calcula o intervalo médio localmente
                  int avgInterval = 0;
                  if (completedDates.length > 1) {
                    completedDates.sort((a, b) => a.compareTo(b));
                    int totalDays = 0;
                    int intervals = 0;
                    for (int i = 1; i < completedDates.length; i++) {
                      final diff = completedDates[i]
                          .difference(completedDates[i - 1])
                          .inDays;
                      if (diff > 0) {
                        // Ignora serviços no mesmo dia
                        totalDays += diff;
                        intervals++;
                      }
                    }
                    if (intervals > 0) {
                      avgInterval = (totalDays / intervals).round();
                    }
                  } else if (completedDates.length == 1) {
                    final startOfToday =
                        DateTime(today.year, today.month, today.day);
                    avgInterval = startOfToday
                        .difference(completedDates.first)
                        .inDays;
                  }

                  return Container(
                    color: const Color(0xFFF8F9FD),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Indicadores',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey)),
                            InkWell(
                              onTap: () => setState(() {
                                _kpisCollapsed = !_kpisCollapsed;
                                if (!_kpisCollapsed) {
                                  _showTagEditor = false;
                                }
                              }),
                              child: Icon(
                                _kpisCollapsed
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                size: 20,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        if (!_kpisCollapsed) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _kpiItem(
                                  label: 'Total Gasto',
                                  value: totalGasto > 0
                                      ? currency.format(totalGasto)
                                      : (completed > 0
                                          ? currency.format(0)
                                          : '--'),
                                  icon: Icons.monetization_on_outlined,
                                  color: Colors.green),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Ticket Médio',
                                  value: ticketMedio > 0
                                      ? currency.format(ticketMedio)
                                      : (completed > 0
                                          ? currency.format(0)
                                          : '--'),
                                  icon: Icons.receipt_long,
                                  color: Colors.teal),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Última Visita',
                                  value: lastVisitStr,
                                  icon: Icons.history,
                                  color: themeColor),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _kpiItem(
                                  label: 'Visitas',
                                  value: '$completed',
                                  icon: Icons.calendar_today,
                                  color: Colors.blue),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Cancelados',
                                  value: '$cancelled',
                                  icon: Icons.cancel_outlined,
                                  color: Colors.red),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Intervalo Médio',
                                  value: avgInterval > 0
                                      ? '$avgInterval dias'
                                      : (completed > 0
                                          ? '0 dias'
                                          : '--'),
                                  icon: Icons.timer_outlined,
                                  color: Colors.orange),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _kpiItem(
                                  label: 'Primeira Visita',
                                  value: firstVisitStr,
                                  icon: Icons.celebration_outlined,
                                  color: Colors.indigo),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Dias sem Visita',
                                  value: daysSinceStr,
                                  icon: Icons.event_busy_outlined,
                                  color: daysSinceLast != null &&
                                          daysSinceLast > 60
                                      ? Colors.red
                                      : daysSinceLast != null &&
                                              daysSinceLast > 30
                                          ? Colors.orange
                                          : Colors.green),
                              _kpiDivider(),
                              _kpiItem(
                                  label: 'Último Serviço',
                                  value: ultimoServico,
                                  icon: Icons.cut_outlined,
                                  color: Colors.purple),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // ── TAB BAR ───────────────────────────────────────────────────
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.primaryPurple,
                      indicatorWeight: 3,
                      labelColor: AppColors.primaryPurple,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: const [
                        Tab(text: 'Histórico'),
                        Tab(text: 'Próximos'),
                      ],
                    ),
                    // Botão editar tags
                    InkWell(
                      onTap: () {
                        if (!_currentFeatures.clientClassification) {
                          UpgradeModal.show(
                            context,
                            featureName: "Classificação de Clientes",
                            requiredPlan: "Plus",
                          );
                          return;
                        }
                        setState(() {
                          _showTagEditor = !_showTagEditor;
                          if (_showTagEditor) _kpisCollapsed = true;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _currentFeatures.clientClassification
                              ? AppColors.primaryPurple.withValues(alpha: 0.04)
                              : Colors.grey.withValues(alpha: 0.1),
                          border: Border(
                              top: BorderSide(
                                  color: (_currentFeatures.clientClassification
                                          ? AppColors.primaryPurple
                                          : Colors.grey)
                                      .withValues(alpha: 0.1))),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                _currentFeatures.clientClassification
                                    ? (_showTagEditor
                                        ? Icons.label
                                        : Icons.label_outline)
                                    : Icons.lock,
                                size: 16,
                                color: _currentFeatures.clientClassification
                                    ? AppColors.primaryPurple
                                    : Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                                !_currentFeatures.clientClassification
                                    ? 'Classificação (Bloqueado)'
                                    : (_showTagEditor
                                        ? 'Ocultar editor de tags'
                                        : 'Gerenciar Tags'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _currentFeatures.clientClassification
                                        ? AppColors.primaryPurple
                                        : Colors.grey,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (_currentFeatures.clientClassification)
                              Icon(
                                  _showTagEditor
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: AppColors.primaryPurple),
                          ],
                        ),
                      ),
                    ),
                    if (_showTagEditor) _buildTagEditor(),
                  ],
                ),
              ),

              // ── CONTEÚDO DAS ABAS ─────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // ABA 1: HISTÓRICO
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _historyFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primaryPurple));
                        }
                        final events = snapshot.data ?? [];
                        if (events.isEmpty) {
                          return _emptyState(
                              icon: Icons.history,
                              message: 'Nenhum histórico encontrado');
                        }
                        return RefreshIndicator(
                          color: AppColors.primaryPurple,
                          onRefresh: () async => _refreshHistory(),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            itemCount: events.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final ev = events[i];
                              if (ev['_type'] == 'activity') {
                                return _buildActivityEventCard(ev);
                              }
                              return _buildHistoryCard(ev);
                            },
                          ),
                        );
                      },
                    ),

                    // ABA 2: PRÓXIMOS
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _getUpcomingStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = snapshot.data ?? [];
                        if (docs.isEmpty) {
                          return _emptyState(
                              icon: Icons.event_available,
                              message: 'Sem agendamentos futuros');
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            return _buildUpcomingCard(docs[i]);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── WIDGETS AUXILIARES ────────────────────────────────────────────

  Widget _kpiItem(
      {required String label,
      required String value,
      required IconData icon,
      required Color color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _kpiDivider() => Container(
      width: 1, height: 36, color: Colors.grey.withValues(alpha: 0.2));

  Widget _buildComparisonRow({
    required String badge,
    required Color color,
    required String summary,
    IconData? trailingIcon,
  }) {
    return Row(
      children: [
        Container(
          width: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 2),
                Icon(trailingIcon, size: 10, color: color),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            summary,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildManualDuplicateComparisonCard(String manualName) {
    final manualPhone = (widget.clientData['telefone'] ??
            widget.clientData['phone'] ??
            'Não informado')
        .toString();
    final maskedManualCpf = _maskCpf(widget.clientData['cpf']?.toString());
    final maskedAuthCpf = _maskCpf(_authDuplicateCpf);
    final authName =
        _authDuplicateName.isNotEmpty ? _authDuplicateName : manualName;
    final authPhone =
        _authDuplicatePhone.isNotEmpty ? _authDuplicatePhone : manualPhone;

    final manualParts = <String>[
      manualName,
      manualPhone,
      if (maskedManualCpf.isNotEmpty) maskedManualCpf,
    ];
    final authParts = <String>[
      authName,
      authPhone,
      if (maskedAuthCpf.isNotEmpty) maskedAuthCpf,
      if (_authDuplicateCity.isNotEmpty) _authDuplicateCity,
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows_rounded,
                  size: 14, color: Colors.orange.shade900),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Duplicado com conta do app',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildComparisonRow(
            badge: 'LOJA',
            color: Colors.orange.shade900,
            summary: manualParts.join(' • '),
          ),
          const SizedBox(height: 4),
          _buildComparisonRow(
            badge: 'APP',
            color: AppColors.primaryPurple,
            trailingIcon: Icons.lock_outline,
            summary: authParts.join(' • '),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemAccountProtectionBanner() {
    final dupManualName =
        (widget.clientData['manual_duplicate_name'] ?? 'Cliente').toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline,
              size: 14, color: AppColors.primaryPurple),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Conta do cliente (protegida) • Duplica com "$dupManualName"',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryPurple,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagEditor() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        border: Border(
            top: BorderSide(
                color: AppColors.primaryPurple.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags pré-definidas
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kPresetTags.map((tag) {
              final label = tag['label'] as String;
              final emoji = tag['emoji'] as String;
              final color = Color(tag['color'] as int);
              final isActive = _manualTags.contains(label);
              return GestureDetector(
                onTap: () => _togglePresetTag(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isActive ? color.withValues(alpha: 0.14) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? color : Colors.grey[300]!,
                      width: isActive ? 1.5 : 1,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                                color: color.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? color : Colors.grey[600])),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle, size: 13, color: color),
                    ],
                  ]),
                ),
              );
            }).toList(),
          ),

          // Tags customizadas existentes
          if (_manualTags.any((t) => !_kPresetTags.any((p) => p['label'] == t)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _manualTags
                    .where((t) => !_kPresetTags.any((p) => p['label'] == t))
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              AppColors.primaryPurple.withValues(alpha: 0.08),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => _removeCustomTag(t),
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          side: BorderSide(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.3)),
                        ))
                    .toList(),
              ),
            ),

          // Campo para tag personalizada
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _customTagController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Nova tag personalizada...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  isDense: true,
                ),
                onSubmitted: _addCustomTag,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _addCustomTag(_customTagController.text),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: const BoxDecoration(
                    color: AppColors.primaryPurple, shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildActivityEventCard(Map<String, dynamic> data) {
    final eventType = data['event_type'] as String? ?? '';
    final description = data['description'] as String? ?? '';
    final actorName = data['actor_name'] as String? ?? '';
    DateTime date;
    try {
      final raw = data['created_at'];
      date = raw is DateTime ? raw : DateTime.parse(raw.toString());
    } catch (_) {
      date = DateTime.now();
    }

    final bool isReschedule = eventType == 'reagendamento';
    final bool isPayment = eventType == 'pagamento_confirmado';

    final Color accentColor = isPayment
        ? Colors.green
        : isReschedule
            ? AppColors.primaryPurple
            : Colors.orange;

    final IconData icon = isPayment
        ? Icons.credit_card_rounded
        : isReschedule
            ? Icons.swap_horiz_rounded
            : Icons.info_outline;

    final String label = isPayment
        ? 'PAGAMENTO'
        : isReschedule
            ? 'REAGENDADO'
            : 'ATUALIZAÇÃO';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone de evento
          Container(
            width: 42,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: accentColor),
                Text(DateFormat('dd').format(date),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: accentColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 9,
                              color: accentColor,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(DateFormat('dd/MM/yy HH:mm').format(date),
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        decoration: TextDecoration.none)),
                if (actorName.isNotEmpty)
                  Text(actorName,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                          decoration: TextDecoration.none)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    DateTime date;
    try {
      final dynDate = data['scheduled_at'];
      if (dynDate is DateTime) {
        date = dynDate;
      } else if (dynDate is String) {
        date = DateTime.parse(dynDate);
      } else {
        date = DateTime.now();
      }
    } catch (_) {
      date = DateTime.now();
    }
    final double valor = double.tryParse(
            (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? '0')
                .toString()) ??
        0.0;
    final String servico = _cleanServiceName(data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço');
    final String profissional = data['profissional_nome'] ?? '';
    final String rawStatus = (data['status'] ?? 'agendado').toLowerCase();

    // Lógica para tratar agendamentos passados não-cancelados como concluídos visualmente
    bool isPast = date
        .isBefore(DateTime.now().subtract(const Duration(hours: 4))); // Passado
    bool isCancelled = rawStatus.contains('cancel') ||
        rawStatus.contains('show') ||
        rawStatus == 'ausente';
    bool isCompletedExplicit = rawStatus == 'concluido' ||
        rawStatus == 'concluído' ||
        rawStatus == 'pago' ||
        rawStatus == 'completed';

    String status = rawStatus;
    if (!isCompletedExplicit && isPast && !isCancelled) {
      status = 'concluido'; // Força para a UI
    }

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.schedule;
    if (status == 'concluido' ||
        status == 'concluído' ||
        status == 'pago' ||
        status == 'completed') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (status == 'cancelado') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else if (status == 'agendado') {
      statusColor = Colors.blue;
      statusIcon = Icons.event;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Data no lado esquerdo
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(DateFormat('dd').format(date),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(DateFormat('MMM').format(date),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(servico,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        decoration: TextDecoration.none,
                        color: Colors.black)),
                if (profissional.isNotEmpty)
                  Text(profissional,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          decoration: TextDecoration.none)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(status.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // Valor
          Text(currency.format(valor),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildUpcomingCard(Map<String, dynamic> data) {
    DateTime date;
    try {
      final dynDate = data['scheduled_at'];
      if (dynDate is DateTime) {
        date = dynDate;
      } else if (dynDate is String) {
        date = DateTime.parse(dynDate);
      } else {
        date = DateTime.now();
      }
    } catch (_) {
      date = DateTime.now();
    }
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final double valor = double.tryParse(
            (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? '0')
                .toString()) ??
        0.0;
    final String servico = data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço';
    final String horario = DateFormat('HH:mm').format(date);
    final String profissional = data['profissional_nome'] ?? '';

    final bool isToday = DateFormat('yyyyMMdd').format(date) ==
        DateFormat('yyyyMMdd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isToday
            ? AppColors.primaryPurple.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isToday
                ? AppColors.primaryPurple.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Datetime badge
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? AppColors.primaryPurple : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(DateFormat('dd').format(date),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isToday ? Colors.white : Colors.black)),
                Text(DateFormat('MMM').format(date),
                    style: TextStyle(
                        fontSize: 10,
                        color: isToday ? Colors.white70 : Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.primaryPurple,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('HOJE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    Expanded(
                      child: Text(servico,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              decoration: TextDecoration.none,
                              color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 11, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(horario,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (profissional.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.person_outline,
                          size: 11, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(profissional,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ],
                ),
              ],
            ),
          ),

          Text(currency.format(valor),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Colors.grey[200]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }
}
