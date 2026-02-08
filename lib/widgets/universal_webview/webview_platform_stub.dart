import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildWebView({
  required String assetPath,
  required Function(String) onMessage,
  required Function(WebViewController) onControllerCreated,
  Map<String, String>? initialData,
}) => throw UnsupportedError('Plataforma não suportada');