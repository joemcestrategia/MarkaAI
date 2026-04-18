import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import 'commission_models.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CommissionSummaryCard extends StatelessWidget {
  final CommissionSummary summary;
  final double grandTotalCommission;
  final VoidCallback onViewDetails;
  final VoidCallback onExportPdf;

  const CommissionSummaryCard({
    super.key,
    required this.summary,
    required this.grandTotalCommission,
    required this.onViewDetails,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Gera uma cor baseada no ID do profissional para dar o destaque na moldura
    final List<Color> accentColors = [
      AppColors.primaryPurple,
      const Color(0xFF2196F3), // Blue
      const Color(0xFF00A86B), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFFE91E63), // Pink
      const Color(0xFF00BCD4), // Cyan
    ];
    final Color cardAccentColor = accentColors[summary.professionalId.hashCode % accentColors.length];

    // Calcula a porcentagem do total (cuidado com divisão por zero)
    double percentageOfTotal = 0;
    if (grandTotalCommission > 0) {
      percentageOfTotal = (summary.totalCommission / grandTotalCommission) * 100;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cardAccentColor.withValues(alpha: 0.3), width: 1.5),
      ),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cardAccentColor.withValues(alpha: 0.02),
              Colors.white,
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Top Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cardAccentColor.withValues(alpha: 0.5), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: cardAccentColor.withValues(alpha: 0.1),
                    backgroundImage: summary.professionalAvatar != null
                        ? CachedNetworkImageProvider(summary.professionalAvatar!)
                        : null,
                    child: summary.professionalAvatar == null
                        ? Text(
                            summary.professionalName.isNotEmpty
                                ? summary.professionalName.substring(0, 2).toUpperCase()
                                : 'P',
                            style: TextStyle(
                              color: cardAccentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.professionalName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.event_available, size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Text(
                            "${summary.totalAppointments} atendimentos",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currencyFormat.format(summary.totalCommission),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cardAccentColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "TOTAL COMISSÃO",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[400],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Bottom Row Actions
            Row(
              children: [
                // Porcentagem Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${percentageOfTotal.toStringAsFixed(1)}% do\ntotal",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.primaryPurple.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A86B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${summary.employeeCommissionPercent.toStringAsFixed(0)}%", 
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00A86B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: onViewDetails,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                  child: const Text("Detalhes"),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onExportPdf,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey[300]!),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("PDF", style: TextStyle(fontSize: 13, height: 1.2)),
                      Icon(Icons.arrow_downward, size: 10),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
