import 'package:intl/intl.dart';

class FormatUtils {
  static String formatMoney(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  static String formatPercent(double value) {
    return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
  }
  
  static String formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}
