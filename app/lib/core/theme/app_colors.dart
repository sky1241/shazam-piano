import 'package:flutter/material.dart';

/// ShazaPiano Design System - Dark Theme Colors
class AppColors {
  // Background
  static const Color bg = Color(0xFF0B0F10);
  static const Color surface = Color(0xFF12171A);
  static const Color card = Color(0xFF0F1417);

  // Primary
  static const Color primary = Color(0xFF2AE6BE);
  static const Color primaryVariant = Color(0xFF21C7A3);
  static const Color accent = Color(0xFF7EF2DA);

  // Text
  static const Color textPrimary = Color(0xFFE9F5F1);
  static const Color textSecondary = Color(0xFFA9C3BC);
  static const Color divider = Color(0xFF1E2A2E);

  // Status
  static const Color success = Color(0xFF47E1A8);
  static const Color warning = Color(0xFFF6C35D);
  static const Color error = Color(0xFFFF6B6B);

  // Piano Keys
  static const Color whiteKey = Color(0xFFE9F5F1);
  static const Color blackKey = Color(0xFF1E2A2E);

  // Gradients
  static const LinearGradient buttonGradient = LinearGradient(
    colors: [primary, primaryVariant],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const RadialGradient backgroundGradient = RadialGradient(
    center: Alignment(0, -0.2),
    radius: 1.5,
    colors: [
      Color(0x1F2AE6BE), // primary @ 12% opacity
      Colors.transparent,
    ],
  );

  // Private constructor
  AppColors._();
}
