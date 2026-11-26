import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/models/dossier.dart';

Dossier dossier({
  List<String> steps = const [
    'Dossier réceptionné',
    'Phase de signature',
    'Disponible au retrait',
  ],
  int stepIndex = 0,
  DossierStatus status = DossierStatus.receptionne,
}) => Dossier(
  id: 'd',
  ownerUid: 'u',
  ownerName: 'Awa',
  trackingCode: 'ABC2345',
  structureUid: 'mairie',
  structureName: 'Mairie de Foumbot',
  title: 'Légalisation d’acte de naissance',
  status: status,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  steps: steps,
  stepIndex: stepIndex,
);

void main() {
  test('le dossier suit les étapes définies par la structure', () {
    final d = dossier();
    expect(d.currentLabel, 'Dossier réceptionné');
    final next = d.nextActions.firstWhere((a) => a.isStep);
    expect(next.label, 'Phase de signature');
    expect(next.stepIndex, 1);
    expect(next.status, DossierStatus.enCours);

    final d2 = dossier(stepIndex: 1, status: DossierStatus.enCours);
    expect(d2.currentLabel, 'Phase de signature');
    final last = d2.nextActions.firstWhere((a) => a.isStep);
    expect(last.label, 'Disponible au retrait');
    expect(last.status, DossierStatus.termine);
  });

  test('à la dernière étape : remise à la personne, plus d’étape suivante', () {
    final d = dossier(stepIndex: 2, status: DossierStatus.termine);
    expect(d.atLastStep, isTrue);
    expect(d.nextActions.any((a) => a.isStep), isFalse);
    expect(d.nextActions.map((a) => a.status), contains(DossierStatus.retire));
  });

  test('pièce manquante : on reprend à la même étape', () {
    final d = dossier(stepIndex: 1, status: DossierStatus.complementRequis);
    expect(d.currentLabel, DossierStatus.complementRequis.label);
    final resume = d.nextActions.first;
    expect(resume.stepIndex, 1);
    expect(resume.status, DossierStatus.enCours);
    expect(
      d.nextActions.where((a) => a.status == DossierStatus.complementRequis),
      isEmpty,
    );
  });

  test('un dossier clos ne propose plus rien', () {
    expect(dossier(status: DossierStatus.retire).nextActions, isEmpty);
    expect(dossier(status: DossierStatus.rejete).nextActions, isEmpty);
  });

  test(
    'sans étapes définies : étapes génériques, anciens dossiers lisibles',
    () {
      final d = dossier(steps: const [], status: DossierStatus.enCours);
      expect(d.steps, Dossier.defaultSteps);
      expect(d.currentStep, 1);
      expect(
        dossier(steps: const [], status: DossierStatus.termine).atLastStep,
        isTrue,
      );
    },
  );

  test('une étape hors bornes ne fait pas planter', () {
    expect(dossier(stepIndex: 9).currentStep, 2);
    expect(dossier(stepIndex: -3).currentStep, 0);
  });

  test('QR code : le guichet relit exactement le code', () {
    final payload = TrackingCode.qrPayload('ABC2345');
    expect(TrackingCode.fromScan(payload), 'ABC2345');
    expect(TrackingCode.fromScan('abc-2345'), 'ABC2345');
    expect(TrackingCode.fromScan('https://exemple.com'), isNull);
    expect(TrackingCode.fromScan('FOUMBOT-SUIVI:ABC0345'), isNull);
  });
}
