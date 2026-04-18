import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import 'commission_models.dart';
import 'commission_repository.dart';
import 'commission_pdf_generator.dart';
import 'commission_filter_bar.dart';
import 'commission_summary_card.dart';
import 'commission_detail_bottom_sheet.dart';
import '../../core/widgets/empty_state_widget.dart';

class CommissionManagementPage extends StatefulWidget {
  final String shopId;
  final bool showAppBar;

  const CommissionManagementPage({
    super.key, 
    required this.shopId,
    this.showAppBar = true,
  });

  @override
  State<CommissionManagementPage> createState() => _CommissionManagementPageState();
}

class _CommissionManagementPageState extends State<CommissionManagementPage> {
  late CommissionRepository _repository;

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  String? _selectedEmployeeId;
  
  List<Map<String, dynamic>> _employees = [];
  List<CommissionSummary> _summaries = [];
  
  bool _isLoading = true;
  String? _errorMessage;

  double get _grandTotalCommission => _summaries.fold(0, (sum, item) => sum + item.totalCommission);
  double get _grandTotalRevenue => _summaries.fold(0, (sum, item) => sum + item.totalRevenue);
  int get _grandTotalAppointments => _summaries.fold(0, (sum, item) => sum + item.totalAppointments);
  
  @override
  void initState() {
    super.initState();
    _repository = CommissionRepository(Supabase.instance.client);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadEmployees();
    await _loadCommissions();
  }

  Future<void> _loadEmployees() async {
    try {
      final data = await Supabase.instance.client
          .from('employees')
          .select('id, name')
          .eq('shop_id', widget.shopId)
          .order('name');
      
      if (mounted) {
        setState(() {
          _employees = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar funcionários: $e");
    }
  }

  Future<void> _loadCommissions() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final detailsWithInfo = await _repository.fetchCommissions(
        shopId: widget.shopId,
        month: _selectedMonth,
        year: _selectedYear,
        employeeId: _selectedEmployeeId,
      );

      final summaries = _repository.groupByProfessional(detailsWithInfo);

      if (mounted) {
        setState(() {
          _summaries = summaries;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar comissões: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Não foi possível carregar as comissões. Tente novamente.";
        });
      }
    }
  }

  void _onFilterChanged(int month, int year, String? employeeId) {
    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
      _selectedEmployeeId = employeeId;
    });
    _loadCommissions();
  }

  void _showDetails(CommissionSummary summary) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommissionDetailBottomSheet(
        summary: summary,
        onExportPdf: () => _exportPdfForSummary(summary),
      ),
    );
  }

  Future<void> _exportPdfForSummary(CommissionSummary summary) async {
    // Busca informações da loja para o cabeçalho
    String businessName = "MarkaAI";
    try {
      final shopData = await Supabase.instance.client
          .from('shops')
          .select('name')
          .eq('id', widget.shopId)
          .maybeSingle();
      if (shopData != null && shopData['name'] != null) {
        businessName = shopData['name'];
      }
    } catch (_) {}

    await CommissionPdfGenerator.generateAndShare(
      summary: summary,
      month: _selectedMonth,
      year: _selectedYear,
      businessName: businessName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final monthName = DateFormat('MMMM', 'pt_BR').format(DateTime(2022, _selectedMonth)).toUpperCase();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: widget.showAppBar ? AppBar(
        title: const Text('Comissões'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ) : null,
      body: Column(
        children: [
          // Header Card (Total a Pagar)
          Container(
            width: double.infinity,
            color: AppColors.primaryPurple,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "TOTAL A PAGAR · $monthName $_selectedYear",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currencyFormat.format(_grandTotalCommission),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Mockado aumento
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_upward, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text(
                              "12%",
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$_grandTotalAppointments atendimentos concluídos",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Container Branco com conteúdo rolante
          Expanded(
            child: Container(
              color: Colors.white,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadCommissions,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryPurple,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text("Tentar Novamente"),
                              ),
                            ],
                          ),
                        )
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Column(
                                children: [
                                  // Filter Bar
                                  CommissionFilterBar(
                                    selectedMonth: _selectedMonth,
                                    selectedYear: _selectedYear,
                                    selectedEmployeeId: _selectedEmployeeId,
                                    employees: _employees,
                                    onFilterChanged: _onFilterChanged,
                                  ),

                                  // Totalizers Cards (3 in a row)
                                  if (_summaries.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: _buildNewTotalCard(
                                              title: "ATENDIMENTOS",
                                              value: _grandTotalAppointments.toString(),
                                              valueColor: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _buildNewTotalCard(
                                              title: "FATURAMENTO",
                                              value: currencyFormat.format(_grandTotalRevenue),
                                              valueColor: AppColors.primaryPurple,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _buildNewTotalCard(
                                              title: "COMISSÕES",
                                              value: currencyFormat.format(_grandTotalCommission),
                                              valueColor: const Color(0xFF00A86B), // Verde estilo imagem
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  
                                  if (_summaries.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "FUNCIONÁRIOS - ${_summaries.length}",
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey[500],
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          Text(
                                            "Ordenar \u2191",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.primaryPurple,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            if (_summaries.isEmpty)
                              const SliverFillRemaining(
                                child: EmptyStateWidget(
                                  icon: Icons.money_off_rounded,
                                  title: "Nenhuma comissão encontrada",
                                  message: "Não encontramos atendimentos concluídos que geram comissão para este período.",
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final summary = _summaries[index];
                                      return CommissionSummaryCard(
                                        summary: summary,
                                        grandTotalCommission: _grandTotalCommission,
                                        onViewDetails: () => _showDetails(summary),
                                        onExportPdf: () => _exportPdfForSummary(summary),
                                      );
                                    },
                                    childCount: _summaries.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewTotalCard({
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50], // Fundo bem claro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

