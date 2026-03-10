import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/services/session_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/widgets/premium_dialogs.dart';

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

    int daysToAdd = 0;
    double amount = 0;
    String description = "";

    switch (_selectedOption) {
      case 0:
        daysToAdd = 1;
        amount = 9.90;
        description = "Impulsionamento 24h - MarkaAI";
        break;
      case 1:
        daysToAdd = 3;
        amount = 14.90;
        description = "Impulsionamento 3 Dias - MarkaAI";
        break;
      case 2:
        daysToAdd = 7;
        amount = 29.90;
        description = "Impulsionamento Semanal - MarkaAI";
        break;
    }

    final confirm = await PremiumDialogs.showConfirmation(
      context: context,
      title: "Pronto para decolar?",
      message: "Seu negócio ganhará destaque total com o $description.\n\n"
          "Confirmar investimento de R\$ ${amount.toStringAsFixed(2).replaceAll('.', ',')}?",
      confirmLabel: "Ativar Destaque!",
      icon: Icons.rocket_launch_rounded,
    );

    if (confirm != true || !mounted) return;

    PremiumDialogs.showLoading(context, "Turbinando seu perfil...");

    final success = await StripeService.instance.processOneTimePayment(
      amount: amount,
      currency: 'brl',
      description: description,
    );

    if (!success) {
      if (mounted) PremiumDialogs.hideLoading(context);
      return;
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
        'is_boosted': true,
      });

      if (mounted) {
        PremiumDialogs.hideLoading(context);
        setState(() {
          _currentBoostExpiration = newExpiration;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Sensacional! Seu perfil agora está no topo. 🚀"),
          backgroundColor: AppColors.successGreen,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Error boosting shop: $e");
      if (mounted) PremiumDialogs.hideLoading(context);
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
            _buildOptionCard(1, "Destaque 3 Dias", "R\$ 14,90",
                "Mais popular! Para períodos intensos",
                isPopular: true),
            _buildOptionCard(2, "Destaque Semanal", "R\$ 29,90",
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
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedOption = v);
                    },
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primaryPurple;
                      }
                      return Colors.grey;
                    }),
                  ),
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
