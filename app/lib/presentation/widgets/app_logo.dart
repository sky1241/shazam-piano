import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// App Logo Widget using SVG
class AppLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final Color? color;

  const AppLogo({super.key, this.width, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/images/app_logo.svg',
      width: width ?? 120,
      height: height ?? 40,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
      placeholderBuilder: (context) => Container(
        width: width ?? 120,
        height: height ?? 40,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
