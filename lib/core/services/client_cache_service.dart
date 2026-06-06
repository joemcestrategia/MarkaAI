import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClientCacheService {
  static const String _keyPrefix = 'cached_clients_';
  static const Duration _maxAge = Duration(minutes: 10);

  /// Salva os dados processados na cache local
  static Future<void> saveClients(
      String shopId, Map<String, List<Map<String, dynamic>>> processedData) async {
    final prefs = await SharedPreferences.getInstance();

    final serializedData = {
      'clients': _serializeList(processedData['clients'] ?? []),
      'visitors': _serializeList(processedData['visitors'] ?? []),
      'cachedAt': DateTime.now().toIso8601String(),
    };

    await prefs.setString('$_keyPrefix$shopId', jsonEncode(serializedData));
  }

  /// Recupera os dados da cache local
  static Future<Map<String, List<Map<String, dynamic>>>?> getCachedClients(
      String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_keyPrefix$shopId');

    if (jsonStr == null) return null;

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      if (cachedAt != null && DateTime.now().difference(cachedAt) > _maxAge) {
        return null;
      }
      return {
        'clients': _deserializeList(decoded['clients'] as List),
        'visitors': _deserializeList(decoded['visitors'] as List),
      };
    } catch (e) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _serializeList(List<Map<String, dynamic>> list) {
    return list.map((item) {
      final newItem = Map<String, dynamic>.from(item);
      newItem.forEach((key, value) {
        if (value is DateTime) {
          newItem[key] = {'__type__': 'DateTime', 'value': value.toIso8601String()};
        }
      });
      return newItem;
    }).toList();
  }

  static List<Map<String, dynamic>> _deserializeList(List<dynamic> list) {
    return list.map((item) {
      final newItem = Map<String, dynamic>.from(item as Map);
      newItem.forEach((key, value) {
        if (value is Map && value.containsKey('__type__')) {
          if (value['__type__'] == 'DateTime') {
            newItem[key] = DateTime.parse(value['value'] as String);
          }
        }
      });
      return newItem;
    }).toList();
  }
}
