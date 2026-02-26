import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../business_profile_page.dart'; // [NEW] Rota correta

class ProfileCompletionWidget extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic>? shopData;
  final VoidCallback?
      onTap; // Manter por compatibilidade, mas usaremos navegação direta

  const ProfileCompletionWidget({
    super.key,
    required this.shopId,
    this.shopData,
    this.onTap,
  });

  @override
  State<ProfileCompletionWidget> createState() =>
      _ProfileCompletionWidgetState();
}

class _ProfileCompletionWidgetState extends State<ProfileCompletionWidget>
    with SingleTickerProviderStateMixin {
  static const _kDismissKey = 'profile_completion_dismissed_until';

  bool _dismissed = false;
  bool _loadingPrefs = true;
  late AnimationController _animController;
  late Animation<double> _progressAnimation;
  int _percentage = 0;
  List<_MissingField> _missing = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _checkDismissed();
    _compute();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────
  // Calculate completion from shopData
  // ──────────────────────────────────────────────
  void _compute() {
    if (widget.shopData == null) return;
    final d = widget.shopData!;

    final fields = <_MissingField>[];

    bool _filled(String field) {
      final v = d[field];
      if (v == null) return false;
      if (v is String) return v.trim().isNotEmpty;
      if (v is List) return (v).isNotEmpty;
      if (v is Map) return (v).isNotEmpty;
      return true;
    }

    void _check(String field, String label) {
      if (!_filled(field))
        fields.add(_MissingField(field: field, label: label));
    }

    // 9 campos do perfil da loja
    _check('nome', 'Nome da loja');
    _check('categoria', 'Categoria');
    _check('telefone', 'Telefone');
    _check('logo', 'Logo / Foto de perfil');
    if (!_filled('imageUrl') && !_filled('coverUrl') && !_filled('foto_capa')) {
      fields
          .add(const _MissingField(field: 'foto_capa', label: 'Foto de capa'));
    }
    _check('descricao', 'Descrição da loja');
    _check('cidade', 'Cidade');
    _check('estado', 'Estado');
    _check('horarios', 'Horários de funcionamento');

    const total = 9;
    final filled = total - fields.length;
    final pct = ((filled / total) * 100).round().clamp(0, 100);

    setState(() {
      _percentage = pct;
      _missing = fields;
    });

    _progressAnimation = Tween<double>(begin: 0, end: pct / 100).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _animController.forward();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kDismissKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (mounted) {
      setState(() {
        _dismissed = until != null && until > now;
        _loadingPrefs = false;
      });
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    final until =
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;
    await prefs.setInt(_kDismissKey, until);
    if (mounted) setState(() => _dismissed = true);
  }

  // ──────────────────────────────────────────────
  // Contextual message based on percentage
  // ──────────────────────────────────────────────
  String _message(int pct) {
    if (pct <= 30)
      return 'Seu perfil está incompleto. Clientes têm menos chances de encontrar sua loja.';
    if (pct <= 60)
      return 'Bom começo! Complete mais alguns dados para aumentar sua visibilidade.';
    if (pct < 90)
      return 'Quase lá! Finalize seu perfil para transmitir mais confiança.';
    return 'Perfil quase completo! Só faltam poucos detalhes.';
  }

  void _navigateToProfile() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessProfilePage(shopId: widget.shopId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) return const SizedBox.shrink();
    if (_dismissed) return const SizedBox.shrink();
    if (_percentage >= 100) return const SizedBox.shrink();
    if (widget.shopData == null) return const SizedBox.shrink();

    final visibleMissing = _missing.take(3).toList();
    final extra = _missing.length - 3;

    return Semantics(
      label: 'Perfil $_percentage% completo',
      child: GestureDetector(
        onTap: _navigateToProfile,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header row ─────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.rocket_launch,
                        color: AppColors.primaryPurple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Complete seu perfil!',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _message(_percentage),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botão fechar
                  Semantics(
                    label: 'Fechar notificação de perfil',
                    button: true,
                    child: GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ─── Animated progress bar ────────────────
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Barra de progresso: $_percentage%',
                      child: AnimatedBuilder(
                        animation: _progressAnimation,
                        builder: (_, __) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value:
                                _animController.isCompleted || _percentage == 0
                                    ? _percentage / 100
                                    : _progressAnimation.value,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.primaryPurple),
                            minHeight: 8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Percentage text
                  Text(
                    '$_percentage%',
                    style: const TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),

              // ─── Missing fields list (max 3) ──────────
              if (visibleMissing.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      ...visibleMissing.map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 14, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.label,
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (extra > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const SizedBox(width: 22),
                              Text(
                                '+ $extra ${extra == 1 ? 'campo restante' : 'campos restantes'}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ─── CTA button ───────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToProfile,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('EDITAR PERFIL'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingField {
  final String field;
  final String label;
  const _MissingField({required this.field, required this.label});
}
