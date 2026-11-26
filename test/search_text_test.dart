import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/search_text.dart';

void main() {
  test('l’index de l’app et celui du serveur sont identiques', () {
    // Généré par functions/search_index.js : si l'un des deux côtés
    // change sa normalisation, ce test casse.
    final fixtures =
        jsonDecode(
              File('test/fixtures_search_prefixes.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    fixtures.forEach((text, expected) {
      expect(
        searchPrefixesOf([text]).toSet(),
        (expected as List).cast<String>().toSet(),
        reason: text,
      );
    });
  });

  test('accents et majuscules confondus', () {
    expect(normalizeForSearch('École Œuvre ÇA'), 'ecole oeuvre ca');
    expect(searchQueryTokens('  Marché  de Foumbot '), [
      'marche',
      'de',
      'foumbot',
    ]);
  });

  test('début de mot, mot entier, fautes de frappe', () {
    expect(tokenMatch('abdel', 'abdel'), 3);
    expect(tokenMatch('abd', 'abdelkader'), 2);
    expect(tokenMatch('abdle', 'abdel'), 1); // lettres inversées
    expect(tokenMatch('fombot', 'foumbot'), 1); // lettre oubliée
    expect(tokenMatch('foumbbot', 'foumbot'), 1); // lettre en trop
    expect(tokenMatch('xyz', 'abdel'), 0);
    expect(tokenMatch('ab', 'ba'), 0); // trop court pour tolérer
  });

  test('tous les mots de la saisie doivent correspondre', () {
    expect(matchScore(['mairie', 'fou'], 'Mairie de Foumbot'), greaterThan(0));
    expect(matchScore(['mairie', 'paris'], 'Mairie de Foumbot'), 0);
  });

  test('un nom qui commence par la saisie passe devant', () {
    expect(
      matchScore(['abdel'], 'Abdel Ngapout'),
      greaterThan(matchScore(['abdel'], 'Sultan Abdel')),
    );
    expect(
      matchScore(['abdel'], 'Abdel'),
      greaterThan(matchScore(['abdel'], 'Abdelkader')),
    );
  });
}
