import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/strings_fr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class PrivacyDataPage extends StatelessWidget {
  const PrivacyDataPage({super.key});

  static const String privacyPolicyUrl = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text(StringsFr.privacyTitle)),
      body: ListView(
        children: [
          _buildSection(
            title: StringsFr.privacyMicroTitle,
            body: StringsFr.privacyMicroBody,
          ),
          _buildSection(
            title: StringsFr.privacyAdsTitle,
            body: StringsFr.privacyAdsBody,
          ),
          _buildSection(
            title: StringsFr.privacyAnalyticsTitle,
            body: StringsFr.privacyAnalyticsBody,
          ),
          _buildSection(
            title: StringsFr.privacyPurchasesTitle,
            body: StringsFr.privacyPurchasesBody,
          ),
          _buildSection(
            title: StringsFr.privacyPolicyTitle,
            body: privacyPolicyUrl.isEmpty
                ? StringsFr.privacyPolicyBody
                : privacyPolicyUrl,
          ),
          const SizedBox(height: AppConstants.spacing32),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        AppConstants.spacing16,
        AppConstants.spacing16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              body,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
