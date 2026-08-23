import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16.0});
  const VerifiedBadge.small({super.key}) : size = 14.0;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.blue,
            Color(0xFF00BCD4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x401E88E5),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Icon(
        Icons.check,
        size: size * 0.65,
        color: AppColors.white,
      ),
    );
  }
}
