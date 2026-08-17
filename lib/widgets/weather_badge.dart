import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import 'weather_visuals.dart';
import 'weekly_weather_sheet.dart';

/// Badge météo temps réel de Foumbot (température + icône), affiché dans
/// l'AppBar. Un tap ouvre la météo de la semaine. Se masque silencieusement
/// tant que la première donnée n'est pas arrivée (ou si le réseau est
/// indisponible) — jamais de spinner ni d'erreur visible, l'app reste
/// utilisable sans météo.
class WeatherBadge extends StatelessWidget {
  const WeatherBadge({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final weather = Get.find<WeatherService>();

    return Obx(() {
      final snapshot = weather.snapshot.value;
      if (snapshot == null) return const SizedBox.shrink();

      final ink = isDark ? AppColors.white : AppColors.black;

      return Tooltip(
        message: 'Météo à Foumbot — voir la semaine',
        child: InkWell(
          onTap: () => showWeeklyWeatherSheet(context, isDark: isDark),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  weatherIcon(snapshot.condition),
                  size: 20,
                  color: weatherColor(snapshot.condition, isDark),
                ),
                const SizedBox(width: 4),
                Text(
                  '${snapshot.roundedTemperature}°',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
