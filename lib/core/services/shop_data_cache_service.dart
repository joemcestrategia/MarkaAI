import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Singleton ShopDataCacheService
/// Reduz drasticamente as leituras do Supabase para dados estáticos/lentos.
class ShopDataCacheService {
  static final ShopDataCacheService _instance = ShopDataCacheService._internal();
  factory ShopDataCacheService() => _instance;
  ShopDataCacheService._internal();

  static Future<void> init() async {
    await _instance.ensureLoaded();
  }

  Future<void>? _loadFuture;

  /// Garante que o cache persistido no disco foi carregado para a memória
  /// (evita corrida com o init disparado no postFrameCallback do main).
  Future<void> ensureLoaded() {
    return _loadFuture ??= loadFromPersistent();
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
    
    // Removido o bloqueio por expiresAt para garantir acesso offline infinito.
    // O cache será atualizado silenciosamente assim que o app voltar a ficar online.
    
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
        // Removida restrição de expiração para garantir persistência offline
        _cache[key] = entry;
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
      final nameA = (a['name'] ?? a['nome'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? b['nome'] ?? '').toString().toLowerCase();
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

  Future<List<Map<String, dynamic>>> getCoupons(String shopId) async {
    final key = 'coupons_$shopId';
    final cached = getCached(key);
    if (cached != null) return List<Map<String, dynamic>>.from(cached['list']);

    final data = await Supabase.instance.client
        .from('coupons')
        .select()
        .eq('shop_id', shopId);

    setCache(key, {'list': data}, ttlServices); // Usa mesmo TTL de serviços
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> getShopsByCity(String city) async {
    final key = 'shops_city_$city';
    final cached = getCached(key);
    if (cached != null) return List<Map<String, dynamic>>.from(cached['list']);

    // Remove espaços das bordas para maior precisão
    final cleanCity = city.trim();
    // Remove acentos para garantir que encontramos tanto Cidades com acento quanto sem
    final normCity = cleanCity.replaceAll(RegExp(r'[ÀÁÂÃÄÅàáâãäå]'), 'a')
                         .replaceAll(RegExp(r'[ÈÉÊËèéêë]'), 'e')
                         .replaceAll(RegExp(r'[ÌÍÎÏìíîï]'), 'i')
                         .replaceAll(RegExp(r'[ÒÓÔÕÖØòóôõöø]'), 'o')
                         .replaceAll(RegExp(r'[ÙÚÛÜùúûü]'), 'u')
                         .replaceAll(RegExp(r'[Çç]'), 'c')
                         .replaceAll(RegExp(r'[Ññ]'), 'n');

    final normCityEscaped = normCity.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final cleanCityEscaped = cleanCity.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    final data = await Supabase.instance.client
        .from('shops')
        .select()
        .gt('services_count', 0)
        .or('city.ilike.%$cleanCityEscaped%,city.ilike.%$normCityEscaped%');

    setCache(key, {'list': data}, ttlConfig); // Usa TTL de config (30 min)
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> getShop(String shopId) async {
    await ensureLoaded();
    final key = 'shop_$shopId';
    final cached = getCached(key);
    if (cached != null) return Map<String, dynamic>.from(cached);

    try {
      final data = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', shopId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (data != null) {
        setCache(key, data, ttlConfig);
      }
      return data;
    } catch (_) {
      // Offline e sem cache: retorna null sem quebrar a UI
      return null;
    }
  }

  /// Salva os dados da loja (último estado conhecido) para uso offline.
  /// Só grava no disco se houve mudança real, evitando escrita a cada rebuild.
  void saveShop(String shopId, Map<String, dynamic> data) {
    _saveIfChanged('shop_$shopId', data);
  }

  /// Salva o perfil do usuário (último estado conhecido) para uso offline.
  void saveUser(String userId, Map<String, dynamic> data) {
    _saveIfChanged('user_$userId', data);
  }

  Future<Map<String, dynamic>?> getCachedUser(String userId) async {
    await ensureLoaded();
    final cached = getCached('user_$userId');
    return cached != null ? Map<String, dynamic>.from(cached) : null;
  }

  /// Busca uma lista online; se der certo, salva como último estado conhecido.
  /// Se falhar (offline/timeout), devolve a última versão salva no aparelho.
  /// Listas muito grandes não são persistidas para não pesar o armazenamento.
  Future<List<Map<String, dynamic>>> fetchListOffline(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetcher, {
    int maxItemsToCache = 3000,
  }) async {
    try {
      final data = await fetcher().timeout(const Duration(seconds: 12));
      if (data.length <= maxItemsToCache) {
        _saveIfChanged(key, {'list': data});
      }
      return data;
    } catch (e) {
      await ensureLoaded();
      final cached = getCached(key);
      if (cached != null && cached['list'] is List) {
        return (cached['list'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    }
  }

  void _saveIfChanged(String key, Map<String, dynamic> data) {
    try {
      final current = _cache[key];
      if (current is Map && jsonEncode(current['data']) == jsonEncode(data)) {
        return;
      }
      setCache(key, Map<String, dynamic>.from(data), ttlConfig);
    } catch (_) {
      // Dados não serializáveis: ignora silenciosamente
    }
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
