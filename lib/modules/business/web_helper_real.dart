// ignore_for_file: avoid_web_libraries_in_flutter
/// Web helper — REAL implementation using package:web / dart:ui_web.
/// Conditionally imported only when compiling for the web target.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

typedef MessageCallback = void Function(String data);

String getWindowOrigin() {
  try {
    return web.window.location.origin;
  } catch (_) {
    return '*';
  }
}

dynamic listenPostMessage(MessageCallback cb) {
  return web.window.onMessage.listen((event) {
    try {
      final raw = event.data?.toString() ?? '';
      if (raw.isNotEmpty) cb(raw);
    } catch (_) {}
  });
}

String? getHashCatalogData() {
  try {
    final hash = web.window.location.hash;
    if (hash.contains('#catalog=')) {
      final encoded = hash.split('#catalog=').last;
      // Clean the hash
      web.window.history.replaceState(null, '', web.window.location.pathname);
      return encoded;
    }
  } catch (_) {}
  return null;
}

void openWindow(String url, String name) {
  web.window.open(url, name);
}

void downloadImageWeb(List<int> bytes, String fileName) {
  try {
    final uint8list = Uint8List.fromList(bytes);
    final blob = web.Blob([uint8list.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(url);
  } catch (e) {
    debugPrint('Erro ao baixar imagem no Web: $e');
  }
}

Future<String?> readClipboardWeb() async {
  try {
    // navigator.clipboard returns a Promise<JSString>
    // We use .toDart to convert the JS Promise to a Dart Future
    final result = await web.window.navigator.clipboard.readText().toDart;
    return result.toDart;
  } catch (_) {
    return null;
  }
}

bool registerBookmarkletView(String viewId, String href) {
  try {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (_) {
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = href;
      anchor.draggable = true;
      anchor.title = 'Arraste para a barra de favoritos';

      anchor.style.display = 'inline-flex';
      anchor.style.alignItems = 'center';
      anchor.style.gap = '8px';
      anchor.style.background = '#25D366';
      anchor.style.color = 'white';
      anchor.style.fontWeight = 'bold';
      anchor.style.fontSize = '14px';
      anchor.style.padding = '12px 20px';
      anchor.style.borderRadius = '10px';
      anchor.style.textDecoration = 'none';
      anchor.style.fontFamily = 'sans-serif';
      anchor.style.cursor = 'grab';
      anchor.style.boxShadow = '0 3px 10px rgba(37,211,102,.3)';
      anchor.style.userSelect = 'none';

      anchor.text = '📌  Arraste este favorito para a barra do Chrome';
      return anchor;
    });
    return true;
  } catch (_) {
    return false;
  }
}
