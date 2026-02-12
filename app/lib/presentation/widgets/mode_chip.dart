import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';

enum ModeChipStatus { queued, processing, completed, error }

/// Horizontal stepper showing L1-L4 processing progress as connected nodes.
///
/// UX rules applied: 44px touch targets, 12px min font (WCAG),
/// 4px spacing grid, status-aware glow halos.
class LevelProgressStepper extends StatelessWidget {
  final Map<int, ModeChipStatus> statuses;

  const LevelProgressStepper({super.key, required this.statuses});

  static const _labels = ['Intro', 'Facile', 'Moyen', 'Pro'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 1; i <= 4; i++) ...[
          _LevelNode(
            level: i,
            label: _labels[i - 1],
            status: statuses[i] ?? ModeChipStatus.queued,
          ),
          if (i < 4)
            _Connector(
              leftDone:
                  (statuses[i] ?? ModeChipStatus.queued) ==
                  ModeChipStatus.completed,
            ),
        ],
      ],
    );
  }
}

class _LevelNode extends StatelessWidget {
  final int level;
  final String label;
  final ModeChipStatus status;

  const _LevelNode({
    required this.level,
    required this.label,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final isActive = status != ModeChipStatus.queued;

    return SizedBox(
      width: AppConstants.touchTargetMin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Node circle — max contrast for mobile
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? color.withValues(alpha: 0.25)
                  : AppColors.divider,
              border: Border.all(
                color: isActive ? color : AppColors.textSecondary,
                width: status == ModeChipStatus.processing ? 2.5 : 2.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(child: _buildIcon(color)),
          ),
          const SizedBox(height: AppConstants.spacing4),
          // Level name
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: AppConstants.fontSizeMin,
              color: isActive ? color : AppColors.textSecondary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildIcon(Color color) {
    return switch (status) {
      ModeChipStatus.completed => Icon(
        Icons.check_rounded,
        size: 18,
        color: color,
      ),
      ModeChipStatus.error => Icon(Icons.close_rounded, size: 18, color: color),
      ModeChipStatus.processing => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      ModeChipStatus.queued => Text(
        '$level',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    };
  }

  Color get _color => switch (status) {
    ModeChipStatus.queued => AppColors.textSecondary,
    ModeChipStatus.processing => AppColors.primary,
    ModeChipStatus.completed => AppColors.success,
    ModeChipStatus.error => AppColors.error,
  };
}

class _Connector extends StatelessWidget {
  final bool leftDone;

  const _Connector({required this.leftDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Vertically center with the 36px node circle
      padding: const EdgeInsets.only(top: 17),
      child: Container(
        width: AppConstants.spacing20,
        height: 2.0,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          color: leftDone
              ? AppColors.success.withValues(alpha: 0.8)
              : AppColors.textSecondary.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
