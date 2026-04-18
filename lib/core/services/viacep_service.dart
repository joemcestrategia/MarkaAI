import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ViaCepService {
  // Retorna um Mapa com os dados ou null se der erro
  static Future<Map<String, dynamic>?> buscarCep(String cep) async {
    // Remove traços e pontos
    String cepLimpo = cep.replaceAll(RegExp(r'[^0-9]'), '');

    if (cepLimpo.length != 8) return null;

    try {
      final url = Uri.parse('https://viacep.com.br/ws/$cepLimpo/json/');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);
        if (dados.containsKey('erro')) return null; // CEP inexistente
        return dados;
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Erro ao buscar CEP: $e");
    }
    return null;
  }
}
