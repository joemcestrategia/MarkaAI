import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/services/session_service.dart';
import '../../core/services/stripe_service.dart';
import '../../core/widgets/premium_dialogs.dart';

class BoostShopPage extends StatefulWidget {
  const BoostShopPage({super.key});

  @override
  State<BoostShopPage> createState() => _BoostShopPageState();
}

class _BoostShopPageState extends State<BoostShopPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = false;
  String? shopId;
  DateTime? _currentBoostExpiration;
  int _selectedOption = 1; // 0: 24h, 1: 3 days, 2: 7 days

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    shopId = await SessionService.getShopId();
    if (shopId != null) {
      try {
        final data = await Supabase.instance.client
            .from('shops')
            .select('boost')
            .eq('id', shopId!)
            .maybeSingle();
            
        if (data != null && data['boost'] != null) {
          final boostData = data['boost'] as Map<String, dynamic>;
          final expiresAtStr = boostData['expires_at']?.toString();
          if (expiresAtStr != null) {
            final date = DateTime.tryParse(expiresAtStr);
            if (date != null && date.isAfter(DateTime.now())) {
              _currentBoostExpiration = date;
            }
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar status do impulsionamento: $e");
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

    bool success;
    try {
      success = await StripeService.instance.processOneTimePayment(
        amount: amount,
        currency: 'brl',
        description: description,
        shopId: shopId,
      );
    } catch (e) {
      debugPrint("Erro no pagamento Stripe (boost): $e");
      if (mounted) {
        PremiumDialogs.hideLoading(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erro ao processar pagamento: $e"),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

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
      await Supabase.instance.client.from('shops').update({
        'boost': {
          'expires_at': newExpiration.toIso8601String(),
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }
      }).eq('id', shopId!);

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Status Card
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                        size: 42, color: Colors.white),
                    const SizedBox(height: 12),
                    const Text("Status do Impulsionamento",
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      _currentBoostExpiration != null ? "ATIVO" : "INATIVO",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1),
                    ),
                    if (_currentBoostExpiration != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        "Expira em: ${DateFormat('dd/MM/yyyy HH:mm').format(_currentBoostExpiration!)}",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ]
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Text("Escolha seu plano de destaque",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              _buildOptionCard(0, "Destaque 24h", "R\$ 9,90",
                  "Ideal para dias de pouco movimento"),
              _buildOptionCard(1, "Destaque 3 Dias", "R\$ 14,90",
                  "Mais popular! Para períodos intensos",
                  isPopular: true),
              _buildOptionCard(2, "Destaque Semanal", "R\$ 29,90",
                  "Presença constante no topo"),

              const SizedBox(height: 8),
              const Text(
                  "O pagamento será processado via sua conta cadastrada.",
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                  textAlign: TextAlign.center),
              const SizedBox(height: 100), // Espaço para o botão fixo
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5)),
          ],
        ),
        child: ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  AppColors.gold,
                  const Color(0xFFFFD700),
                  AppColors.gold,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isLoading ? null : _purchaseBoost,
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: AppColors.primaryPurple)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.rocket_launch_rounded,
                            color: AppColors.primaryPurple, size: 20),
                        SizedBox(width: 8),
                        Text("ATIVAR DESTAQUE AGORA",
                            style: TextStyle(
                                color: AppColors.primaryPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5)),
                      ],
                    ),
            ),
          ),
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
                  child: const Text("DESTAK+",
                      style: TextStyle(
                          fontSize: 9,
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
