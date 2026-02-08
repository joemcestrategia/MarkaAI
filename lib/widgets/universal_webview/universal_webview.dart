// lib/widgets/universal_webview/universal_webview.dart
export 'webview_platform_stub.dart'
    if (dart.library.js_util) 'webview_platform_web.dart'
    if (dart.library.io) 'webview_platform_mobile.dart';