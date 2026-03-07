import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/services/session_service.dart';

class BoostShopPage extends StatefulWidget {
  const BoostShopPage({super.key});

  @override
  State<BoostShopPage> createState() => _BoostShopPageState();
}

class _BoostShopPageState extends State<BoostShopPage> {
  bool _isLoading = false;
  String? shopId;
  DateTime? _currentBoostExpiration;
  int _selectedOption = 1; // 0: 24h, 1: 3 days, 2: 7 days

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    shopId = await SessionService.getShopId();
    if (shopId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final ts = data?['boost_expires_at'] as Timestamp?;
        if (ts != null) {
          final date = ts.toDate();
          if (date.isAfter(DateTime.now())) {
            _currentBoostExpiration = date;
          }
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _purchaseBoost() async {
    if (shopId == null) return;
    setState(() => _isLoading = true);

    // MOCK PAYMENT
    // In a real app, this would call IAP or Stripe
    await Future.delayed(const Duration(seconds: 2));

    int daysToAdd = 0;
    switch (_selectedOption) {
      case 0:
        daysToAdd = 1;
        break;
      case 1:
        daysToAdd = 3;
        break;
      case 2:
        daysToAdd = 7;
        break;
    }

    final now = DateTime.now();
    final start = (_currentBoostExpiration != null &&
            _currentBoostExpiration!.isAfter(now))
        ? _currentBoostExpiration!
        : now;

    final newExpiration = start.add(Duration(days: daysToAdd));

    try {
      await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
        'boost_expires_at': Timestamp.fromDate(newExpiration),
        'is_boosted': true, // Helper flag
      });

      if (mounted) {
        setState(() {
          _currentBoostExpiration = newExpiration;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Impulsionamento ativado com sucesso! ðŸš€"),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context); // Optional: close after purchase
      }
    } catch (e) {
      debugPrint("Error boosting shop: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Impulsionar Negócio",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        backgroundColor: AppColors.primaryPurple,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryPurple,
                    AppColors.primaryPurple.withValues(alpha: 0.8)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primaryPurple.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.rocket_launch,
                      size: 48, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text("Status do Impulsionamento",
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(
                    _currentBoostExpiration != null ? "ATIVO" : "INATIVO",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1),
                  ),
                  if (_currentBoostExpiration != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Expira em: ${DateFormat('dd/MM/yyyy HH:mm').format(_currentBoostExpiration!)}",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ]
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Text("Escolha seu plano de destaque",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _buildOptionCard(0, "Destaque 24h", "R\$ 9,90",
                "Ideal para dias de pouco movimento"),
            _buildOptionCard(1, "Destaque 3 Dias", "R\$ 19,90",
                "Mais popular! Final de semana garantido",
                isPopular: true),
            _buildOptionCard(2, "Destaque Semanal", "R\$ 39,90",
                "Presença constante no topo"),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                ),
                onPressed: _isLoading ? null : _purchaseBoost,
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: AppColors.primaryPurple)
                    : const Text("ATIVAR DESTAQUE AGORA",
                        style: TextStyle(
                            color: AppColors.primaryPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            const Text("O pagamento será processado via sua conta cadastrada.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(
      int index, String title, String price, String subtitle,
      {bool isPopular = false}) {
    final isSelected = _selectedOption == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedOption = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primaryPurple : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Radio<int>(
                      value: index,
                      groupValue: _selectedOption,
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppColors.primaryPurple;
                        }
                        return Colors.grey;
                      }),
                      onChanged: (v) => setState(() => _selectedOption = v!)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(price,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.primaryPurple)),
                ],
              ),
            ),
            if (isPopular)
              Positioned(
                top: -10,
                right: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text("MAIS VENDIDO",
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryPurple)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
