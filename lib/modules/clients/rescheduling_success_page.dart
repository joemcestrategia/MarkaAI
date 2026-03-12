import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

class RescheduleSuccessPage extends StatelessWidget {
  final String appointmentId;
  final DateTime newDate;
  final String newProfessional;
  final String newServiceName;
  final DateTime? oldDate;
  final String oldProfessional;
  final String oldServiceName;

  const RescheduleSuccessPage({
    super.key,
    required this.appointmentId,
    required this.newDate,
    required this.newProfessional,
    required this.newServiceName,
    this.oldDate,
    this.oldProfessional = '',
    this.oldServiceName = '',
  });

  String _formatDate(DateTime d) =>
      DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(d);

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Header com sucesso ──────────────────────────────────────
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryPurple, Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                child: Column(
                  children: [
                    // Círculo com check
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.event_available_rounded,
                        size: 52,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Reagendado com Sucesso!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Seu horário foi atualizado.\nConfira os detalhes abaixo.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // ── Conteúdo ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),

                      // Card: De → Para
                      if (oldDate != null) ...[
                        _buildComparisonCard(context),
                        const SizedBox(height: 16),
                      ],

                      // Card: Detalhes do Novo Horário
                      _buildNewDetailsCard(),

                      const SizedBox(height: 32),

                      // ── Botões ──────────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.of(context)
                              .pushNamedAndRemoveUntil(
                                  '/client_home', (route) => false),
                          icon: const Icon(Icons.calendar_month_rounded,
                              size: 18),
                          label: const Text(
                            "VER MEUS AGENDAMENTOS",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: BorderSide(
                                color: Colors.grey.shade300, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => Navigator.of(context)
                              .pushNamedAndRemoveUntil('/', (route) => false),
                          icon: const Icon(Icons.home_outlined, size: 18),
                          label: const Text(
                            "IR PARA O INÍCIO",
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Topo do card: título
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.compare_arrows_rounded,
                    size: 18, color: Colors.black54),
                SizedBox(width: 8),
                Text(
                  "ALTERAÇÃO REALIZADA",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // Antes
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "ANTES",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade400,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildCompRow(
                  icon: Icons.event_outlined,
                  text: _formatDate(oldDate!),
                  isOld: true,
                ),
                const SizedBox(height: 8),
                _buildCompRow(
                  icon: Icons.access_time_outlined,
                  text: _formatTime(oldDate!),
                  isOld: true,
                ),
                if (oldProfessional.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCompRow(
                    icon: Icons.person_outline_rounded,
                    text: oldProfessional,
                    isOld: true,
                  ),
                ],
                if (oldServiceName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCompRow(
                    icon: Icons.cut_rounded,
                    text: oldServiceName,
                    isOld: true,
                  ),
                ],
              ],
            ),
          ),

          // Seta divisória
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryPurple.withValues(alpha: 0.08),
                ),
                child: const Icon(Icons.arrow_downward_rounded,
                    color: AppColors.primaryPurple, size: 20),
              ),
            ),
          ),

          // Depois
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "AGORA",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildCompRow(
                  icon: Icons.event_rounded,
                  text: _formatDate(newDate),
                  isOld: false,
                ),
                const SizedBox(height: 8),
                _buildCompRow(
                  icon: Icons.access_time_rounded,
                  text: _formatTime(newDate),
                  isOld: false,
                ),
                if (newProfessional.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCompRow(
                    icon: Icons.person_rounded,
                    text: newProfessional,
                    isOld: false,
                  ),
                ],
                if (newServiceName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCompRow(
                    icon: Icons.cut_rounded,
                    text: newServiceName,
                    isOld: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompRow(
      {required IconData icon, required String text, required bool isOld}) {
    final color = isOld ? Colors.red.shade300 : AppColors.primaryPurple;
    final textColor = isOld ? Colors.black38 : Colors.black87;
    final decoration = isOld ? TextDecoration.lineThrough : TextDecoration.none;

    return Row(
      children: [
        Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: textColor,
              decoration: decoration,
              decorationColor: Colors.red.shade300,
              fontWeight: isOld ? FontWeight.normal : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.primaryPurple.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_available_rounded,
                    color: AppColors.primaryPurple, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                "NOVO HORÁRIO CONFIRMADO",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _detailRow(
              Icons.calendar_today_rounded, "Data", _formatDate(newDate)),
          const SizedBox(height: 14),
          _detailRow(
              Icons.access_time_rounded, "Horário", _formatTime(newDate)),
          if (newServiceName.isNotEmpty) ...[
            const SizedBox(height: 14),
            _detailRow(Icons.cut_rounded, "Serviço", newServiceName),
          ],
          if (newProfessional.isNotEmpty) ...[
            const SizedBox(height: 14),
            _detailRow(Icons.person_rounded, "Profissional", newProfessional),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
