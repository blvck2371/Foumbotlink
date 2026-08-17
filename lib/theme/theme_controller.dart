import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_theme.dart';

class ThemeController extends GetxController {
  static const _key = 'foumbotlik_theme_mode';

  final isDark = true.obs;

  ThemeMode get themeMode =>
      isDark.value ? ThemeMode.dark : ThemeMode.light;

  ThemeData get theme => isDark.value ? AppTheme.dark : AppTheme.light;

  bool get isDarkMode => isDark.value;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    isDark.value = prefs.getBool(_key) ?? true;
    _applySystemUi();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isDark.value);
  }

  void _applySystemUi() {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark.value ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:
            isDark.value ? AppColors.black : AppColors.white,
        systemNavigationBarIconBrightness:
            isDark.value ? Brightness.light : Brightness.dark,
      ),
    );
  }

  void setDark(bool value) {
    if (isDark.value == value) return;
    isDark.value = value;
    _applySystemUi();
    _persist();
  }

  void toggleTheme() => setDark(!isDark.value);
}
