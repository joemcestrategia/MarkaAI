import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleCacheService {
  static const String _keyPrefix = 'schedule_cache_';
  static const Duration _maxAge = Duration(minutes: 10);

  static Future<void> saveAppointments(
      String shopId, List<Map<String, dynamic>> appointments) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = appointments.map((a) {
      final copy = Map<String, dynamic>.from(a);
      copy.forEach((key, value) {
        if (value is DateTime) {
          copy[key] = value.toIso8601String();
        }
      });
      return copy;
    }).toList();
    final data = {
      'appointments': serialized,
      'cachedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString('$_keyPrefix$shopId', jsonEncode(data));
  }

  static Future<List<Map<String, dynamic>>?> getCachedAppointments(
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
      final list = decoded['appointments'] as List;
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        map.forEach((key, value) {
          if (value is String) {
            final parsed = DateTime.tryParse(value);
            if (parsed != null) map[key] = parsed;
          }
        });
        return map;
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCache(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$shopId');
  }
}
