import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../modules/business/trial_service.dart';
import '../../modules/business/trial_activation_page.dart';

class TrialBannerWidget extends StatefulWidget {
  const TrialBannerWidget({super.key});

  @override
  State<TrialBannerWidget> createState() => _TrialBannerWidgetState();
}

class _TrialBannerWidgetState extends State<TrialBannerWidget> {
  bool _isLoading = true;
  bool _isVisible = true;
  Map<String, dynamic> _status = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await TrialService.getTrialStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
      });
    }
  }

  void _hideBanner() {
    setState(() {
      _isVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_isVisible) return const SizedBox.shrink();

    final bool canUseTrial = _status['canUseTrial'] == true;
    final bool trialActive = _status['trialActive'] == true;
    final int daysRemaining = _status['daysRemaining'] ?? 0;

    if (!canUseTrial && !trialActive) return const SizedBox.shrink();

    if (trialActive) {
      return _buildActiveTrialBanner(daysRemaining);
    } else {
      return _buildPromotionBanner();
    }
  }

  Widget _buildPromotionBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch,
                    color: AppColors.primaryPurple),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      const Text(
                        "Experimente 1 Mês Grátis!",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primaryPurple,
                        ),
                      ),
                    const SizedBox(height: 4),
                    const Text(
                      "Libere todos os recursos pagos sem usar cartão de crédito.",
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TrialActivationPage()),
                        ).then((_) => _loadStatus());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: const Text("Ativar Agora"),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: -10,
            right: -10,
            child: IconButton(
              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
              onPressed: _hideBanner,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTrialBanner(int daysRemaining) {
    bool isUrgent = daysRemaining <= 15;
    Color color = isUrgent ? Colors.orange : AppColors.primaryPurple;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isUrgent
                  ? "Seu período de teste acaba em $daysRemaining dias."
                  : "Restam $daysRemaining dias no seu período de teste gratuito.",
              style: TextStyle(
                  fontSize: 14, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
