import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// Météo temps réel de Foumbot (Ouest Cameroun), via Open-Meteo — API
/// publique gratuite, sans clé requise.
class WeatherService extends GetxService {
  // Foumbot, Noun, Ouest Cameroun.
  static const _latitude = 5.7167;
  static const _longitude = 10.6333;
  static const _refreshInterval = Duration(minutes: 20);

  final snapshot = Rxn<WeatherSnapshot>();
  /// Prévision des 7 prochains jours (aujourd'hui inclus).
  final forecast = RxList<WeatherDay>([]);
  /// Prévision heure par heure sur les 7 prochains jours — sert à montrer
  /// à quel moment il pleut ou fait beau, pas seulement un résumé.
  final hourly = RxList<WeatherHour>([]);
  Timer? _timer;

  /// Heures de prévision pour une journée donnée (comparaison sur la
  /// date seule, indépendamment de l'heure).
  List<WeatherHour> hoursForDay(DateTime day) => hourly
      .where((h) =>
          h.time.year == day.year &&
          h.time.month == day.month &&
          h.time.day == day.day)
      .toList();

  /// Les prochaines heures à partir de maintenant (heure en cours
  /// incluse), pour le bandeau "météo du moment".
  List<WeatherHour> nextHours({int count = 12}) {
    final now = DateTime.now();
    final currentHour = DateTime(now.year, now.month, now.day, now.hour);
    return hourly
        .where((h) => !h.time.isBefore(currentHour))
        .take(count)
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
    unawaited(refreshNow());
    _timer = Timer.periodic(_refreshInterval, (_) => refreshNow());
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> refreshNow() async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_latitude&longitude=$_longitude'
        '&current=temperature_2m,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,'
        'precipitation_probability_max'
        '&hourly=temperature_2m,weather_code,precipitation_probability'
        '&forecast_days=7&timezone=auto',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      final current = body['current'] as Map<String, dynamic>;
      final temperature = (current['temperature_2m'] as num).toDouble();
      final code = (current['weather_code'] as num).toInt();
      snapshot.value = WeatherSnapshot(
        temperatureC: temperature,
        condition: WeatherCondition.fromWmoCode(code),
        fetchedAt: DateTime.now(),
      );

      final daily = body['daily'] as Map<String, dynamic>;
      final dates = daily['time'] as List;
      final codes = daily['weather_code'] as List;
      final maxTemps = daily['temperature_2m_max'] as List;
      final minTemps = daily['temperature_2m_min'] as List;
      final rainChances = daily['precipitation_probability_max'] as List;

      forecast.assignAll([
        for (var i = 0; i < dates.length; i++)
          WeatherDay(
            date: DateTime.parse(dates[i] as String),
            condition:
                WeatherCondition.fromWmoCode((codes[i] as num).toInt()),
            maxTempC: (maxTemps[i] as num).toDouble(),
            minTempC: (minTemps[i] as num).toDouble(),
            rainChance: (rainChances[i] as num? ?? 0).toInt(),
          ),
      ]);

      final hourlyBody = body['hourly'] as Map<String, dynamic>;
      final hourTimes = hourlyBody['time'] as List;
      final hourTemps = hourlyBody['temperature_2m'] as List;
      final hourCodes = hourlyBody['weather_code'] as List;
      final hourRainChances = hourlyBody['precipitation_probability'] as List;

      hourly.assignAll([
        for (var i = 0; i < hourTimes.length; i++)
          WeatherHour(
            time: DateTime.parse(hourTimes[i] as String),
            condition:
                WeatherCondition.fromWmoCode((hourCodes[i] as num).toInt()),
            temperatureC: (hourTemps[i] as num).toDouble(),
            rainChance: (hourRainChances[i] as num? ?? 0).toInt(),
          ),
      ]);
    } catch (_) {
      // Le réseau ou l'API peut être indisponible (ex. hors-ligne) : le
      // badge météo se contente de rester masqué, ça ne doit jamais
      // bloquer le fil.
    }
  }
}
