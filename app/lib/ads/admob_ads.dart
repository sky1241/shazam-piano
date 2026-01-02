import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _androidBannerAdUnitId = 'ca-app-pub-3763795208308317/8745935199';
const _androidInterstitialAdUnitId = 'ca-app-pub-3763795208308317/3479304253';
const _androidTestBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
const _androidTestInterstitialAdUnitId =
    'ca-app-pub-3940256099942544/1033173712';

String get _bannerAdUnitId =>
    kReleaseMode ? _androidBannerAdUnitId : _androidTestBannerAdUnitId;

String get _interstitialAdUnitId => kReleaseMode
    ? _androidInterstitialAdUnitId
    : _androidTestInterstitialAdUnitId;

bool _supportsAds() {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.android;
}

class AdmobBanner extends StatefulWidget {
  const AdmobBanner({super.key});

  @override
  State<AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<AdmobBanner> {
  static const AdSize _adSize = AdSize.banner;
  BannerAd? _banner;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!_supportsAds()) {
      return;
    }
    final banner = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: _adSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            debugPrint('AdMob banner failed to load: $error');
          }
        },
      ),
    );
    _banner = banner;
    banner.load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsAds()) {
      return const SizedBox.shrink();
    }
    final height = _adSize.height.toDouble();
    final width = _adSize.width.toDouble();
    if (!_isLoaded || _banner == null) {
      return SizedBox(height: height, width: width);
    }
    return SizedBox(
      height: height,
      width: width,
      child: AdWidget(ad: _banner!),
    );
  }
}

class AdmobInterstitialOnce {
  static const _prefsKey = 'admob_practice_interstitial_shown';
  static bool _requested = false;

  static Future<void> maybeShowPractice() async {
    if (!_supportsAds()) {
      return;
    }
    if (_requested) {
      return;
    }
    _requested = true;
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_prefsKey) ?? false;
    if (alreadyShown) {
      return;
    }
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (_) {
              unawaited(prefs.setBool(_prefsKey, true));
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _requested = false;
              if (kDebugMode) {
                debugPrint('AdMob interstitial failed to show: $error');
              }
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {
          _requested = false;
          if (kDebugMode) {
            debugPrint('AdMob interstitial failed to load: $error');
          }
        },
      ),
    );
  }
}
