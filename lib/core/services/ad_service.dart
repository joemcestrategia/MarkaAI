import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// AdHelper — Ad Unit IDs for the client home page ads.
// TODO: Replace test IDs with real production unit IDs from the AdMob console.
// App ID (already set in AndroidManifest / Info.plist):
//   ca-app-pub-4304690293754093~6073797484
// ---------------------------------------------------------------------------
class AdHelper {
  static String get bannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-4304690293754093/3425627382';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // TODO: real ID
    }
    throw UnsupportedError('Unsupported platform for AdMob banner');
  }

  static String get nativeAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-4304690293754093/8486382379';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/3986624511'; // TODO: real ID
    }
    throw UnsupportedError('Unsupported platform for AdMob native');
  }
}
