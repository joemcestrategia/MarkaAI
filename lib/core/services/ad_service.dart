import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  // --- Ad Unit IDs ---
  // Android
  static const String _androidBannerId =
      'ca-app-pub-4304690293754093/1536611087'; // Production ID
  static const String _androidInterstitialId =
      'ca-app-pub-3940256099942544/1033173712'; // Test ID

  // iOS
  // TODO: Replace with real iOS Ad Unit IDs from AdMob Console
  static const String _iosBannerId =
      'ca-app-pub-3940256099942544/2934735716'; // Test ID
  static const String _iosInterstitialId =
      'ca-app-pub-3940256099942544/4411468910'; // Test ID

  static Future<void> initialize() async {
    if (kIsWeb) return; // Ads not supported on web yet or handled differently
    await MobileAds.instance.initialize();
  }

  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _androidBannerId;
    } else if (Platform.isIOS) {
      return _iosBannerId;
    }
    return '';
  }

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return _androidInterstitialId;
    } else if (Platform.isIOS) {
      return _iosInterstitialId;
    }
    return '';
  }

  static BannerAd createBannerAd(
      {required Function(Ad) onAdLoaded,
      required Function(Ad, LoadAdError) onAdFailedToLoad}) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }

  static void loadInterstitialAd(
      {required Function(InterstitialAd) onAdLoaded,
      required Function(LoadAdError) onAdFailedToLoad}) {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
      ),
    );
  }
}
