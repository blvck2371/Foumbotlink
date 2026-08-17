import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.black,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.red,
        secondary: AppColors.white,
        surface: AppColors.blackSoft,
        onPrimary: AppColors.white,
        onSecondary: AppColors.black,
        onSurface: AppColors.white,
        error: AppColors.redDeep,
      ),
    );
    return _withTypography(
      base,
      onSurface: AppColors.white,
      muted: AppColors.whiteMuted,
      appBarBg: AppColors.black,
      surface: AppColors.blackSoft,
      elevated: AppColors.blackElevated,
    );
  }

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.white,
      colorScheme: const ColorScheme.light(
        primary: AppColors.red,
        secondary: AppColors.black,
        surface: AppColors.whiteSoft,
        onPrimary: AppColors.white,
        onSecondary: AppColors.white,
        onSurface: AppColors.black,
        error: AppColors.redDeep,
      ),
    );
    return _withTypography(
      base,
      onSurface: AppColors.black,
      muted: AppColors.gray,
      appBarBg: AppColors.white,
      surface: AppColors.whiteSoft,
      elevated: AppColors.white,
    );
  }

  static ThemeData _withTypography(
    ThemeData base, {
    required Color onSurface,
    required Color muted,
    required Color appBarBg,
    required Color surface,
    required Color elevated,
  }) {
    final display = GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    final body = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );

    return base.copyWith(
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: onSurface,
        ),
        displayMedium: display.displayMedium?.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: onSurface,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: onSurface,
        ),
        titleLarge: display.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        bodyLarge: body.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.45,
          color: onSurface,
        ),
        bodyMedium: body.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.4,
          color: muted,
        ),
        labelLarge: body.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: onSurface,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: AppColors.white,
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: onSurface),
        actionsIconTheme: IconThemeData(color: onSurface),
        titleTextStyle: display.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        systemOverlayStyle: appBarBg == AppColors.black
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        textStyle: GoogleFonts.manrope(
          color: onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: onSurface.withValues(alpha: 0.1),
      ),
      iconTheme: IconThemeData(color: onSurface),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.red,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.red,
        foregroundColor: AppColors.white,
      ),
    );
  }
}
