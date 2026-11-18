import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ClientCacheService {
  static const String _keyPrefix = 'cached_clients_';
  static const Duration _maxAge = Duration(hours: 2);

  /// Salva os dados processados na cache local
  static Future<void> saveClients(
      String shopId, Map<String, dynamic> processedData) async {
    final prefs = await SharedPreferences.getInstance();

    final serializedData = {
      'clients': _serializeList(
          (processedData['clients'] as List?)?.cast<Map<String, dynamic>>() ??
              []),
      'visitors': _serializeList(
          (processedData['visitors'] as List?)?.cast<Map<String, dynamic>>() ??
              []),
      'cachedAt': DateTime.now().toIso8601String(),
      'fingerprint': processedData['fingerprint'] ?? '',
    };

    await prefs.setString('$_keyPrefix$shopId', jsonEncode(serializedData));
  }

  /// Recupera os dados da cache (retorna mesmo expirado - stale-while-revalidate)
  static Future<Map<String, dynamic>?> getCachedClients(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_keyPrefix$shopId');

    if (jsonStr == null) return null;

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return {
        'clients': _deserializeList(decoded['clients'] as List),
        'visitors': _deserializeList(decoded['visitors'] as List),
        'fingerprint': decoded['fingerprint']?.toString() ?? '',
      };
    } catch (e) {
      return null;
    }
  }

  /// Computa fingerprint dos appointments para detectar mudanças
  static int computeAppointmentsFingerprint(
      List<Map<String, dynamic>> appointments) {
    int hash = appointments.length;
    for (int i = 0; i < appointments.length; i++) {
      final a = appointments[i];
      hash = hash * 31 + (a['id']?.hashCode ?? 0);
      hash = hash * 31 + (a['status']?.hashCode ?? 0);
      hash = hash * 31 + (a['client_id']?.hashCode ?? 0);
      hash = hash * 31 + ((a['total_price'] ?? 0).hashCode);
    }
    return hash;
  }

  /// Computa fingerprint dos cadastros de shop_clients (clientes manuais, tags,
  /// classificação) para detectar criação, edição e exclusão em tempo real.
  static int computeShopClientsFingerprint(List<Map<String, dynamic>> rows) {
    int hash = rows.length;
    for (final r in rows) {
      hash = (hash * 31 + (r['id']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['nome']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['telefone']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['photo_url']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['classification']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['last_updated']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['manual_tags']?.toString().hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['notes']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['has_auth_account']?.hashCode ?? 0)) & 0x3fffffff;
      hash = (hash * 31 + (r['is_deleted']?.hashCode ?? 0)) & 0x3fffffff;
    }
    return hash;
  }

  /// Verifica se a cache está expirada (precisa de refresh em background)
  static Future<bool> isCacheStale(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_keyPrefix$shopId');
    if (jsonStr == null) return true;

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      if (cachedAt == null) return true;
      return DateTime.now().difference(cachedAt) > _maxAge;
    } catch (e) {
      return true;
    }
  }

  static List<Map<String, dynamic>> _serializeList(
      List<Map<String, dynamic>> list) {
    return list.map((item) {
      final newItem = Map<String, dynamic>.from(item);
      newItem.forEach((key, value) {
        if (value is DateTime) {
          newItem[key] = {
            '__type__': 'DateTime',
            'value': value.toIso8601String()
          };
        } else if (value is List) {
          newItem[key] = value.map((e) {
            if (e is DateTime) {
              return {'__type__': 'DateTime', 'value': e.toIso8601String()};
            }
            return e;
          }).toList();
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
        } else if (value is List) {
          newItem[key] = value.map((e) {
            if (e is Map && e['__type__'] == 'DateTime') {
              return DateTime.parse(e['value'] as String);
            }
            return e;
          }).toList();
        }
      });
      return newItem;
    }).toList();
  }
}
