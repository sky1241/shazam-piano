import 'package:flutter/material.dart';
import 'app_colors.dart';

/// ShazaPiano Typography
class AppTextStyles {
  // Display - 24px
  static const TextStyle display = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  // Title - 18px
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  // Body - 14px
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  // Caption - 12px
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  // Private constructor
  AppTextStyles._();
}

