import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/controllers/demarches_controller.dart';
import 'package:foumbotlik/models/demarche.dart';
import 'package:foumbotlik/services/demarche_companion.dart';
import 'package:shared_preferences/shared_preferences.dart';

Demarche published(
  String title, {
  String structure = 'mairie',
  String structureName = 'Mairie de Foumbot',
  List<String> docs = const ['CNI'],
  DemarcheCategory category = DemarcheCategory.etatCivil,
  int? jours,
  String? depuis,
}) => Demarche(
  id: '$structure/$title',
  structureUid: structure,
  structureName: structureName,
  category: category,
  title: title,
  description: '',
  documents: docs,
  lieu: 'Guichet',
  cout: 'Gratuit',
  delai: '24 h',
  etapes: const [],
  echeanceJours: jours,
  echeanceDepuis: depuis,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le catalogue est regroupé par structure, sans rien d’inventé', () {
    final groups = DemarchesController.groupByStructure([
      published('Acte de naissance'),
      published(
        'Abonnement électricité',
        structure: 'eneo',
        structureName: 'Agence d’électricité',
        category: DemarcheCategory.services,
      ),
      published('Acte de décès'),
    ]);
    expect(groups.map((g) => g.name), [
      'Agence d’électricité',
      'Mairie de Foumbot',
    ]);
    expect(groups.last.demarches.map((d) => d.title), [
      'Acte de décès',
      'Acte de naissance',
    ]);
    expect(DemarchesController.groupByStructure(const []), isEmpty);
  });

  test('deux structures, même intitulé : deux checklists distinctes', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await DemarcheCompanion().init();
    final a = published('Acte de naissance', docs: ['CNI', 'Certificat']);
    final b = published(
      'Acte de naissance',
      structure: 'mairie2',
      docs: ['CNI', 'Photo'],
    );
    c.toggle(a, 'CNI');
    expect(c.progress(a), (done: 1, total: 2));
    expect(c.progress(b), (done: 0, total: 2));

    final reloaded = await DemarcheCompanion().init();
    expect(reloaded.isChecked(a, 'cni'), isTrue);
  });

  test('échéance : le délai vient de la structure, jours restants exacts',
      () async {
    SharedPreferences.setMockInitialValues({});
    final c = await DemarcheCompanion().init();
    final d = published(
      'Déclaration de naissance',
      jours: 90,
      depuis: 'la naissance de l’enfant',
    );
    await c.setDeadline(d, DateTime(2026, 11, 1, 18));
    final saved = c.deadlineFor(d)!;
    expect(saved.dueDate, DateTime(2027, 1, 30));
    expect(saved.daysLeft(DateTime(2026, 11, 1, 18)), 90);
    expect(saved.daysLeft(DateTime(2027, 1, 30)), 0);
    expect(saved.daysLeft(DateTime(2027, 2, 2)), lessThan(0));

    // Sans délai publié par la structure, rien n'est suivi.
    await c.setDeadline(published('Légalisation'), DateTime(2026, 11, 1));
    expect(c.deadlines, hasLength(1));
  });

  test('la structure change son délai : l’échéance suit', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await DemarcheCompanion().init();
    final v1 = published('Déclaration', jours: 90, depuis: 'la naissance');
    await c.setDeadline(v1, DateTime(2026, 11, 1));

    await c.sync([v1.copyWith(echeanceJours: 60)]);
    expect(c.deadlines.single.days, 60);
    expect(c.deadlines.single.dueDate, DateTime(2026, 12, 31));

    // Délai retiré, ou démarche supprimée : l'échéance disparaît.
    await c.sync([v1.copyWith(clearEcheance: true)]);
    expect(c.deadlines, isEmpty);

    await c.setDeadline(v1, DateTime(2026, 11, 1));
    await c.sync(const []);
    expect(c.deadlines, isEmpty);
  });

  test('les échéances sont retenues d’une ouverture à l’autre', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await DemarcheCompanion().init();
    await a.setDeadline(
      published('Déclaration de décès', jours: 30, depuis: 'le décès'),
      DateTime(2026, 11, 20, 15),
    );
    final b = await DemarcheCompanion().init();
    expect(b.deadlines, hasLength(1));
    expect(b.deadlines.single.dueDate, DateTime(2026, 12, 20));
    expect(b.deadlines.single.since, 'le décès');
  });

  test('rappels : seulement ceux qui tiennent dans le délai', () {
    expect(DemarcheCompanion.remindersFor(90), [30, 14, 7, 3, 0]);
    expect(DemarcheCompanion.remindersFor(10), [7, 3, 0]);
    expect(DemarcheCompanion.remindersFor(1), [0]);
  });

  test('un délai incomplet n’est pas un délai', () {
    expect(published('A', jours: 90).hasEcheance, isFalse);
    expect(published('A', depuis: 'la naissance').hasEcheance, isFalse);
    expect(published('A', jours: 0, depuis: 'x').hasEcheance, isFalse);
    expect(published('A', jours: 5, depuis: 'x').hasEcheance, isTrue);
  });

  test('catégorie inconnue : rangée dans « Autres »', () {
    expect(DemarcheCategory.values.last, DemarcheCategory.autre);
  });
}
