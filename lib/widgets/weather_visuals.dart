import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../theme/app_colors.dart';

/// Icône et couleur associées à une condition météo — utilisées à la
/// fois par le badge dans l'AppBar et par la vue "météo de la semaine",
/// pour rester cohérentes partout.
IconData weatherIcon(WeatherCondition condition) => switch (condition) {
      WeatherCondition.sunny => Icons.wb_sunny_rounded,
      WeatherCondition.cloudy => Icons.wb_cloudy_rounded,
      // Une goutte d'eau claire plutôt qu'un parapluie (illisible en
      // petit — il ressort fermé/affaissé, pas clairement "pluie").
      WeatherCondition.rain => Icons.water_drop_rounded,
      WeatherCondition.storm => Icons.thunderstorm_rounded,
      WeatherCondition.fog => Icons.foggy,
      WeatherCondition.snow => Icons.ac_unit_rounded,
      WeatherCondition.unknown => Icons.thermostat_rounded,
    };

Color weatherColor(WeatherCondition condition, bool isDark) =>
    switch (condition) {
      WeatherCondition.sunny => const Color(0xFFF5A623),
      WeatherCondition.rain || WeatherCondition.storm => AppColors.blue,
      _ => isDark ? AppColors.whiteMuted : AppColors.gray,
    };
