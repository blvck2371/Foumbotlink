import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/weather.dart';
import '../services/weather_service.dart';
import '../theme/app_colors.dart';
import 'weather_visuals.dart';

/// Ouvre la météo de la semaine à Foumbot dans une feuille en bas
/// d'écran : gros icônes, mots simples et conseils pratiques plutôt que
/// des chiffres bruts, pour rester lisible même sans savoir lire une
/// météo classique. Montre aussi À QUELLE HEURE il pleut ou fait beau,
/// pas seulement un résumé de la journée.
void showWeeklyWeatherSheet(BuildContext context, {required bool isDark}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _WeeklyWeatherSheet(isDark: isDark),
  );
}

/// Résume en une phrase simple les heures où la pluie est probable
/// (risque ≥ 50%), en fusionnant les créneaux qui se suivent — ex.
/// "Pluie probable de 14h à 17h" plutôt qu'un pourcentage brut.
String? _rainWindowSummary(List<WeatherHour> hours) {
  final windows = <List<int>>[];
  for (var i = 0; i < hours.length; i++) {
    if (hours[i].rainChance < 50) continue;
    if (windows.isNotEmpty && windows.last[1] == i - 1) {
      windows.last[1] = i;
    } else {
      windows.add([i, i]);
    }
  }
  if (windows.isEmpty) return null;

  final parts = windows.map((w) {
    final startHour = hours[w[0]].time.hour;
    final endHour = (hours[w[1]].time.hour + 1) % 24;
    return startHour == endHour
        ? 'vers ${startHour}h'
        : 'de ${startHour}h à ${endHour}h';
  });

  return 'Pluie probable ${parts.join(' et ')}';
}

class _WeeklyWeatherSheet extends StatelessWidget {
  const _WeeklyWeatherSheet({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final weather = Get.find<WeatherService>();
    final bg = isDark ? AppColors.blackSoft : AppColors.white;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.only(top: 60),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Obx(() {
          final today = weather.snapshot.value;
          final days = weather.forecast;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Météo à Foumbot',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualiser',
                      onPressed: weather.refreshNow,
                      icon: Icon(Icons.refresh_rounded, color: muted),
                    ),
                  ],
                ),
              ),
              if (today == null && days.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Text(
                    'Météo indisponible pour le moment. Vérifiez votre '
                    'connexion et réessayez.',
                    style: GoogleFonts.manrope(color: muted, height: 1.4),
                  ),
                )
              else ...[
                if (today != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: _TodayBanner(
                      isDark: isDark,
                      snapshot: today,
                      nextHours: weather.nextHours(),
                    ),
                  ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: days.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) => _DayRow(
                      day: days[i],
                      isToday: i == 0,
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                    ),
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

class _TodayBanner extends StatelessWidget {
  const _TodayBanner({
    required this.isDark,
    required this.snapshot,
    required this.nextHours,
  });

  final bool isDark;
  final WeatherSnapshot snapshot;
  final List<WeatherHour> nextHours;

  @override
  Widget build(BuildContext context) {
    final color = weatherColor(snapshot.condition, isDark);
    final rainWindow = _rainWindowSummary(nextHours);
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(weatherIcon(snapshot.condition), size: 40, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'En ce moment : ${snapshot.roundedTemperature}°, '
                      '${snapshot.condition.label.toLowerCase()}',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rainWindow ?? snapshot.condition.advice,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nextHours.isNotEmpty) ...[
            const SizedBox(height: 14),
            _HourlyStrip(hours: nextHours, isDark: isDark, ink: ink, muted: muted),
          ],
        ],
      ),
    );
  }
}

/// Bandeau horizontal heure par heure : icône + heure + température, pour
/// voir d'un coup d'œil QUAND il va pleuvoir ou faire beau.
class _HourlyStrip extends StatelessWidget {
  const _HourlyStrip({
    required this.hours,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final List<WeatherHour> hours;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: hours.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final hour = hours[i];
          final now = DateTime.now();
          final isNow = hour.time.year == now.year &&
              hour.time.month == now.month &&
              hour.time.day == now.day &&
              hour.time.hour == now.hour;
          final color = weatherColor(hour.condition, isDark);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isNow ? 'Maintenant' : '${hour.time.hour}h',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: isNow ? FontWeight.w800 : FontWeight.w600,
                  color: isNow ? ink : muted,
                ),
              ),
              const SizedBox(height: 8),
              Icon(weatherIcon(hour.condition), color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                '${hour.roundedTemperature}°',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayRow extends StatefulWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final WeatherDay day;
  final bool isToday;
  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  bool _expanded = false;

  static const _weekdays = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];

  String get _dayLabel {
    if (widget.isToday) return 'Aujourd’hui';
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final date = widget.day.date;
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'Demain';
    }
    return _weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final isDark = widget.isDark;
    final ink = widget.ink;
    final muted = widget.muted;
    final color = weatherColor(day.condition, isDark);
    final hours = Get.find<WeatherService>().hoursForDay(day.date);
    final rainWindow = _rainWindowSummary(hours);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hours.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isToday
                ? color.withValues(alpha: isDark ? 0.12 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      _dayLabel,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  Icon(weatherIcon(day.condition), color: color, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          day.condition.label,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: ink,
                          ),
                        ),
                        if (rainWindow != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.water_drop_rounded,
                                  size: 12, color: AppColors.blue),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  rainWindow,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${day.roundedMax}°',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${day.roundedMin}°',
                    style: GoogleFonts.manrope(fontSize: 15, color: muted),
                  ),
                  if (hours.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: muted,
                    ),
                  ],
                ],
              ),
              if (_expanded && hours.isNotEmpty) ...[
                const SizedBox(height: 8),
                _HourlyStrip(
                  hours: hours,
                  isDark: isDark,
                  ink: ink,
                  muted: muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
