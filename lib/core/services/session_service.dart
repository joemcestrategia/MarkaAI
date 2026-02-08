import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      if (kDebugMode) debugPrint('DEBUG SessionService: shopId salvo no login: $shopId');
    } else {
      await prefs.remove(_keyShopId);
      if (kDebugMode) debugPrint('DEBUG SessionService: shopId removido no login (null ou vazio)');
    }
  }

  static Future<void> saveShopId(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    if (shopId.isEmpty) {
      await prefs.remove(_keyShopId);
      if (kDebugMode) debugPrint('DEBUG SessionService: shopId removido (vazio)');
    } else {
      await prefs.setString(_keyShopId, shopId);
      if (kDebugMode) debugPrint('DEBUG SessionService: shopId salvo via saveShopId: $shopId');
    }
  }

  static Future<String?> getShopId() async {
    final prefs = await SharedPreferences.getInstance();
    final shopId = prefs.getString(_keyShopId);
    if (kDebugMode) debugPrint('DEBUG SessionService: getShopId chamado - retornando: ${shopId ?? "NULL"}');
    return shopId;
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUserId);
    if (kDebugMode) debugPrint('DEBUG SessionService: getUserId chamado - retornando: ${userId ?? "NULL"}');
    return userId;
  }

  static Future<String?> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString(_keyUserType);
    if (kDebugMode) debugPrint('DEBUG SessionService: getUserType chamado - retornando: ${userType ?? "NULL"}');
    return userType;
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final hasUserId = prefs.containsKey(_keyUserId);
    if (kDebugMode) debugPrint('DEBUG SessionService: isLoggedIn chamado - tem userId? $hasUserId');
    return hasUserId;
  }

  // Novo método útil para checar se tem loja
  static Future<bool> hasShopId() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShop = prefs.containsKey(_keyShopId);
    if (kDebugMode) debugPrint('DEBUG SessionService: hasShopId chamado - tem shopId? $hasShop');
    return hasShop;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (kDebugMode) debugPrint('DEBUG SessionService: logout chamado - todas chaves removidas');
  }
}