import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../modules/business/subscription_service.dart';
import '../services/ad_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _shouldShowAd = false;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionAndLoadAd();
  }

  Future<void> _checkSubscriptionAndLoadAd() async {
    final plan = await SubscriptionService.getCurrentPlan();
    final details = SubscriptionService.getPlanDetails(plan);

    // Check if plan has ads enabled (default true for Free, false for Paid)
    if (details['adEnabled'] == true) {
      if (mounted) {
        setState(() => _shouldShowAd = true);
        _loadAd();
      }
    }
  }

  void _loadAd() {
    _bannerAd = AdService.createBannerAd(
      onAdLoaded: (ad) {
        if (mounted) setState(() => _isLoaded = true);
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();
      },
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShowAd || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
