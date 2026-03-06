// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'package:webview_flutter/webview_flutter.dart';

Widget buildWebView({
  required String assetPath,
  required Function(String) onMessage,
  required Function(WebViewController) onControllerCreated,
  Map<String, String>? initialData,
}) {
  final String viewId = 'mp-checkout-${DateTime.now().millisecondsSinceEpoch}';
  final String baseUrl =
      assetPath.startsWith('assets/') ? assetPath : 'assets/$assetPath';
  final String query = (initialData != null && initialData.isNotEmpty)
      ? '?${initialData.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
      : '';

  ui.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
    return html.IFrameElement()
      ..src = baseUrl + query
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%';
  });

  // Na Web não há WebViewController nativo; onControllerCreated é ignorado.
  // Escutamos os eventos do IFrame via window postMessage.
  html.window.onMessage.listen((html.MessageEvent event) {
    if (event.data != null) {
      final String payload = event.data.toString();
      // Filtramos mensagens que não são do nosso checkout (evitar plugins sujos da página)
      if (payload.contains('"action"') || payload.contains("'action'")) {
        onMessage(payload);
      }
    }
  });

  return HtmlElementView(viewType: viewId);
}
