import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildWebView({
  required String assetPath,
  required Function(String) onMessage,
  required Function(WebViewController) onControllerCreated,
  Map<String, String>? initialData,
}) {
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('FlutterChannel', onMessageReceived: (msg) => onMessage(msg.message));

  // Always load HTTPS page via Cloud Function to avoid SPA/service worker.
  // Function URL: https://us-central1-wismart-118c3.cloudfunctions.net/checkoutTransparentePage
  final String hostedBase =
      'https://us-central1-wismart-118c3.cloudfunctions.net/checkoutTransparentePage';
  String relative = '';
  // Build query string from initialData
  String query = '';
  if (initialData != null && initialData.isNotEmpty) {
    query = '?${initialData.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&')}';
  }
  final Uri uri = Uri.parse(hostedBase + relative + query);
  debugPrint('WebView URL: $uri');
  controller.loadRequest(uri);

  onControllerCreated(controller);
  return WebViewWidget(controller: controller);
}