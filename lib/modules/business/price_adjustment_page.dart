import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class PriceAdjustmentPage extends StatefulWidget {
  const PriceAdjustmentPage({super.key});

  @override
  State<PriceAdjustmentPage> createState() => _PriceAdjustmentPageState();
}

class _PriceAdjustmentPageState extends State<PriceAdjustmentPage> {
  bool _isLoading = false;
  String? shopId;

  double _percentage = 0.0;
  int _roundingStep = 0; // 0: None, 5: Round to 5, 10: Round to 10
  DateTime _effectiveDate = DateTime.now();

  Map<String, dynamic>? _lastAdjustment;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    shopId = await SessionService.getShopId();
    if (shopId != null) {
      final historyDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('price_adjustment_history')
          .orderBy('appliedAt', descending: true)
          .limit(1)
          .get();
      if (historyDoc.docs.isNotEmpty) {
        _lastAdjustment = historyDoc.docs.first.data();
      }
    }
    setState(() => _isLoading = false);
  }

  double _calculateNewPrice(double oldPrice) {
    double newPrice = oldPrice * (1 + _percentage / 100);
    if (_roundingStep > 0) {
      newPrice = (newPrice / _roundingStep).ceil() * _roundingStep.toDouble();
    }
    return newPrice;
  }

  Future<void> _showSimulationDialog() async {
    if (shopId == null) return;

    setState(() => _isLoading = true);

    try {
      final servicesSnap = await FirebaseFirestore.instance
          .collection('services')
          .where('shopId', isEqualTo: shopId)
          .get();

      if (servicesSnap.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Nenhum serviço encontrado para reajustar.")),
          );
        }
        return;
      }

      final simulationData = servicesSnap.docs.map((doc) {
        final data = doc.data();
        double oldPrice =
            double.tryParse(data['preco']?.toString() ?? "0") ?? 0.0;
        double newPrice = _calculateNewPrice(oldPrice);
        return {
          'nome': data['nome'] ?? 'Serviço sem nome',
          'old': oldPrice,
          'new': newPrice,
        };
      }).toList();

      if (mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Simulação de Reajuste"),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Confira como ficarão seus preços (${_percentage.toStringAsFixed(1)}%):",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: simulationData.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = simulationData[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(item['nome'].toString(),
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              Row(
                                children: [
                                  Text("R\$ ${item['old']}",
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          decoration:
                                              TextDecoration.lineThrough,
                                          fontSize: 12)),
                                  const Icon(Icons.arrow_right_alt,
                                      size: 16, color: Colors.grey),
                                  Text("R\$ ${item['new']}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryPurple)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Obs: Arredondamento para ${_roundingStep == 0 ? 'nenhum' : _roundingStep.toString()}.",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    "Início: ${_effectiveDate.month}/${_effectiveDate.year}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("CANCELAR")),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple),
                child: const Text("CONFIRMAR E APLICAR",
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _applyAdjustment();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro na simulação: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyAdjustment() async {
    if (shopId == null) return;

    setState(() => _isLoading = true);

    try {
      final servicesSnap = await FirebaseFirestore.instance
          .collection('services')
          .where('shopId', isEqualTo: shopId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final Map<String, double> oldPrices = {};
      final Map<String, double> newPrices = {};

      for (var doc in servicesSnap.docs) {
        double oldPrice =
            double.tryParse(doc.data()['preco']?.toString() ?? "0") ?? 0.0;
        double newPrice = _calculateNewPrice(oldPrice);

        oldPrices[doc.id] = oldPrice;
        newPrices[doc.id] = newPrice;

        batch.update(doc.reference, {'preco': newPrice});
      }

      // Save History
      final historyRef = FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('price_adjustment_history')
          .doc();

      batch.set(historyRef, {
        'id': historyRef.id,
        'percentage': _percentage,
        'rounding': _roundingStep,
        'effectiveDate': Timestamp.fromDate(_effectiveDate),
        'appliedAt': FieldValue.serverTimestamp(),
        'oldPrices': oldPrices,
        'newPrices': newPrices,
      });

      await batch.commit();

      // Update future appointments (unpaid and "No Local")
      await _updateFutureAppointments(newPrices);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Reajuste aplicado com sucesso!"),
              backgroundColor: Colors.green),
        );
        _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erro ao aplicar reajuste: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateFutureAppointments(
      Map<String, double> serviceNewPrices) async {
    final startOfEffectiveMonth =
        DateTime(_effectiveDate.year, _effectiveDate.month, 1);

    final appointmentsSnap = await FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId)
        .where('data_agendamento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfEffectiveMonth))
        .where('metodo_pagamento', isEqualTo: 'No Local')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (var doc in appointmentsSnap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '').toString().toLowerCase();
      // Only update if not already paid/concluded
      if (status != 'concluido' && data['pagamento_confirmado'] != true) {
        final serviceId = data['servicoId'];
        if (serviceId != null && serviceNewPrices.containsKey(serviceId)) {
          batch.update(doc.reference, {
            'valor': serviceNewPrices[serviceId],
            'valor_total': serviceNewPrices[serviceId],
            'reajustado': true,
          });
          count++;
        }
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  Future<void> _undoLastAdjustment() async {
    if (shopId == null || _lastAdjustment == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Desfazer Último Reajuste"),
        content: const Text(
            "Deseja reverter os preços para os valores anteriores ao último reajuste?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Não")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Sim, Desfazer",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final oldPrices =
          Map<String, dynamic>.from(_lastAdjustment!['oldPrices']);
      final batch = FirebaseFirestore.instance.batch();

      for (var entry in oldPrices.entries) {
        final serviceRef =
            FirebaseFirestore.instance.collection('services').doc(entry.key);
        batch.update(serviceRef, {'preco': entry.value});
      }

      // We should also revert appointments if possible, but it's complex since we don't know if they were already reajusted by another logic.
      // For now, let's focus on services and remove the history entry.
      final historyRef = FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('price_adjustment_history')
          .doc(_lastAdjustment!['id']);

      batch.delete(historyRef);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Reajuste desfeito!"),
              backgroundColor: Colors.blue),
        );
        _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erro ao desfazer reajuste: $e"),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reajuste de Valores"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildPercentageSlider(),
                  const SizedBox(height: 32),
                  _buildRoundingOptions(),
                  const SizedBox(height: 32),
                  _buildEffectiveMonthPicker(),
                  const SizedBox(height: 48),
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Configurar Reajuste Anual",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "Ajuste todos os preços da sua loja de forma rápida. O sistema calculará os novos valores e aplicará aos serviços e agendamentos futuros.",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildPercentageSlider() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Porcentagem de Reajuste",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                "${_percentage > 0 ? '+' : ''}${_percentage.toStringAsFixed(1)}%",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _percentage >= 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Slider(
            value: _percentage,
            min: -50,
            max: 50,
            divisions: 100,
            activeColor: AppColors.primaryPurple,
            onChanged: (v) => setState(() => _percentage = v),
          ),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("-50%", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("0%", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text("+50%", style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundingOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Arredondamento",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildRoundingChip("Não arredondar", 0),
            const SizedBox(width: 12),
            _buildRoundingChip("Para 5", 5),
            const SizedBox(width: 12),
            _buildRoundingChip("Para 10", 10),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          "Evite valores quebrados (ex: R\$ 22,50 vira R\$ 25,00)",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildRoundingChip(String label, int step) {
    bool isSelected = _roundingStep == step;
    return GestureDetector(
      onTap: () => setState(() => _roundingStep = step),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEffectiveMonthPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Aplicar a partir de:",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: _effectiveDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              helpText: "Selecione o mês de início",
            );
            if (picked != null) {
              setState(
                  () => _effectiveDate = DateTime(picked.year, picked.month));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_month,
                    color: AppColors.primaryPurple),
                const SizedBox(width: 12),
                Text(
                  "${_effectiveDate.month.toString().padLeft(2, '0')}/${_effectiveDate.year}",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Icon(Icons.edit, size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _percentage == 0 ? null : _showSimulationDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: const Text("APLICAR REAJUSTE AGORA",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
        ),
        if (_lastAdjustment != null) ...[
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _undoLastAdjustment,
            icon: const Icon(Icons.undo, color: Colors.red),
            label: const Text("Desfazer último reajuste",
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ],
    );
  }
}
