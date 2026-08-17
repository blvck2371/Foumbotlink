import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// AppBar Foumbot — rouge / blanc / noir, titre Space Grotesk.
class FoumbotAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FoumbotAppBar({
    super.key,
    required this.isDark,
    this.title = 'Foumbot',
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final bool isDark;
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final bg = isDark ? AppColors.black : AppColors.white;

    return AppBar(
      backgroundColor: bg,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      iconTheme: IconThemeData(color: ink),
      actionsIconTheme: IconThemeData(color: ink),
      title: Text(
        title,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      actions: actions,
    );
  }
}
