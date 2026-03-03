// ignore_for_file: avoid_web_libraries_in_flutter
/// Web helper — REAL implementation using dart:html / dart:ui_web.
/// Conditionally imported only when compiling for the web target.
library;

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

typedef MessageCallback = void Function(String data);

String getWindowOrigin() {
  try {
    return html.window.location.origin;
  } catch (_) {
    return '*';
  }
}

dynamic listenPostMessage(MessageCallback cb) {
  return html.window.onMessage.listen((event) {
    try {
      final raw = event.data?.toString() ?? '';
      if (raw.isNotEmpty) cb(raw);
    } catch (_) {}
  });
}

String? getHashCatalogData() {
  try {
    final hash = html.window.location.hash;
    if (hash.contains('#catalog=')) {
      final encoded = hash.split('#catalog=').last;
      // Clean the hash
      html.window.history.replaceState(null, '', html.window.location.pathname);
      return encoded;
    }
  } catch (_) {}
  return null;
}

void openWindow(String url, String name) {
  html.window.open(url, name);
}

Future<String?> readClipboardWeb() async {
  try {
    return await html.window.navigator.clipboard?.readText();
  } catch (_) {
    return null;
  }
}

bool registerBookmarkletView(String viewId, String href) {
  try {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (_) {
      final anchor = html.AnchorElement()
        ..href = href
        ..draggable = true
        ..title = 'Arraste para a barra de favoritos';
      anchor.style
        ..display = 'inline-flex'
        ..alignItems = 'center'
        ..gap = '8px'
        ..background = '#25D366'
        ..color = 'white'
        ..fontWeight = 'bold'
        ..fontSize = '14px'
        ..padding = '12px 20px'
        ..borderRadius = '10px'
        ..textDecoration = 'none'
        ..fontFamily = 'sans-serif'
        ..cursor = 'grab'
        ..boxShadow = '0 3px 10px rgba(37,211,102,.3)'
        ..userSelect = 'none';
      anchor.text = '🔖  Arraste este favorito para a barra do Chrome';
      return anchor;
    });
    return true;
  } catch (_) {
    return false;
  }
}
