import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton ShopDataCacheService
/// Reduz drasticamente as leituras do Supabase para dados estáticos/lentos.
class ShopDataCacheService {
  static final ShopDataCacheService _instance = ShopDataCacheService._internal();
  factory ShopDataCacheService() => _instance;
  ShopDataCacheService._internal() {
    loadFromPersistent();
  }

  final Map<String, dynamic> _cache = {};
  
  // TTLs em minutos
  static const int ttlServices = 10;
  static const int ttlEmployees = 10;
  static const int ttlConfig = 30;

  /// Retorna dados do cache se válidos
  Map<String, dynamic>? getCached(String key) {
    if (!_cache.containsKey(key)) return null;
    
    final entry = _cache[key] as Map<String, dynamic>;
    final expiresAt = entry['expiresAt'] as int;
    
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      _cache.remove(key);
      _saveToPersistent();
      return null;
    }
    
    return entry['data'] as Map<String, dynamic>;
  }

  /// Salva dados no cache com TTL
  void setCache(String key, dynamic data, int ttlMinutes) {
    final expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes)).millisecondsSinceEpoch;
    _cache[key] = {
      'data': data,
      'expiresAt': expiresAt,
    };
    _saveToPersistent();
  }

  // --- PERSISTÊNCIA ---

  Future<void> _saveToPersistent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shop_data_cache', jsonEncode(_cache));
    } catch (e) {
      // Ignora erro de persistência
    }
  }

  Future<void> loadFromPersistent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('shop_data_cache');
      if (jsonStr == null) return;

      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final now = DateTime.now().millisecondsSinceEpoch;

      decoded.forEach((key, value) {
        final entry = value as Map<String, dynamic>;
        if (entry['expiresAt'] > now) {
          _cache[key] = entry;
        }
      });
    } catch (e) {
      _cache.clear();
    }
  }

  // --- MÉTODOS DE ACESSO ---

  Future<List<Map<String, dynamic>>> getServices(String shopId) async {
    final key = 'services_$shopId';
    final cached = getCached(key);
    if (cached != null) return List<Map<String, dynamic>>.from(cached['list']);

    final data = await Supabase.instance.client
        .from('services')
        .select()
        .eq('shop_id', shopId);

    // Filtragem local: trata null como ativo (dados migrados) + ordenação alfabética
    final filtered = List<Map<String, dynamic>>.from(data)
        .where((s) => s['is_active'] == null || s['is_active'] == true)
        .toList();

    filtered.sort((a, b) {
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    setCache(key, {'list': filtered}, ttlServices);
    return filtered;
  }

  Future<List<Map<String, dynamic>>> getEmployees(String shopId) async {
    final key = 'employees_$shopId';
    final cached = getCached(key);
    if (cached != null) return List<Map<String, dynamic>>.from(cached['list']);

    final data = await Supabase.instance.client
        .from('employees')
        .select()
        .eq('shop_id', shopId)
        .eq('is_active', true);

    setCache(key, {'list': data}, ttlEmployees);
    return List<Map<String, dynamic>>.from(data);
  }

  // --- CONTROLE ---

  void invalidate(String shopId, String entity) {
    _cache.remove('${entity}_$shopId');
    _saveToPersistent();
  }

  void invalidateAll(String? shopId) {
    if (shopId != null) {
      final prefixes = [
        'services_$shopId',
        'employees_$shopId',
        'config_$shopId',
        'coupons_$shopId',
        'categories_$shopId'
      ];
      _cache.removeWhere((key, _) => prefixes.any((p) => key.startsWith(p)));
    } else {
      _cache.clear();
    }
    _saveToPersistent();
  }
}
