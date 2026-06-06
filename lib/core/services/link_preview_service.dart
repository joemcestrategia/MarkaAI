import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

class LinkPreviewData {
  final String? title;
  final String? imageUrl;
  final String? description;
  final String? price;

  LinkPreviewData({this.title, this.imageUrl, this.description, this.price});
}

class LinkPreviewService {
  static Future<LinkPreviewData?> fetchPreview(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      // Add a generic user agent to avoid being blocked by simple anti-bot mechanisms
      final response = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final document = parse(response.body);

      // Try to find OpenGraph tags
      String? title;
      String? imageUrl;
      String? description;
      String? price;

      final metaTags = document.getElementsByTagName('meta');
      for (final meta in metaTags) {
        final property = meta.attributes['property'] ?? meta.attributes['name'];
        final content = meta.attributes['content'];

        if (property == 'og:title' && content != null) {
          title = content;
        } else if (property == 'og:image' && content != null) {
          imageUrl = content;
        } else if (property == 'og:description' && content != null) {
          description = content;
        } else if ((property == 'product:price:amount' || property == 'price') && content != null) {
          price = content;
        }
      }

      // Fallback to title tag if og:title is missing
      title ??= document.getElementsByTagName('title').firstOrNull?.text;

      return LinkPreviewData(
        title: title?.trim(),
        imageUrl: imageUrl?.trim(),
        description: description?.trim(),
        price: price?.trim(),
      );
    } catch (e) {
      print('Error fetching link preview: $e');
      return null;
    }
  }
}
