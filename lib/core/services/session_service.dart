import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionService {
  static const String _keyUserId = 'userId';
  static const String _keyShopId = 'shopId';
  static const String _keyUserType = 'userType';

  // Salva os dados do login
  static Future<void> saveLogin({
    required String userId,
    required String userType,
    String? shopId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyUserType, userType);

    if (shopId != null && shopId.isNotEmpty) {
      await prefs.setString(_keyShopId, shopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId salvo no login: $shopId');
      }
    } else {
      await prefs.remove(_keyShopId);
      if (kDebugMode) {
        debugPrint(
            'DEBUG SessionService: shopId removido no login (null ou vazio)');
      }
    }
  }

  static Future<void> saveShopId(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    if (shopId.isEmpty) {
      await prefs.remove(_keyShopId);
      if (kDebugMode) {
        debugPrint('DEBUG SessionService: shopId removido (vazio)');
      }
    } else {
      await prefs.setString(_keyShopId, shopId);
      if (kDebugMode) {
        debugPrint(
            'DEBUG SessionService: shopId salvo via saveShopId: $shopId');
      }
    }
  }

  static Future<String?> getShopId() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getString(_keyShopId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getShopId chamado - retornando: ${shopId ?? "NULL"}');
    }
    return shopId;
  }

  // Last selected location (address + lat + lng)
  static const String _keyLastAddress = 'last_address';
  static const String _keyLastLat = 'last_lat';
  static const String _keyLastLng = 'last_lng';

  static Future<void> saveLastLocation(
      {required String address, double? lat, double? lng}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastAddress, address);
    if (lat != null) await prefs.setDouble(_keyLastLat, lat);
    if (lng != null) await prefs.setDouble(_keyLastLng, lng);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: last location salvo: $address ($lat,$lng)');
    }
  }

  static Future<Map<String, dynamic>?> getLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_keyLastAddress);
    if (address == null) return null;
    final lat =
        prefs.containsKey(_keyLastLat) ? prefs.getDouble(_keyLastLat) : null;
    final lng =
        prefs.containsKey(_keyLastLng) ? prefs.getDouble(_keyLastLng) : null;
    return {'address': address, 'lat': lat, 'lng': lng};
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getUserId chamado - retornando: ${userId ?? "NULL"}');
    }
    return userId;
  }

  static Future<String?> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString(_keyUserType);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: getUserType chamado - retornando: ${userType ?? "NULL"}');
    }
    return userType;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final hasUserId = prefs.containsKey(_keyUserId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: isLoggedIn chamado - tem userId? $hasUserId');
    }
    return hasUserId;
  }

  // Novo método útil para checar se tem loja
  static Future<bool> hasShopId() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShop = prefs.containsKey(_keyShopId);
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: hasShopId chamado - tem shopId? $hasShop');
    }
    return hasShop;
  }

  // Check if current user is an admin
  static Future<bool> isAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final userId = user.uid;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) return false;
      final data = doc.data();
      final role = data?['role'] as String?;
      final roles = data?['roles'] as List?;
      final isAdminDev = data?['is_admin_dev'] == true;

      final isAnyAdmin = role == 'admin' || 
                         (roles?.contains('admin') ?? false) || 
                         isAdminDev;

      if (kDebugMode) {
        debugPrint(
            'DEBUG SessionService: isAdmin checked for $userId - result: $isAnyAdmin');
      }
      return isAnyAdmin;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ERROR SessionService: isAdmin check failed: $e');
      }
      return false;
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (kDebugMode) {
      debugPrint(
          'DEBUG SessionService: logout chamado - todas chaves removidas');
    }
  }
}
