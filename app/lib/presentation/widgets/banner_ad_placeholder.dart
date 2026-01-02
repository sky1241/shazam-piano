import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../ads/admob_ads.dart';
import '../../core/theme/app_colors.dart';

class BannerAdPlaceholder extends StatelessWidget {
  const BannerAdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: AdSize.banner.height.toDouble(),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        alignment: Alignment.center,
        child: const AdmobBanner(),
      ),
    );
  }
}
