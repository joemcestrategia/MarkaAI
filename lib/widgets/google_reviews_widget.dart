import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../core/theme/app_colors.dart';

class GoogleReviewsWidget extends StatefulWidget {
  final String placeId;
  final bool showAll;

  const GoogleReviewsWidget({
    super.key,
    required this.placeId,
    this.showAll = false,
  });

  @override
  State<GoogleReviewsWidget> createState() => _GoogleReviewsWidgetState();
}

class _GoogleReviewsWidgetState extends State<GoogleReviewsWidget> {
  bool _isLoading = true;
  bool _showAllReviews = false;
  Map<String, dynamic>? _placeData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _showAllReviews = widget.showAll;
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse(
            'https://us-central1-wismart-118c3.cloudfunctions.net/getGoogleReviews'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'place_id': widget.placeId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          setState(() {
            _placeData = data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = data['error'] ?? 'Erro ao carregar avaliações';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Erro ao conectar: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erro ao carregar: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.orange, size: 16);
        } else if (index < rating && rating % 1 >= 0.5) {
          return const Icon(Icons.star_half, color: Colors.orange, size: 16);
        } else {
          return const Icon(Icons.star_border, color: Colors.orange, size: 16);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.grey, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loadReviews,
                icon: const Icon(Icons.refresh),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          ),
        ),
      );
    }

    if (_placeData == null || _placeData!['reviews'] == null) {
      return const SizedBox.shrink();
    }

    final reviews = _placeData!['reviews'] as List;
    final rating = _placeData!['rating'] ?? 0.0;
    final totalReviews = _placeData!['user_ratings_total'] ?? 0;

    // Mostrar apenas as 3 primeiras se _showAllReviews for false
    final displayReviews = _showAllReviews ? reviews : reviews.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com média geral
          Row(
            children: [
              const Icon(Icons.star, color: Colors.orange, size: 28),
              const SizedBox(width: 8),
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '($totalReviews avaliações)',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStars(rating.toDouble()),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Use an inline icon instead of requesting an asset that may be missing on web
                    const Icon(
                      Icons.g_mobiledata,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Google',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Título da seção
          const Text(
            'Avaliações',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Lista de avaliações
          if (displayReviews.isEmpty)
            const Center(
              child: Text(
                'Nenhuma avaliação ainda',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...displayReviews.map((review) => _buildReviewCard(review)),

          // Botão "Carregar Mais"
          if (!_showAllReviews && reviews.length > 3) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAllReviews = true),
                icon: const Icon(Icons.expand_more),
                label: Text('VER TODAS (${reviews.length - 3} restantes)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                  side: const BorderSide(color: AppColors.primaryPurple),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],

          // Botão "Mostrar Menos"
          if (_showAllReviews && reviews.length > 3) ...[
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showAllReviews = false),
                icon: const Icon(Icons.expand_less),
                label: const Text('MOSTRAR MENOS'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                  side: const BorderSide(color: AppColors.primaryPurple),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header da avaliação
          Row(
            children: [
              // Foto do perfil
              CircleAvatar(
                radius: 20,
                backgroundImage: review['profile_photo_url'] != null
                    ? NetworkImage(review['profile_photo_url'])
                    : null,
                backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                child: review['profile_photo_url'] == null
                    ? const Icon(Icons.person, color: AppColors.primaryPurple)
                    : null,
              ),
              const SizedBox(width: 12),
              // Nome e data
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review['author_name'] ?? 'Anônimo',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      review['relative_time_description'] ?? '',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Estrelas
              _buildStars((review['rating'] ?? 0).toDouble()),
            ],
          ),

          // Texto da avaliação
          if (review['text'] != null &&
              review['text'].toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review['text'],
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
