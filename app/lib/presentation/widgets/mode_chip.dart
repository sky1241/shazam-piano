import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

/// Progress chip for each level (L1-L4)
class ModeChip extends StatelessWidget {
  final int level;
  final ModeChipStatus status;

  const ModeChip({super.key, required this.level, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing8,
      ),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: _getBorderColor(), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(),
          const SizedBox(width: AppConstants.spacing8),
          Text(
            'L$level',
            style: AppTextStyles.body.copyWith(
              color: _getTextColor(),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (status) {
      case ModeChipStatus.queued:
        return Icon(Icons.schedule, size: 16, color: AppColors.divider);
      case ModeChipStatus.processing:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.warning,
          ),
        );
      case ModeChipStatus.completed:
        return Icon(Icons.check_circle, size: 16, color: AppColors.success);
      case ModeChipStatus.error:
        return Icon(Icons.error, size: 16, color: AppColors.error);
    }
  }

  Color _getBackgroundColor() {
    switch (status) {
      case ModeChipStatus.queued:
        return AppColors.surface;
      case ModeChipStatus.processing:
        return AppColors.warning.withOpacity(0.1);
      case ModeChipStatus.completed:
        return AppColors.success.withOpacity(0.1);
      case ModeChipStatus.error:
        return AppColors.error.withOpacity(0.1);
    }
  }

  Color _getBorderColor() {
    switch (status) {
      case ModeChipStatus.queued:
        return AppColors.divider;
      case ModeChipStatus.processing:
        return AppColors.warning;
      case ModeChipStatus.completed:
        return AppColors.success;
      case ModeChipStatus.error:
        return AppColors.error;
    }
  }

  Color _getTextColor() {
    switch (status) {
      case ModeChipStatus.queued:
        return AppColors.textSecondary;
      case ModeChipStatus.processing:
        return AppColors.warning;
      case ModeChipStatus.completed:
        return AppColors.success;
      case ModeChipStatus.error:
        return AppColors.error;
    }
  }
}

enum ModeChipStatus { queued, processing, completed, error }
