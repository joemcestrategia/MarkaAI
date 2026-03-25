import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Resultado da consulta de CEP via Cloud Function proxy (fetchCep).
class CepResult {
  final String cep;
  final String logradouro;
  final String bairro;
  final String cidade;
  final String estado;

  const CepResult({
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.cidade,
    required this.estado,
  });

  factory CepResult.fromMap(Map<String, dynamic> map) {
    return CepResult(
      cep: map['cep']?.toString() ?? '',
      logradouro: map['logradouro']?.toString() ?? '',
      bairro: map['bairro']?.toString() ?? '',
      cidade: map['cidade']?.toString() ?? '',
      estado: map['estado']?.toString() ?? '',
    );
  }
}

/// Representa uma cidade disponível para seleção pelo cliente.
class CidadeDisponivel {
  final String cidade;
  final String estado;

  const CidadeDisponivel({required this.cidade, required this.estado});

  factory CidadeDisponivel.fromMap(Map<String, dynamic> map) {
    return CidadeDisponivel(
      cidade: map['cidade']?.toString() ?? '',
      estado: map['estado']?.toString() ?? '',
    );
  }

  @override
  String toString() => '$cidade, $estado';
}

class LocationService {
  static final _functions = Supabase.instance.client.functions;

  // -------------------------------------------------------------------------
  // Busca dados de um CEP via Cloud Function proxy (para o formulário da loja).
  // Retorna null e não lança exceção se o CEP não for encontrado ou rede falhar.
  // -------------------------------------------------------------------------
  static Future<CepResult?> buscarCep(String cep) async {
    final cepDigitos = cep.replaceAll(RegExp(r'\D'), '');
    if (cepDigitos.length != 8) return null;

    try {
      final result =
          await _functions.invoke('fetchCep', body: {'cep': cepDigitos});
      final data = Map<String, dynamic>.from(result.data as Map);
      return CepResult.fromMap(data);
    } on FunctionException catch (e) {
      debugPrint(
          '[LocationService] fetchCep error: ${e.reasonPhrase} — ${e.details}');
      return null;
    } catch (e) {
      debugPrint('[LocationService] fetchCep unexpected error: $e');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Lista cidades disponíveis (com lojas cadastradas) para o SeletorDeCidade.
  // Parâmetros opcionais: query (busca parcial) e estado (UF).
  // -------------------------------------------------------------------------
  static Future<List<CidadeDisponivel>> listarCidades({
    String? query,
    String? estado,
  }) async {
    try {
      final result = await _functions.invoke('getAvailableCities', body: {
        if (query != null && query.isNotEmpty) 'query': query,
        if (estado != null && estado.isNotEmpty) 'estado': estado,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final citiesRaw = data['cities'] as List? ?? [];
      return citiesRaw
          .map((c) =>
              CidadeDisponivel.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } catch (e) {
      debugPrint('[LocationService] getAvailableCities error: $e');
      return [];
    }
  }
}
