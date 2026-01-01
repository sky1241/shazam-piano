import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class BannerAdPlaceholder extends StatelessWidget {
  const BannerAdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 56,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        alignment: Alignment.center,
        child: Text(
          'Pub (banniere) - a remplacer par AdMob',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
