import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class BrasilApiService {
  static const String _baseUrl = 'https://brasilapi.com.br/api';

  static Future<List<dynamic>> getHolidays(int year) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/feriados/v1/$year'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        debugPrint('Erro ao buscar feriados da BrasilAPI: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('Exceção ao buscar feriados da BrasilAPI: $e');
      return [];
    }
  }
}
