import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  static SharedPreferences? _prefs;

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static const String _keyUserId = 'ss_userId';
  static const String _keyShopId = 'ss_shopId';
  static const String _keyUserType = 'ss_userType';

  // Salva os dados do login em armazenamento criptografado
  static Future<void> saveLogin({
    required String userId,
    required String userType,
    String? shopId,
  }) async {
    await _secureStorage.write(key: _keyUserId, value: userId);
    await _secureStorage.write(key: _keyUserType, value: userType);

    if (shopId != null && shopId.isNotEmpty) {
      await _secureStorage.write(key: _keyShopId, value: shopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId salvo no login');
      }
    } else {
      await _secureStorage.delete(key: _keyShopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId removido no login (null ou vazio)');
      }
    }
  }

  static Future<void> saveShopId(String shopId) async {
    if (shopId.isEmpty) {
      await _secureStorage.delete(key: _keyShopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId removido (vazio)');
      }
    } else {
      await _secureStorage.write(key: _keyShopId, value: shopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId salvo via saveShopId');
      }
    }
  }

  static Future<String?> getShopId() async {
    final shopId = await _secureStorage.read(key: _keyShopId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getShopId chamado - retornando: ${shopId != null ? "[presente]" : "NULL"}');
    }
    return shopId;
  }

  // Last selected location (address + lat + lng)
  static const String _keyLastAddress = 'last_address';
  static const String _keyLastLat = 'last_lat';
  static const String _keyLastLng = 'last_lng';

  static Future<void> saveLastLocation(
      {required String address, double? lat, double? lng}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_keyLastAddress, address);
    if (lat != null) await prefs.setDouble(_keyLastLat, lat);
    if (lng != null) await prefs.setDouble(_keyLastLng, lng);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: last location salvo: $address ($lat,$lng)');
    }
  }

  static Future<Map<String, dynamic>?> getLastLocation() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final address = prefs.getString(_keyLastAddress);
    if (address == null) return null;
    final lat =
        prefs.containsKey(_keyLastLat) ? prefs.getDouble(_keyLastLat) : null;
    final lng =
        prefs.containsKey(_keyLastLng) ? prefs.getDouble(_keyLastLng) : null;
    return {'address': address, 'lat': lat, 'lng': lng};
  }

  static Future<String?> getUserId() async {
    final userId = await _secureStorage.read(key: _keyUserId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getUserId chamado - retornando: ${userId != null ? "[presente]" : "NULL"}');
    }
    return userId;
  }

  static Future<String?> getUserType() async {
    final userType = await _secureStorage.read(key: _keyUserType);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getUserType chamado - retornando: ${userType ?? "NULL"}');
    }
    return userType;
  }

  static Future<bool> isLoggedIn() async {
    final userId = await _secureStorage.read(key: _keyUserId);
    final hasUserId = userId != null && userId.isNotEmpty;
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: isLoggedIn chamado - tem userId? $hasUserId');
    }
    return hasUserId;
  }

  // Novo método útil para checar se tem loja
  static Future<bool> hasShopId() async {
    final shopId = await _secureStorage.read(key: _keyShopId);
    final hasShop = shopId != null && shopId.isNotEmpty;
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: hasShopId chamado - tem shopId? $hasShop');
    }
    return hasShop;
  }

  // Check if current user is an admin
  static Future<bool> isAdmin() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      // 1. Check metadata first (cached and fast)
      final metadata = user.userMetadata;
      if (metadata != null) {
        final role = metadata['role'] as String?;
        final roles = metadata['roles'] as List?;
        final isAdminDev = metadata['is_admin_dev'] == true;

        if (role == 'admin' ||
            (roles?.contains('admin') ?? false) ||
            isAdminDev) {
          return true;
        }
      }

      // 2. Fallback: Check public.users table for the most up-to-date role
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        final role = response['role'] as String?;
        final roles = response['roles'] as List?;
        final isAdminDev = response['is_admin_dev'] == true;

        if (role == 'admin' || (roles?.contains('admin') ?? false) || isAdminDev) {
          if (kDebugMode) {
            debugPrint('DEBUG SessionService: isAdmin confirmed via DB table for ${user.id}');
          }
          return true;
        }
      }

      if (kDebugMode) {
        debugPrint(
            'DEBUG SessionService: isAdmin check for ${user.id} - result: false');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ERROR SessionService: isAdmin check failed: $e');
      }
      return false;
    }
  }

  static Future<void> logout() async {
    await _secureStorage.delete(key: _keyUserId);
    await _secureStorage.delete(key: _keyShopId);
    await _secureStorage.delete(key: _keyUserType);
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    // Remove apenas dados de sessão/cache — preserva preferências do usuário (cidade selecionada)
    await prefs.remove(_keyLastAddress);
    await prefs.remove(_keyLastLat);
    await prefs.remove(_keyLastLng);
    await prefs.remove('shop_data_cache');
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: logout chamado - dados de sessão removidos (cidade preservada)');
    }
  }
}
