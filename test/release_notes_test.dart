import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Codemagic envoie `release_notes_fr-FR.txt` à Google Play avec chaque
/// version (rubrique « Nouveautés »). Le Play Store refuse plus de 500
/// caractères : mieux vaut l'apprendre ici qu'après vingt minutes de build.
void main() {
  test('notes de version fr-FR présentes et sous la limite du Play Store', () {
    final file = File('release_notes_fr-FR.txt');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'release_notes_fr-FR.txt manquant',
    );
    final text = file.readAsStringSync().trim();
    expect(text, isNotEmpty);
    // Google compte les caractères (un emoji en vaut deux), pas les octets.
    expect(
      text.length,
      lessThanOrEqualTo(500),
      reason: 'Notes de version trop longues : ${text.length}/500 caractères',
    );
  });
}
