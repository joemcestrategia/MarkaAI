import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../modules/business/subscription_service.dart';

/// Widget que bloqueia visualmente um filho quando o plano atual não permite a feature.
///
/// Uso:
/// ```dart
/// PlanGateWidget(
///   feature: 'creditCard',
///   requiredPlan: SubscriptionPlan.flex,
///   child: MyCreditCardSection(),
/// )
/// ```
class PlanGateWidget extends StatefulWidget {
  final Widget child;
  final SubscriptionPlan requiredPlan;
  final String featureLabel;
  final VoidCallback? onUpgradeTap;

  const PlanGateWidget({
    super.key,
    required this.child,
    required this.requiredPlan,
    required this.featureLabel,
    this.onUpgradeTap,
  });

  @override
  State<PlanGateWidget> createState() => _PlanGateWidgetState();
}

class _PlanGateWidgetState extends State<PlanGateWidget> {
  bool _hasAccess = true;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final plan = await SubscriptionService.getCurrentPlan();
    final access = plan.index >= widget.requiredPlan.index;
    if (mounted) {
      setState(() {
        _hasAccess = access;
        _checked = true;
      });
    }
  }

  String _planName(SubscriptionPlan p) {
    switch (p) {
      case SubscriptionPlan.start:
        return 'Start';
      case SubscriptionPlan.plus:
        return 'Plus';
      case SubscriptionPlan.pro:
        return 'Pro';
      default:
        return 'Pago';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return widget.child;
    if (_hasAccess) return widget.child;

    return Stack(
      children: [
        // Conteúdo bloqueado â€” visual desfocado
        IgnorePointer(
          child: Opacity(
            opacity: 0.35,
            child: widget.child,
          ),
        ),
        // Overlay de cadeado
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onUpgradeTap,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: AppColors.primaryPurple,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.featureLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Disponível no Plano ${_planName(widget.requiredPlan)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.onUpgradeTap != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.onUpgradeTap,
                        child: const Text(
                          'Ver Planos →',
                          style: TextStyle(
                            color: AppColors.primaryPurple,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner compacto de upgrade — exibir no topo de páginas/seções bloqueadas
class PlanUpgradeBanner extends StatelessWidget {
  final String currentPlanName;
  final String featureDescription;
  final VoidCallback? onUpgradeTap;

  const PlanUpgradeBanner({
    super.key,
    required this.currentPlanName,
    required this.featureDescription,
    this.onUpgradeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD93D).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF856404)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Seu plano atual ($currentPlanName) não inclui $featureDescription.',
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF533F03),
                  fontWeight: FontWeight.w500),
            ),
          ),
          if (onUpgradeTap != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onUpgradeTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Upgrade →',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}
