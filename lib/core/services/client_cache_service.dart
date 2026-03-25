import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClientCacheService {
  static const String _keyPrefix = 'cached_clients_';

  /// Salva os dados processados na cache local
  static Future<void> saveClients(
      String shopId, Map<String, List<Map<String, dynamic>>> processedData) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Serializa os dados, tratando DateTimes e Timestamps
    final serializedData = {
      'app': _serializeList(processedData['app'] ?? []),
      'manual': _serializeList(processedData['manual'] ?? []),
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
      return {
        'app': _deserializeList(decoded['app'] as List),
        'manual': _deserializeList(decoded['manual'] as List),
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
