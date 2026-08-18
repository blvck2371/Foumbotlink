import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Cadre de champ de formulaire réutilisé par les écrans de composition
/// et d'authentification, pour un style cohérent.
class FormFieldBox extends StatelessWidget {
  const FormFieldBox({super.key, required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
