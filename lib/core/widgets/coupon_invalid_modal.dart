import 'package:flutter/material.dart';

/// Enum para classificar o tipo de erro do cupom e personalizar a UI
enum CouponErrorType {
  notFound,              // Cupom não encontrado
  expired,               // Cupom expirou
  alreadyUsed,           // Usuário já usou este cupom
  limitReached,          // Limite global de usos atingido
  notForService,         // Cupom não válido para este serviço
  notActiveMonth,        // Cupom não válido neste mês
  inactive,              // Cupom desativado pelo lojista
  generic,               // Erro genérico / desconhecido
  onlinePaymentOnly,     // Feature C: cupom válido apenas para pagamento online
  newClientsOnly,        // Feature A: cupom válido apenas para novos clientes
  vipOnly,               // Feature A: cupom válido apenas para clientes VIP
  profileNotEligible,    // Feature A: perfil não elegível (genérico)
  classificationBlocked, // Feature B: categoria do cliente está bloqueada
}

/// Retorna o [CouponErrorType] baseado na mensagem de erro do backend
CouponErrorType parseCouponErrorType(String? message) {
  if (message == null) return CouponErrorType.generic;
  final m = message.toLowerCase();
  if (m.contains('expirou')) return CouponErrorType.expired;
  if (m.contains('já utilizou')) return CouponErrorType.alreadyUsed;
  if (m.contains('limite')) return CouponErrorType.limitReached;
  if (m.contains('serviço')) return CouponErrorType.notForService;
  if (m.contains('mês')) return CouponErrorType.notActiveMonth;
  if (m.contains('ativo')) return CouponErrorType.inactive;
  if (m.contains('inválido')) return CouponErrorType.notFound;
  if (m.contains('pagamento online') || m.contains('online')) return CouponErrorType.onlinePaymentOnly;
  if (m.contains('primeira vez')) return CouponErrorType.newClientsOnly;
  if (m.contains('vip')) return CouponErrorType.vipOnly;
  if (m.contains('elegível')) return CouponErrorType.profileNotEligible;
  if (m.contains('não está disponível') || m.contains('indisponível')) return CouponErrorType.classificationBlocked;
  return CouponErrorType.generic;
}

/// Modal animado exibido quando um cupom é inválido ou indisponível.
///
/// Uso:
/// ```dart
/// showCouponInvalidModal(
///   context: context,
///   message: result.message,
///   couponCode: 'PROMO10',
/// );
/// ```
Future<void> showCouponInvalidModal({
  required BuildContext context,
  String? message,
  String? couponCode,
  CouponErrorType? directErrorType,
}) {
  final errorType = directErrorType ?? parseCouponErrorType(message);
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => CouponInvalidModal(
      message: message ?? 'Este cupom não é válido.',
      couponCode: couponCode,
      errorType: errorType,
    ),
  );
}

class CouponInvalidModal extends StatefulWidget {
  final String message;
  final String? couponCode;
  final CouponErrorType errorType;

  const CouponInvalidModal({
    super.key,
    required this.message,
    this.couponCode,
    this.errorType = CouponErrorType.generic,
  });

  @override
  State<CouponInvalidModal> createState() => _CouponInvalidModalState();
}

class _CouponInvalidModalState extends State<CouponInvalidModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Animação de "shake" para dar sensação de rejeição
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -5.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -5.0, end: 3.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: 0.0), weight: 10),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Retorna a configuração visual do ícone e cor baseado no tipo de erro
  _ErrorConfig get _config {
    switch (widget.errorType) {
      case CouponErrorType.expired:
        return _ErrorConfig(
          icon: Icons.timer_off_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFE65100), Color(0xFFFF6F00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFFFF6F00),
          title: 'Cupom Expirado',
          tip: 'Fique de olho nas nossas promoções para não perder as próximas ofertas!',
        );
      case CouponErrorType.alreadyUsed:
        return _ErrorConfig(
          icon: Icons.check_circle_outline_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF1E88E5),
          title: 'Cupom Já Utilizado',
          tip: 'Você já aproveitou este desconto. Cada cupom pode ser usado apenas uma vez por cliente.',
        );
      case CouponErrorType.limitReached:
        return _ErrorConfig(
          icon: Icons.people_alt_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF9C27B0),
          title: 'Cupom Esgotado',
          tip: 'Este cupom chegou ao limite de usos. Confira outros cupons disponíveis!',
        );
      case CouponErrorType.notForService:
        return _ErrorConfig(
          icon: Icons.block_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF37474F), Color(0xFF607D8B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF607D8B),
          title: 'Serviço Não Incluso',
          tip: 'Este cupom é válido apenas para serviços específicos. Verifique as condições.',
        );
      case CouponErrorType.notActiveMonth:
        return _ErrorConfig(
          icon: Icons.calendar_month_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF00796B), Color(0xFF26A69A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF26A69A),
          title: 'Fora do Período',
          tip: 'Este cupom é válido apenas em um mês específico. Tente novamente quando for a hora certa!',
        );
      case CouponErrorType.inactive:
        return _ErrorConfig(
          icon: Icons.pause_circle_outline_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF424242), Color(0xFF616161)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF616161),
          title: 'Cupom Desativado',
          tip: 'O lojista pausou este cupom temporariamente. Entre em contato para mais informações.',
        );
      case CouponErrorType.onlinePaymentOnly:
        return _ErrorConfig(
          icon: Icons.payment_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF42A5F5),
          title: 'Pagamento online necessário',
          tip: 'Selecione Pix ou cartão para utilizar este cupom.',
        );
      case CouponErrorType.newClientsOnly:
        return _ErrorConfig(
          icon: Icons.person_add_alt_1_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF66BB6A),
          title: 'Cupom para novos clientes',
          tip: 'Este cupom é válido apenas para quem está agendando pela primeira vez neste salão.',
        );
      case CouponErrorType.vipOnly:
        return _ErrorConfig(
          icon: Icons.stars_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFE65100), Color(0xFFFFB300)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFFFFB300),
          title: 'Cupom exclusivo VIP',
          tip: 'Este cupom é válido apenas para clientes VIP do salão.',
        );
      case CouponErrorType.profileNotEligible:
        return _ErrorConfig(
          icon: Icons.person_off_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF7B1FA2),
          title: 'Perfil não elegível',
          tip: 'Seu perfil de cliente não está elegível para utilizar este cupom.',
        );
      case CouponErrorType.classificationBlocked:
        return _ErrorConfig(
          icon: Icons.block_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFF37474F), Color(0xFF78909C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFF78909C),
          title: 'Cupom indisponível',
          tip: 'Este cupom não está disponível para o seu perfil de cliente.',
        );
      case CouponErrorType.notFound:
      case CouponErrorType.generic:
        return _ErrorConfig(
          icon: Icons.local_offer_rounded,
          gradient: const LinearGradient(
            colors: [Color(0xFFC62828), Color(0xFFE53935)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          accentColor: const Color(0xFFE53935),
          title: 'Cupom Inválido',
          tip: 'Verifique se o código foi digitado corretamente e tente novamente.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: child,
              ),
            );
          },
          child: _buildContent(config),
        ),
      ),
    );
  }

  Widget _buildContent(_ErrorConfig config) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: config.accentColor.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header com gradiente e ícone
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              gradient: config.gradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                // Ícone principal com halo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    config.icon,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  config.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                if (widget.couponCode != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      widget.couponCode!.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Corpo do modal
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              children: [
                // Mensagem principal
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 16),

                // Dica contextual
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: config.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: config.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        color: config.accentColor,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          config.tip,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Botão de fechar
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: config.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'ENTENDI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Configuração visual para cada tipo de erro
class _ErrorConfig {
  final IconData icon;
  final LinearGradient gradient;
  final Color accentColor;
  final String title;
  final String tip;

  const _ErrorConfig({
    required this.icon,
    required this.gradient,
    required this.accentColor,
    required this.title,
    required this.tip,
  });
}
