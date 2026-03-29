import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 再利用可能なAdMobバナーウィジェット
/// 使い方: AdBannerWidget() をページ下部に配置するだけ
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  static String get _unitId {
    // テスト用ID（本番に切り替える際は constants.dart の useTestAds を false にして
    // _admobBannerIos / _admobBannerAndroid を実際のIDに差し替える）
    if (Platform.isIOS) {
      // return 'ca-app-pub-3940256099942544/2934735716'; // iOS test banner
      return 'ca-app-pub-1178983985791938/5888777228';
    }
    return 'ca-app-pub-3940256099942544/6300978111';   // Android test banner
  }

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _ad = BannerAd(
      adUnitId: _unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
