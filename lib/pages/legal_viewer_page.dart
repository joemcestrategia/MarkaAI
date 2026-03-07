import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../core/theme/app_colors.dart';

class LegalViewerPage extends StatelessWidget {
  final String title;
  final String markdownContent;

  const LegalViewerPage({
    super.key,
    required this.title,
    required this.markdownContent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Markdown(
        data: markdownContent,
        styleSheet: MarkdownStyleSheet(
          h1: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryPurple,
          ),
          h2: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            height: 1.5,
          ),
          p: const TextStyle(
            fontSize: 16,
            color: Colors.black87,
            height: 1.4,
          ),
          listBullet: const TextStyle(
            color: AppColors.primaryPurple,
          ),
        ),
      ),
    );
  }
}
