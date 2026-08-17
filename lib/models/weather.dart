/// Condition météo simplifiée, dérivée du code WMO renvoyé par l'API.
enum WeatherCondition {
  sunny,
  cloudy,
  rain,
  storm,
  fog,
  snow,
  unknown;

  /// Mappe un code météo WMO (norme utilisée par Open-Meteo) vers une
  /// condition simplifiée suffisante pour choisir une icône.
  static WeatherCondition fromWmoCode(int code) {
    if (code == 0 || code == 1) return WeatherCondition.sunny;
    if (code == 2 || code == 3) return WeatherCondition.cloudy;
    if (code == 45 || code == 48) return WeatherCondition.fog;
    if (code == 95 || code == 96 || code == 99) return WeatherCondition.storm;
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return WeatherCondition.snow;
    }
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      return WeatherCondition.rain;
    }
    return WeatherCondition.unknown;
  }

  /// Nom en langage courant — pas de jargon météo.
  String get label => switch (this) {
        WeatherCondition.sunny => 'Ensoleillé',
        WeatherCondition.cloudy => 'Nuageux',
        WeatherCondition.rain => 'Pluvieux',
        WeatherCondition.storm => 'Orageux',
        WeatherCondition.fog => 'Brumeux',
        WeatherCondition.snow => 'Neigeux',
        WeatherCondition.unknown => 'Variable',
      };

  /// Conseil pratique en une phrase simple, pensé pour quelqu'un qui ne
  /// sait pas interpréter une météo classique.
  String get advice => switch (this) {
        WeatherCondition.sunny => 'Beau temps toute la journée, profitez-en',
        WeatherCondition.cloudy => 'Ciel couvert mais temps sec',
        WeatherCondition.rain => 'Pensez à prendre un parapluie',
        WeatherCondition.storm => 'Orages possibles, restez à l’abri',
        WeatherCondition.fog => 'Visibilité réduite, soyez prudent·e',
        WeatherCondition.snow => 'Températures froides, couvrez-vous bien',
        WeatherCondition.unknown => 'Temps changeant, vérifiez avant de sortir',
      };
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureC,
    required this.condition,
    required this.fetchedAt,
  });

  final double temperatureC;
  final WeatherCondition condition;
  final DateTime fetchedAt;

  int get roundedTemperature => temperatureC.round();
}

/// Prévision d'une journée, pour l'écran "météo de la semaine".
class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.condition,
    required this.maxTempC,
    required this.minTempC,
    required this.rainChance,
  });

  final DateTime date;
  final WeatherCondition condition;
  final double maxTempC;
  final double minTempC;
  /// Probabilité de pluie ce jour-là, en pourcentage (0-100).
  final int rainChance;

  int get roundedMax => maxTempC.round();
  int get roundedMin => minTempC.round();
}

/// Prévision d'une heure précise — sert à montrer à quel moment de la
/// journée il pleut ou fait beau, pas seulement un résumé de la journée.
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.condition,
    required this.temperatureC,
    required this.rainChance,
  });

  final DateTime time;
  final WeatherCondition condition;
  final double temperatureC;
  final int rainChance;

  int get roundedTemperature => temperatureC.round();
}
