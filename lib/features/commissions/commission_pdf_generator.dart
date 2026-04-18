import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'commission_models.dart';

class CommissionPdfGenerator {
  static Future<void> generateAndShare({
    required CommissionSummary summary,
    required int month,
    required int year,
    required String businessName,
  }) async {
    final pdf = pw.Document();

    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat("dd/MM/yyyy HH:mm", 'pt_BR');
    
    final months = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    final monthName = month >= 1 && month <= 12 ? months[month] : month.toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      businessName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      "Relatório de Comissões — $monthName $year",
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Divider(),
            pw.SizedBox(height: 16),
            
            // Professional Info & Summary
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Profissional: ${summary.professionalName}",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Total de Atendimentos: ${summary.totalAppointments}",
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        "Faturamento Bruto: ${currencyFormat.format(summary.totalRevenue)}",
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Comissão A Pagar: ${currencyFormat.format(summary.totalCommission)}",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            
            // Details Table
            pw.Text(
              "Detalhamento dos Serviços",
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headerHeight: 25,
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              },
              data: <List<String>>[
                ['Data', 'Serviço', 'Valor Bruto', 'Regra', 'Comissão'],
                ...summary.details.map((d) => [
                  dateFormat.format(d.scheduledAt),
                  d.serviceName,
                  currencyFormat.format(d.servicePrice),
                  d.commissionType == 'percentage' ? '${d.commissionValue.toStringAsFixed(1)}%' : 'Fixo',
                  currencyFormat.format(d.commissionAmount),
                ]),
              ],
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10.0),
            child: pw.Text(
              'Gerado automaticamente pelo sistema MarkaAI em ${dateFormat.format(DateTime.now())} • Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'comissoes_${summary.professionalName.replaceAll(' ', '_')}_${month}_$year.pdf',
    );
  }
}
