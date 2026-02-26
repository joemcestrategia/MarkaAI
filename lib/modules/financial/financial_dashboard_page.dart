import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';
import 'widgets/refund_management_widget.dart';

class FinancialDashboardPage extends StatefulWidget {
  const FinancialDashboardPage({super.key});

  @override
  State<FinancialDashboardPage> createState() => _FinancialDashboardPageState();
}

class _FinancialDashboardPageState extends State<FinancialDashboardPage> {
  String? _shopId;
  bool _isLoading = true;
  bool _isProcessingFile = false;

  // Filtros
  int? _selectedMonth;
  int _selectedYear = DateTime.now().year;
  String _filterType = 'all'; // 'all', 'receita', 'despesa'
  String? _filterBankNormalized;

  // Ordenação
  bool _sortDesc = true;

  // Visualização
  bool _showGraph = false;
  String _graphFilter = 'saldo';

  // Paginação
  final int _pageSize = 25;
  DocumentSnapshot? _lastDocument;
  final List<QueryDocumentSnapshot> _transactions = [];
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // Cache de totais
  double _totalReceita = 0.0;
  double _totalDespesa = 0.0;

  // Listas auxiliares
  final List<String> _months = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez'
  ];
  List<int> _availableYears = [];

  final ScrollController _scrollController = ScrollController();
  final GlobalKey<RefreshIndicatorState> _refreshKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    // Gera de 2022 até o ano atual
    _availableYears = List.generate(
        math.max(1, currentYear - 2022 + 1), (i) => currentYear - i);
    _selectedMonth = DateTime.now().month;

    _loadShopId();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // 🛠️ CORREÇÃO DO SHOP ID + LOGS DE DEBUG
  Future<void> _loadShopId() async {
    try {
      // 1. Tenta pegar da memória local (rápido)
      _shopId = await SessionService.getShopId();

      if (_shopId == null || _shopId!.isEmpty) {
        debugPrint(
            "⚠️ ShopId não encontrado no cache local. Buscando no Firebase...");

        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (doc.exists) {
            _shopId = doc.data()?['shopId'] as String?;

            // 🔥 CORREÇÃO: Salva no SessionService para não buscar de novo
            if (_shopId != null) {
              await SessionService.saveShopId(_shopId!);
              debugPrint("✅ ShopId recuperado e salvo: $_shopId");
            }
          }
        }
      } else {
        // debugPrint("✅ ShopId carregado da sessão: $_shopId");
      }
    } catch (e) {
      debugPrint('❌ Erro crítico ao carregar shopId: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (_shopId != null) _refresh();
    }
  }

  String _normalize(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void _toggleTypeFilter(String type) {
    setState(() {
      _filterType = (_filterType == type) ? 'all' : type;
    });
    _refresh();
  }

  void _toggleBankFilter(String bankNormalized) {
    setState(() {
      _filterBankNormalized =
          (_filterBankNormalized == bankNormalized) ? null : bankNormalized;
    });
    _refresh();
  }

  void _toggleSort() {
    setState(() => _sortDesc = !_sortDesc);
    _refresh();
  }

  void _clearFilters() {
    setState(() {
      _filterType = 'all';
      _filterBankNormalized = null;
      _selectedMonth = DateTime.now().month;
      _selectedYear = DateTime.now().year;
      _sortDesc = true;
    });
    _refresh();
  }

  // 📊 LEITURA DE TOTAIS (Monitorada)
  Future<void> _loadTotals() async {
    if (_shopId == null) return;
    final monthKey = _selectedMonth != null ? '_$_selectedMonth' : '_all';
    final summaryId = '$_shopId$_selectedYear$monthKey';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('financial_summaries')
          .doc(summaryId)
          .get();

      // 📊 LOG DE CUSTO - RESUMO
      if (doc.metadata.isFromCache) {
        // debugPrint("💰 [RESUMO] Leitura do Cache (Grátis)");
      } else {
        debugPrint("💸 [RESUMO] 1 Leitura no Servidor (Custo Baixo)");
      }

      if (doc.exists) {
        final data = doc.data()!;
        _totalReceita = (data['total_receita'] as num?)?.toDouble() ?? 0.0;
        _totalDespesa = (data['total_despesa'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Se não existe resumo, tentamos calcular na mão (fallback)
        await _calculateTotalsManually();
      }
    } catch (e) {
      debugPrint('Erro ao carregar totais: $e');
      await _calculateTotalsManually();
    }

    if (mounted) setState(() {});
  }

  Future<void> _calculateTotalsManually() async {
    if (_shopId == null) return;

    try {
      final start = _selectedMonth == null
          ? DateTime(_selectedYear, 1, 1)
          : DateTime(_selectedYear, _selectedMonth!, 1);
      final end = _selectedMonth == null
          ? DateTime(_selectedYear + 1, 1, 1)
              .subtract(const Duration(seconds: 1))
          : DateTime(_selectedYear, _selectedMonth! + 1, 0, 23, 59, 59);

      // Aqui usamos get() normal, que pode gastar leitura se não tiver cache
      final snapshot = await FirebaseFirestore.instance
          .collection('financial_transactions')
          .where('shopId', isEqualTo: _shopId)
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      // 📊 LOG DE CUSTO - CÁLCULO MANUAL
      if (!snapshot.metadata.isFromCache) {
        debugPrint(
            "⚠️ [MANUAL] Calculando totais lendo ${snapshot.docs.length} docs (Dica: Use o botão Otimizar)");
      }

      double receita = 0.0;
      double despesa = 0.0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final valorNum = data['valor'] as num?;
        if (valorNum == null) continue;
        final valor = valorNum.toDouble();

        final tipo = data['tipo'] as String?;
        if (tipo == 'receita' || (tipo == null && valor > 0)) {
          receita += valor;
        } else {
          despesa += valor.abs();
        }
      }

      _totalReceita = receita;
      _totalDespesa = despesa;
    } catch (e) {
      debugPrint('Erro ao calcular totais: $e');
    }
  }

  // 📊 LEITURA DE TRANSAÇÕES (Monitorada)
  Future<void> _loadTransactions({bool reset = false}) async {
    if (_shopId == null || (!_hasMore && !reset) || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('financial_transactions')
          .where('shopId', isEqualTo: _shopId);

      // Filtro de Data (Essencial para não ler o banco todo)
      final start = _selectedMonth == null
          ? DateTime(_selectedYear, 1, 1)
          : DateTime(_selectedYear, _selectedMonth!, 1);
      final end = _selectedMonth == null
          ? DateTime(_selectedYear + 1, 1, 1)
              .subtract(const Duration(seconds: 1))
          : DateTime(_selectedYear, _selectedMonth! + 1, 0, 23, 59, 59);

      query = query
          .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('data', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('data', descending: _sortDesc);

      if (!reset && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      query = query.limit(_pageSize);

      final snap = await query.get();

      // 📊 O GRANDE LOG DE CUSTO 📊
      if (snap.metadata.isFromCache) {
        // debugPrint("💰 [LISTA] ${snap.docs.length} itens carregados do CACHE (R\$ 0,00)");
      } else {
        debugPrint(
            "💸 [LISTA] Baixando ${snap.docs.length} novos itens do SERVIDOR.");
      }

      if (reset) {
        _transactions.clear();
        _lastDocument = null;
      }

      // Filtros locais (Banco e Tipo) para não exigir índices complexos demais
      final filteredDocs = snap.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;

        if (_filterType != 'all') {
          final valor = (data['valor'] as num?)?.toDouble() ?? 0;
          if (_filterType == 'receita' && valor < 0) return false;
          if (_filterType == 'despesa' && valor >= 0) return false;
        }

        if (_filterBankNormalized != null) {
          final bancoNorm = _normalize(data['banco_origem'] as String? ?? '');
          if (!bancoNorm.contains(_filterBankNormalized!)) return false;
        }

        return true;
      }).toList();

      _transactions.addAll(filteredDocs);
      _lastDocument = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMore = snap.docs.length == _pageSize;
    } catch (e) {
      debugPrint('Erro ao carregar transações: $e');
      _showSnack('Erro ao carregar dados', isError: true);
    }

    if (mounted) setState(() => _isLoadingMore = false);
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadTransactions();
    }
  }

  Future<void> _refresh() async {
    _lastDocument = null;
    _hasMore = true;
    _transactions.clear();
    await _loadTotals();
    await _loadTransactions(reset: true);
  }

  // --- OTIMIZAÇÃO (GERAÇÃO DE RESUMOS) ---
  Future<void> _generateMonthlySummaries({bool forceForPeriod = false}) async {
    if (_shopId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otimizar Dados?'),
        content: const Text(
          'Isso lerá o histórico para gerar resumos mensais, tornando o app mais rápido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Otimizar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('financial_transactions')
          .where('shopId', isEqualTo: _shopId);

      if (forceForPeriod) {
        final start = _selectedMonth == null
            ? DateTime(_selectedYear, 1, 1)
            : DateTime(_selectedYear, _selectedMonth!, 1);
        final end = _selectedMonth == null
            ? DateTime(_selectedYear + 1, 1, 1)
                .subtract(const Duration(seconds: 1))
            : DateTime(_selectedYear, _selectedMonth! + 1, 0, 23, 59, 59);
        query = query
            .where('data', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('data', isLessThanOrEqualTo: Timestamp.fromDate(end));
      }

      final allTrans = await query.get();

      if (allTrans.docs.isEmpty) {
        _showSnack('Nenhuma transação para otimizar.');
        return;
      }

      final summaries = <String, Map<String, dynamic>>{};

      for (var doc in allTrans.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['data'] as Timestamp?;
        if (timestamp == null) continue;

        final date = timestamp.toDate();
        final valorNum = data['valor'] as num?;
        if (valorNum == null) continue;

        final valor = valorNum.toDouble();
        final type =
            data['tipo'] as String? ?? (valor < 0 ? 'despesa' : 'receita');

        final key = '$_shopId${date.year}_${date.month}';
        final keyYear = '$_shopId${date.year}_all';

        void addToSummary(String k, int? m) {
          summaries[k] ??= {
            'shopId': _shopId,
            'year': date.year,
            'month': m,
            'total_receita': 0.0,
            'total_despesa': 0.0,
            'count': 0,
          };

          if (type == 'receita' || valor > 0) {
            summaries[k]!['total_receita'] =
                (summaries[k]!['total_receita'] as double) + valor;
          } else {
            summaries[k]!['total_despesa'] =
                (summaries[k]!['total_despesa'] as double) + valor.abs();
          }
          summaries[k]!['count'] = (summaries[k]!['count'] as int) + 1;
        }

        addToSummary(key, date.month);
        addToSummary(keyYear, null);
      }

      final batch = FirebaseFirestore.instance.batch();
      summaries.forEach((key, sumData) {
        final ref = FirebaseFirestore.instance
            .collection('financial_summaries')
            .doc(key);
        batch.set(ref, {
          ...sumData,
          'saldo': (sumData['total_receita'] as double) -
              (sumData['total_despesa'] as double),
          'last_updated': FieldValue.serverTimestamp(),
        });
      });

      await batch.commit();

      _showSnack('Sucesso! ${summaries.length} períodos otimizados.');
      await _refresh();
    } catch (e) {
      _showSnack('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- IMPORTAÇÃO E UPLOAD ---

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ofx', 'xlsx', 'xls'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      final ext = file.extension?.toLowerCase();

      if (ext == 'xlsx' || ext == 'xls') {
        await _processExcelFile(file);
      } else if (ext == 'ofx') {
        await _processOFXFile(file);
      } else {
        _showSnack('Formato não suportado', isError: true);
      }
    } catch (e) {
      _showSnack('Erro ao selecionar arquivo: $e', isError: true);
    }
  }

  dynamic _getSafeValue(CellValue? val) {
    if (val == null) return null;
    if (val is TextCellValue) return val.value;
    if (val is DoubleCellValue) return val.value;
    if (val is IntCellValue) return val.value;
    if (val is DateCellValue) {
      return DateTime(val.year, val.month, val.day);
    }
    return val.toString();
  }

  Future<void> _processExcelFile(PlatformFile file) async {
    if (_shopId == null) {
      _showSnack('Erro: ID da loja não encontrado', isError: true);
      return;
    }
    setState(() => _isProcessingFile = true);
    DateTime? maxDate;

    try {
      final bytes = file.bytes;
      if (bytes == null) {
        _showSnack('Erro ao ler arquivo', isError: true);
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final filename = file.name.toLowerCase();

      String bankName = "Banco";
      if (filename.contains("ton")) {
        bankName = "Ton";
      } else if (filename.contains("nubank"))
        bankName = "Nubank";
      else if (filename.contains("inter"))
        bankName = "Banco Inter";
      else if (filename.contains("itau"))
        bankName = "Itaú";
      else if (filename.contains("bradesco")) bankName = "Bradesco";

      final ownerDisplay = "Excel";
      final pending = <Map<String, dynamic>>[];

      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;
        for (int i = 1; i < sheet.rows.length; i++) {
          final t = _parseExcelRow(sheet.rows[i]);
          if (t != null) {
            pending.add(t);
            final currentDate = t['date'] as DateTime;
            if (maxDate == null || currentDate.isAfter(maxDate)) {
              maxDate = currentDate;
            }
          }
        }
      }

      if (pending.isEmpty) {
        _showSnack('Nenhuma transação encontrada.', isError: true);
        return;
      }

      final bankId = await _ensureBankExists(bankName, ownerDisplay);
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (var t in pending) {
        final date = t['date'] as DateTime;
        final amount = t['amount'] as double;
        final desc = t['desc'] as String;
        final uid =
            '${_shopId}_${date.millisecondsSinceEpoch}_${amount}_${desc.hashCode}';

        batch.set(
          FirebaseFirestore.instance
              .collection('financial_transactions')
              .doc(uid),
          {
            'shopId': _shopId,
            'valor': amount,
            'descricao': desc,
            'data': Timestamp.fromDate(date),
            'tipo': amount < 0 ? 'despesa' : 'receita',
            'banco_origem': bankName,
            'banco_origem_normalized': _normalize(bankName),
            'titular': ownerDisplay,
            'origem': 'excel',
            'criado_em': FieldValue.serverTimestamp(),
            'uniqueId': uid,
          },
          SetOptions(merge: true),
        );
        count++;
        if (count % 450 == 0) await batch.commit();
      }

      await batch.commit();

      if (maxDate != null && bankId != null) {
        await FirebaseFirestore.instance
            .collection('bank_accounts')
            .doc(bankId)
            .update({'last_transaction_date': Timestamp.fromDate(maxDate)});
      }

      _showSnack('${pending.length} transações importadas!');
      await _generateMonthlySummaries();
      await _refresh();
    } catch (e) {
      debugPrint('Erro Excel: $e');
      _showSnack('Erro ao processar: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingFile = false);
    }
  }

  Map<String, dynamic>? _parseExcelRow(List<Data?> row) {
    DateTime? date;
    double? amount;
    String desc = '';

    for (var cell in row) {
      if (cell == null) continue;
      final val = _getSafeValue(cell.value);
      if (val == null) continue;

      if (date == null) {
        if (val is DateTime) {
          date = val;
        } else if (val is String && val.contains('/')) {
          try {
            final parts = val.split('/');
            if (parts.length == 3) {
              date = DateTime(int.parse(parts[2]), int.parse(parts[1]),
                  int.parse(parts[0]));
            }
          } catch (_) {}
        }
      }

      if (amount == null) {
        if (val is double) {
          amount = val;
        } else if (val is int)
          amount = val.toDouble();
        else if (val is String && val.contains(RegExp(r'[0-9]'))) {
          final clean = val
              .replaceAll('R\$', '')
              .replaceAll(' ', '')
              .replaceAll('.', '')
              .replaceAll(',', '.');
          amount = double.tryParse(clean);
        }
      }

      if (val is String &&
          val.length > 3 &&
          double.tryParse(val) == null &&
          !val.contains('/')) {
        desc += '$val ';
      }
    }

    if (date == null || amount == null) return null;
    return {
      'date': date,
      'amount': amount,
      'desc': desc.trim().isEmpty ? 'Sem descrição' : desc.trim()
    };
  }

  Future<void> _processOFXFile(PlatformFile file) async {
    if (_shopId == null) {
      _showSnack('Erro: ID da loja não encontrado', isError: true);
      return;
    }

    setState(() => _isProcessingFile = true);
    DateTime? maxDate;

    try {
      final bytes = file.bytes;
      if (bytes == null) {
        _showSnack('Erro ao ler arquivo', isError: true);
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      String bankName = RegExp(r'<ORG>(.*?)(?:\n|<)', caseSensitive: false)
              .firstMatch(content)
              ?.group(1)
              ?.trim() ??
          "Banco";
      if (bankName.toUpperCase().contains("NU PAGAMENTOS")) bankName = "Nubank";

      final acctId = RegExp(r'<ACCTID>(.*?)(?:\n|<)', caseSensitive: false)
              .firstMatch(content)
              ?.group(1)
              ?.trim() ??
          "Conta";
      final ownerDisplay = acctId;

      final matches = RegExp(r'<STMTTRN>(.*?)<\/STMTTRN>', dotAll: true)
          .allMatches(content);

      if (matches.isEmpty) {
        _showSnack('Nenhuma transação encontrada.', isError: true);
        return;
      }

      final bankId = await _ensureBankExists(bankName, ownerDisplay);
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (final match in matches) {
        final block = match.group(1) ?? "";
        final amount = double.tryParse(
                RegExp(r'<TRNAMT>([-0-9.]+)').firstMatch(block)?.group(1) ??
                    "0") ??
            0.0;
        final memo = RegExp(r'<MEMO>(.*?)(?:\n|<)')
                .firstMatch(block)
                ?.group(1)
                ?.trim() ??
            "S/D";
        final dateStr =
            RegExp(r'<DTPOSTED>([0-9]+)').firstMatch(block)?.group(1) ?? "";

        DateTime date = DateTime.now();
        if (dateStr.length >= 8) {
          try {
            date = DateTime(
              int.parse(dateStr.substring(0, 4)),
              int.parse(dateStr.substring(4, 6)),
              int.parse(dateStr.substring(6, 8)),
            );
          } catch (e) {
            debugPrint('Erro data OFX: $e');
          }
        }

        if (maxDate == null || date.isAfter(maxDate)) maxDate = date;
        final fitid =
            RegExp(r'<FITID>(.*?)(?:\n|<)').firstMatch(block)?.group(1) ?? "";
        final uid =
            '${_shopId}_${date.millisecondsSinceEpoch}_${amount}_${memo.hashCode}';

        batch.set(
          FirebaseFirestore.instance
              .collection('financial_transactions')
              .doc(uid),
          {
            'shopId': _shopId,
            'valor': amount,
            'descricao': memo,
            'data': Timestamp.fromDate(date),
            'tipo': amount < 0 ? 'despesa' : 'receita',
            'banco_origem': bankName,
            'banco_origem_normalized': _normalize(bankName),
            'titular': ownerDisplay,
            'fitid': fitid,
            'origem': 'ofx',
            'criado_em': FieldValue.serverTimestamp(),
            'uniqueId': uid,
          },
          SetOptions(merge: true),
        );
        count++;
        if (count % 450 == 0) await batch.commit();
      }

      await batch.commit();

      if (maxDate != null && bankId != null) {
        await FirebaseFirestore.instance
            .collection('bank_accounts')
            .doc(bankId)
            .update({'last_transaction_date': Timestamp.fromDate(maxDate)});
      }

      _showSnack('$count transações importadas!');
      await _generateMonthlySummaries();
      await _refresh();
    } catch (e) {
      _showSnack('Erro: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingFile = false);
    }
  }

  String _getBankLogoUrl(String bankName) {
    final clean = _normalize(bankName);
    if (clean.contains('inter'))
      return 'https://logo.clearbit.com/bancointer.com.br';
    if (clean.contains('nu')) return 'https://logo.clearbit.com/nubank.com.br';
    if (clean.contains('itau')) return 'https://logo.clearbit.com/itau.com.br';
    if (clean.contains('bradesco'))
      return 'https://logo.clearbit.com/bradesco.com.br';
    if (clean.contains('brasil') || clean.contains('bb'))
      return 'https://logo.clearbit.com/bb.com.br';
    if (clean.contains('santander'))
      return 'https://logo.clearbit.com/santander.com.br';
    if (clean.contains('caixa'))
      return 'https://logo.clearbit.com/caixa.gov.br';
    return 'https://logo.clearbit.com/$clean.com.br';
  }

  Future<String?> _ensureBankExists(String bankName, String owner) async {
    if (_shopId == null) return null;
    final normalized = _normalize(bankName);
    final display = '$bankName ($owner)';

    try {
      final q = await FirebaseFirestore.instance
          .collection('bank_accounts')
          .where('shopId', isEqualTo: _shopId)
          .where('bank_name', isEqualTo: display)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        final ref =
            await FirebaseFirestore.instance.collection('bank_accounts').add({
          'shopId': _shopId,
          'bank_name': display,
          'original_bank': normalized,
          'owner': owner,
          'logo_url': _getBankLogoUrl(bankName),
          'created_at': FieldValue.serverTimestamp(),
          'last_transaction_date': null,
        });
        return ref.id;
      }
      return q.docs.first.id;
    } catch (e) {
      return null;
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2)));
  }

  void _openDeleteManager() {
    if (_shopId == null) return;
    showDialog(
            context: context,
            builder: (context) => _DeleteManagerDialog(shopId: _shopId!))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryPurple)));
    }

    if (_shopId == null) {
      return Scaffold(
          body: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
            Icon(Icons.error_outline, size: 60, color: Colors.red),
            SizedBox(height: 16),
            Text('Erro ao carregar dados da loja')
          ])));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF4F6F8),
          body: RefreshIndicator(
            key: _refreshKey,
            onRefresh: _refresh,
            color: AppColors.primaryPurple,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                    padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
                    sliver: SliverToBoxAdapter(child: _buildTopBar(isMobile))),
                SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverToBoxAdapter(
                        child:
                            SizedBox(height: 80.0, child: _buildBankList()))),

                // [FASE 7] Widget de Gestão de Reembolsos Pendentes (Some sozinho se vazio)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverToBoxAdapter(
                    child: RefundManagementWidget(shopId: _shopId!),
                  ),
                ),

                SliverPadding(
                    padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
                    sliver: SliverToBoxAdapter(
                        child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.03),
                                      blurRadius: 5.0)
                                ]),
                            child: Column(children: [
                              _buildViewTabs(isMobile),
                              const Divider(height: 1.0),
                              SizedBox(
                                  height: 400.0,
                                  child: _showGraph
                                      ? _buildGraph()
                                      : _buildTransactionList())
                            ])))),
              ],
            ),
          ),
        ),
        if (_isProcessingFile)
          Container(
              color: Colors.black54,
              child: Center(
                  child:
                      Column(mainAxisSize: MainAxisSize.min, children: const [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text('Processando arquivo...',
                    style: TextStyle(color: Colors.white, fontSize: 16))
              ]))),
      ],
    );
  }

  Widget _buildTopBar(bool isMobile) {
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dropdown<int?>(_selectedMonth, [
          const DropdownMenuItem(value: null, child: Text('Todos')),
          ...List.generate(12,
              (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i])))
        ], (v) {
          setState(() => _selectedMonth = v);
          _refresh();
        }),
        const SizedBox(width: 8),
        _dropdown<int>(
            _selectedYear,
            _availableYears
                .map((y) =>
                    DropdownMenuItem(value: y, child: Text(y.toString())))
                .toList(), (v) {
          if (v != null) {
            setState(() => _selectedYear = v);
            _refresh();
          }
        }),
        const SizedBox(width: 8),
        IconButton(
            icon: const Icon(Icons.filter_alt_off, color: Colors.red, size: 20),
            onPressed: _clearFilters,
            tooltip: 'Limpar'),
        const VerticalDivider(width: 16, thickness: 1),
        IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.orange, size: 20),
            onPressed: _generateMonthlySummaries,
            tooltip: 'Otimizar'),
        IconButton(
            icon: const Icon(Icons.upload_file,
                color: AppColors.primaryPurple, size: 20),
            onPressed: _pickAndUploadFile,
            tooltip: 'Importar'),
        IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey, size: 20),
            onPressed: _openDeleteManager,
            tooltip: 'Gerenciar'),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03), blurRadius: 5)
          ]),
      child: isMobile
          ? Column(children: [
              Row(children: [
                Expanded(
                    child: _MetricCard(
                        label: 'Receitas',
                        value: _totalReceita,
                        color: Colors.green,
                        isSelected: _filterType == 'receita',
                        onTap: () => _toggleTypeFilter('receita'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _MetricCard(
                        label: 'Despesas',
                        value: _totalDespesa,
                        color: Colors.red,
                        isSelected: _filterType == 'despesa',
                        onTap: () => _toggleTypeFilter('despesa')))
              ]),
              const SizedBox(height: 12),
              const Divider(),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: actions)
            ])
          : Row(children: [
              _MetricCard(
                  label: 'Receitas',
                  value: _totalReceita,
                  color: Colors.green,
                  isSelected: _filterType == 'receita',
                  onTap: () => _toggleTypeFilter('receita')),
              const SizedBox(width: 15),
              _MetricCard(
                  label: 'Despesas',
                  value: _totalDespesa,
                  color: Colors.red,
                  isSelected: _filterType == 'despesa',
                  onTap: () => _toggleTypeFilter('despesa')),
              const Spacer(),
              actions
            ]),
    );
  }

  Widget _buildViewTabs(bool isMobile) {
    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child:
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 10, children: [
        Container(
            decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _tabBtn('📄 Lista', !_showGraph,
                  () => setState(() => _showGraph = false)),
              _tabBtn('📊 Gráfico', _showGraph,
                  () => setState(() => _showGraph = true))
            ])),
        if (!_showGraph)
          GestureDetector(
              onTap: _toggleSort,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_sortDesc ? 'Recentes' : 'Antigos',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 5),
                    Icon(_sortDesc ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 14, color: AppColors.primaryPurple)
                  ]))),
        if (_showGraph)
          Wrap(spacing: 5, children: [
            _filterBtn('Entrada', 'receita', Colors.green),
            _filterBtn('Saída', 'despesa', Colors.red),
            _filterBtn('Saldo', 'saldo', AppColors.primaryPurple)
          ]),
      ]),
    );
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: active ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? Colors.black : Colors.grey))));
  }

  Widget _filterBtn(String label, String value, Color color) {
    final sel = _graphFilter == value;
    return GestureDetector(
        onTap: () => setState(() => _graphFilter = value),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: sel ? color.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? color : Colors.grey.shade300)),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: sel ? color : Colors.grey))));
  }

  Widget _buildGraph() {
    if (_transactions.isEmpty)
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
            Icon(Icons.insights, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text('Sem dados para o gráfico')
          ]));

    final isMonth = _selectedMonth != null;
    final data = <int, double>{};
    final max = isMonth ? 31 : 12;
    for (var i = 1; i <= max; i++) {
      data[i] = 0.0;
    }

    for (var doc in _transactions) {
      final d = doc.data() as Map<String, dynamic>;
      final ts = d['data'] as Timestamp?;
      if (ts == null) continue;
      final date = ts.toDate();
      final val = (d['valor'] as num?)?.toDouble() ?? 0;
      if (_graphFilter == 'receita' && val < 0) continue;
      if (_graphFilter == 'despesa' && val > 0) continue;
      final key = isMonth ? date.day : date.month;
      data[key] =
          (data[key] ?? 0) + (_graphFilter == 'despesa' ? val.abs() : val);
    }

    final spots = data.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    if (spots.every((s) => s.y == 0))
      return const Center(child: Text('Sem movimentação'));

    final minY = spots.map((s) => s.y).reduce(math.min);
    final maxY = spots.map((s) => s.y).reduce(math.max);
    final margin = (maxY - minY).abs() * 0.1;
    final color = _graphFilter == 'receita'
        ? Colors.green
        : _graphFilter == 'despesa'
            ? Colors.red
            : AppColors.primaryPurple;

    return Padding(
        padding: const EdgeInsets.fromLTRB(10, 30, 20, 10),
        child: LineChart(LineChartData(
            minY: minY > 0 ? 0 : minY - margin,
            maxY: maxY < 0 ? 0 : maxY + margin,
            gridData: FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (isMonth && i % 3 == 0 && i <= 31)
                            return Text(i.toString(),
                                style: const TextStyle(fontSize: 9));
                          if (!isMonth && i >= 1 && i <= 12)
                            return Text(_months[i - 1],
                                style: const TextStyle(fontSize: 9));
                          return const SizedBox();
                        })),
                leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        getTitlesWidget: (v, _) => Text(
                            NumberFormat.compact(locale: 'pt_BR').format(v),
                            style: const TextStyle(fontSize: 9)))),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false))),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true, color: color.withValues(alpha: 0.1)))
            ])));
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty && !_isLoadingMore)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text('Nenhuma transação'),
        TextButton.icon(
            onPressed: _pickAndUploadFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Importar'))
      ]));
    return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _transactions.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _transactions.length)
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                        color: AppColors.primaryPurple)));
          final d = _transactions[i].data() as Map<String, dynamic>;
          final val = (d['valor'] as num?)?.toDouble() ?? 0;
          final ts = d['data'] as Timestamp?;
          if (ts == null) return const SizedBox();
          return Card(
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: ListTile(
                  dense: true,
                  leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: val >= 0
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(
                          val >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                          color: val >= 0 ? Colors.green : Colors.red,
                          size: 20)),
                  title: Text(d['descricao'] as String? ?? 'S/D',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${DateFormat('dd/MM/yy').format(ts.toDate())} • ${d['banco_origem'] ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                      NumberFormat.simpleCurrency(locale: 'pt_BR').format(val),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: val >= 0 ? Colors.green : Colors.red))));
        });
  }

  Widget _buildBankList() {
    return FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('bank_accounts')
            .where('shopId', isEqualTo: _shopId)
            .get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primaryPurple));
          if (!snap.hasData || snap.data!.docs.isEmpty)
            return Center(
                child: Text('Nenhum banco',
                    style: TextStyle(color: Colors.grey.shade600)));
          return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: snap.data!.docs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = snap.data!.docs[i].data() as Map<String, dynamic>;
                final name = d['bank_name'] as String? ?? 'Banco';
                final norm = _normalize(
                    d['original_bank'] as String? ?? name.split('(')[0]);
                final lastDate = d['last_transaction_date'] as Timestamp?;
                return _BankCard(
                    name: name,
                    logo: d['logo_url'] as String?,
                    selected: _filterBankNormalized == norm,
                    onTap: () => _toggleBankFilter(norm),
                    last: lastDate != null
                        ? DateFormat('dd/MM/yy').format(lastDate.toDate())
                        : 'S/D');
              });
        });
  }

  Widget _dropdown<T>(
      T value, List<DropdownMenuItem<T>> items, Function(T?) onChange) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 36,
        decoration: BoxDecoration(
            color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
                value: value,
                items: items,
                onChanged: onChange,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                icon: const Icon(Icons.arrow_drop_down, size: 16),
                isDense: true)));
  }
}

class _BankCard extends StatelessWidget {
  final String name;
  final String? logo;
  final bool selected;
  final VoidCallback onTap;
  final String last;
  const _BankCard(
      {required this.name,
      required this.logo,
      required this.selected,
      required this.onTap,
      required this.last});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: selected ? AppColors.primaryPurple : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? AppColors.primaryPurple
                        : Colors.grey.shade300,
                    width: selected ? 2 : 1)),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.grey.shade100,
                        backgroundImage:
                            logo != null ? NetworkImage(logo!) : null,
                        child: logo == null
                            ? const Icon(Icons.account_balance, size: 12)
                            : null),
                    const SizedBox(width: 6),
                    Text(name.split('(')[0].trim(),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : Colors.black87))
                  ]),
                  Padding(
                      padding: const EdgeInsets.only(top: 4, left: 22),
                      child: Text('Última: $last',
                          style: TextStyle(
                              fontSize: 9,
                              color: selected ? Colors.white70 : Colors.grey)))
                ])));
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  const _MetricCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.isSelected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: color.withValues(alpha: 0.3), width: 2)
                    : null),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(NumberFormat.simpleCurrency(locale: 'pt_BR').format(value),
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: color))
            ])));
  }
}

class _DeleteManagerDialog extends StatefulWidget {
  final String shopId;
  const _DeleteManagerDialog({required this.shopId});
  @override
  State<_DeleteManagerDialog> createState() => _DeleteManagerDialogState();
}

class _DeleteManagerDialogState extends State<_DeleteManagerDialog> {
  final Set<String> _sel = {};
  final Map<String, String> _names = {};
  bool _deleting = false;
  bool _loading = true;
  List<QueryDocumentSnapshot>? _banks;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bank_accounts')
          .where('shopId', isEqualTo: widget.shopId)
          .get();
      if (mounted)
        setState(() {
          _banks = snap.docs;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: const Text('Gerenciar Bancos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
            width: 300,
            height: 300,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _banks == null || _banks!.isEmpty
                    ? const Center(child: Text('Nenhum banco'))
                    : ListView.separated(
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: _banks!.length,
                        itemBuilder: (_, i) {
                          final doc = _banks![i];
                          final d = doc.data() as Map<String, dynamic>;
                          final name = d['bank_name'] as String? ?? 'Banco';
                          _names[doc.id] = name;
                          return CheckboxListTile(
                              dense: true,
                              title: Text(name,
                                  style: const TextStyle(fontSize: 13)),
                              value: _sel.contains(doc.id),
                              onChanged: (v) => setState(() {
                                    if (v!) {
                                      _sel.add(doc.id);
                                    } else {
                                      _sel.remove(doc.id);
                                    }
                                  }));
                        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _sel.isEmpty || _deleting ? null : _delete,
              child: _deleting
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Excluir'))
        ]);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Confirmar'),
                content:
                    Text('Excluir ${_sel.length} bancos e suas transações?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Não')),
                  ElevatedButton(
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sim'))
                ]));
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      String norm(String s) =>
          s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final trans = await FirebaseFirestore.instance
          .collection('financial_transactions')
          .where('shopId', isEqualTo: widget.shopId)
          .get();
      for (final id in _sel) {
        final clean = norm((_names[id] ?? '').split('(')[0]);
        for (final t in trans.docs) {
          if (norm(t.data()['banco_origem'] as String? ?? '').contains(clean))
            batch.delete(t.reference);
        }
        batch.delete(
            FirebaseFirestore.instance.collection('bank_accounts').doc(id));
      }
      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bancos excluídos'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
        setState(() => _deleting = false);
      }
    }
  }
}
