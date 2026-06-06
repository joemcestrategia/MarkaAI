import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PexelsImageWidget extends StatefulWidget {
  final String searchQuery;
  final int index;
  const PexelsImageWidget({super.key, required this.searchQuery, required this.index});

  @override
  State<PexelsImageWidget> createState() => _PexelsImageWidgetState();
}

class _PexelsImageWidgetState extends State<PexelsImageWidget> {
  String? _imageUrl;
  static const String _pexelsApiKey =
      '1RYDlI3xTEeYwIHOfwh3MZCslQNj3XYeQ7MmyoBRTy6uRQxujW7nfvkf';
  static final Map<String, List<String>> _queryCache = {};

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(PexelsImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final cachedUrls = _queryCache[widget.searchQuery];
    if (cachedUrls != null && cachedUrls.isNotEmpty) {
      _imageUrl = cachedUrls[widget.index % cachedUrls.length];
      return;
    }

    try {
      final url = Uri.parse(
          'https://api.pexels.com/v1/search?query=${Uri.encodeComponent(widget.searchQuery)}&per_page=15');
      final response =
          await http.get(url, headers: {'Authorization': _pexelsApiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final photos = data['photos'] as List;
        if (photos.isNotEmpty && mounted) {
          final urls = photos.map<String>((p) => p['src']['medium'].toString()).toList();
          _queryCache[widget.searchQuery] = urls;
          setState(() => _imageUrl = urls[widget.index % urls.length]);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Erro ao carregar imagem Pexels: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageUrl == null) {
      return Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image, color: Colors.grey),
      );
    }
    return Image.network(
      _imageUrl!, 
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[100],
          child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.error_outline, color: Colors.grey),
      ),
    );
  }
}
