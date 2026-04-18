import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const String _keyBusiness = 'tutorial_seen_business';
  static const String _keyClient = 'tutorial_seen_client';

  static Future<bool> hasSeenTutorial({required bool isBusiness}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(isBusiness ? _keyBusiness : _keyClient) ?? false;
  }

  static Future<void> markAsSeen({required bool isBusiness}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(isBusiness ? _keyBusiness : _keyClient, true);
  }

  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBusiness);
    await prefs.remove(_keyClient);
  }
}
