import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/demarche.dart';
import '../models/search_text.dart';
import 'local_notifications_service.dart';

/// Une échéance suivie par l'habitant : une démarche dont la structure a
/// fixé un délai, et la date de l'événement qu'il a saisie.
///
/// Le délai et les libellés sont une **copie** de ce que publie la
/// structure, rafraîchie à chaque chargement du catalogue (voir
/// [DemarcheCompanion.sync]) : l'échéance reste lisible hors ligne, et
/// suit les mises à jour de la structure.
class SavedDeadline {
  const SavedDeadline({
    required this.demarcheId,
    required this.title,
    required this.structureName,
    required this.days,
    required this.since,
    required this.date,
  });

  final String demarcheId;
  final String title;
  final String structureName;

  /// Délai fixé par la structure, en jours.
  final int days;

  /// « la naissance de l'enfant » — à partir de quoi court le délai.
  final String since;

  /// Date de l'événement, à minuit.
  final DateTime date;

  /// Dernier jour du délai.
  DateTime get dueDate => date.add(Duration(days: days));

  /// Jours restants à partir d'aujourd'hui (négatif une fois passé).
  int daysLeft([DateTime? now]) =>
      dueDate.difference(_day(now ?? DateTime.now())).inDays;

  SavedDeadline copyFrom(Demarche d) => SavedDeadline(
    demarcheId: demarcheId,
    title: d.title,
    structureName: d.structureName,
    days: d.echeanceJours!,
    since: d.echeanceDepuis!,
    date: date,
  );

  Map<String, dynamic> toJson() => {
    'id': demarcheId,
    'title': title,
    'structure': structureName,
    'days': days,
    'since': since,
    'date': date.toIso8601String(),
  };

  static SavedDeadline fromJson(Map<String, dynamic> m) => SavedDeadline(
    demarcheId: m['id'] as String,
    title: m['title'] as String,
    structureName: m['structure'] as String? ?? '',
    days: (m['days'] as num).toInt(),
    since: m['since'] as String? ?? '',
    date: DateTime.parse(m['date'] as String),
  );
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ce qui aide la personne à mener ses démarches, gardé sur l'appareil :
///
/// - la **checklist** des pièces déjà réunies pour chaque démarche ;
/// - les **échéances** suivies, quand la structure a fixé un délai à sa
///   démarche, avec des rappels programmés même app fermée.
///
/// Rien ne part sur le serveur : ce sont des aide-mémoire personnels.
/// La checklist est propre à **une** démarche d'**une** structure (son
/// identifiant) : deux structures peuvent proposer une démarche du même
/// nom avec des pièces différentes.
class DemarcheCompanion extends GetxService {
  static const _checksKey = 'demarches.checklist';
  static const _deadlinesKey = 'demarches.deadlines.v2';

  /// identifiant de la démarche → pièces cochées (normalisées).
  final checks = <String, Set<String>>{}.obs;
  final deadlines = <SavedDeadline>[].obs;

  SharedPreferences? _prefs;

  Future<DemarcheCompanion> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs!.getString(_checksKey);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          checks[k] = (v as List).cast<String>().toSet();
        });
      }
      final dl = _prefs!.getString(_deadlinesKey);
      if (dl != null) {
        for (final e in jsonDecode(dl) as List) {
          deadlines.add(SavedDeadline.fromJson(e as Map<String, dynamic>));
        }
      }
    } catch (_) {
      // Données illisibles : on repart de zéro plutôt que de bloquer.
      checks.clear();
      deadlines.clear();
    }
    return this;
  }

  static String _key(String text) => normalizeForSearch(text.trim());

  // ---------------------------------------------------------------------
  // Checklist
  // ---------------------------------------------------------------------

  bool isChecked(Demarche d, String document) =>
      checks[d.id]?.contains(_key(document)) ?? false;

  void toggle(Demarche d, String document) {
    final k = d.id;
    final set = {...?checks[k]};
    final doc = _key(document);
    if (!set.remove(doc)) set.add(doc);
    if (set.isEmpty) {
      checks.remove(k);
    } else {
      checks[k] = set;
    }
    _saveChecks();
  }

  void resetChecklist(Demarche d) {
    checks.remove(d.id);
    _saveChecks();
  }

  /// Pièces réunies sur le total — seules comptent celles qui figurent
  /// encore dans la démarche (la structure a pu modifier la liste).
  ({int done, int total}) progress(Demarche d) {
    final set = checks[d.id] ?? const <String>{};
    final done = d.documents.where((doc) => set.contains(_key(doc))).length;
    return (done: done, total: d.documents.length);
  }

  void _saveChecks() {
    unawaited(
      _prefs?.setString(
        _checksKey,
        jsonEncode({for (final e in checks.entries) e.key: e.value.toList()}),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Échéances
  // ---------------------------------------------------------------------

  SavedDeadline? deadlineFor(Demarche d) =>
      deadlines.firstWhereOrNull((e) => e.demarcheId == d.id);

  Future<void> setDeadline(Demarche d, DateTime date) async {
    if (!d.hasEcheance) return;
    await removeDeadline(d.id, save: false);
    final saved = SavedDeadline(
      demarcheId: d.id,
      title: d.title,
      structureName: d.structureName,
      days: d.echeanceJours!,
      since: d.echeanceDepuis!.trim(),
      date: _day(date),
    );
    deadlines.add(saved);
    _sortAndSave();
    await _schedule(saved);
  }

  Future<void> removeDeadline(String demarcheId, {bool save = true}) async {
    deadlines.removeWhere((e) => e.demarcheId == demarcheId);
    if (save) _sortAndSave();
    await _cancel(demarcheId);
  }

  /// Recale les échéances sur les démarches publiées : la structure a pu
  /// changer le délai ou l'intitulé (les rappels sont reprogrammés), le
  /// retirer, ou supprimer la démarche (l'échéance disparaît alors avec
  /// ses rappels). À n'appeler qu'avec un catalogue **complet** chargé du
  /// serveur — jamais sur une erreur de chargement.
  Future<void> sync(List<Demarche> published) async {
    if (deadlines.isEmpty) return;
    final byId = {for (final d in published) d.id: d};
    var changed = false;
    for (final saved in deadlines.toList()) {
      final d = byId[saved.demarcheId];
      if (d == null || !d.hasEcheance) {
        deadlines.remove(saved);
        await _cancel(saved.demarcheId);
        changed = true;
        continue;
      }
      final fresh = saved.copyFrom(d);
      if (fresh.days != saved.days ||
          fresh.title != saved.title ||
          fresh.since != saved.since ||
          fresh.structureName != saved.structureName) {
        deadlines[deadlines.indexOf(saved)] = fresh;
        await _cancel(saved.demarcheId);
        await _schedule(fresh);
        changed = true;
      }
    }
    if (changed) _sortAndSave();
  }

  void _sortAndSave() {
    deadlines.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    unawaited(
      _prefs?.setString(
        _deadlinesKey,
        jsonEncode([for (final d in deadlines) d.toJson()]),
      ),
    );
  }

  /// Rappels, en jours avant l'échéance — ceux qui tiennent dans le délai.
  static List<int> remindersFor(int days) => [
    for (final before in const [30, 14, 7, 3, 0])
      if (before < days) before,
  ];

  /// Identifiant de notification stable pour une démarche et un rappel
  /// (hachage FNV-1a : `String.hashCode` peut changer d'une exécution à
  /// l'autre, et il faut retrouver ses rappels pour les annuler).
  static int _notifId(String demarcheId, int i) {
    var h = 0x811c9dc5;
    for (final c in demarcheId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return 100000 + (h % 100000) * 8 + i;
  }

  LocalNotificationsService? get _notifs =>
      Get.isRegistered<LocalNotificationsService>()
      ? Get.find<LocalNotificationsService>()
      : null;

  Future<void> _schedule(SavedDeadline d) async {
    final notifs = _notifs;
    if (notifs == null) return;
    final reminders = remindersFor(d.days);
    for (var i = 0; i < reminders.length; i++) {
      final before = reminders[i];
      final day = d.dueDate.subtract(Duration(days: before));
      // 9 h : ni la nuit, ni trop tard pour se rendre au guichet.
      final at = DateTime(day.year, day.month, day.day, 9);
      if (at.isBefore(DateTime.now())) continue;
      await notifs.scheduleAt(
        id: _notifId(d.demarcheId, i),
        at: at,
        title: before == 0
            ? 'Dernier jour : ${d.title}'
            : '${d.title} : plus que $before jours',
        body: before == 0
            ? 'C’est aujourd’hui le dernier jour du délai fixé par '
                  '${d.structureName}.'
            : 'Délai fixé par ${d.structureName} : $before jours restants.',
        payload: const {'type': 'echeance'},
      );
    }
  }

  Future<void> _cancel(String demarcheId) async {
    final notifs = _notifs;
    if (notifs == null) return;
    for (var i = 0; i < 8; i++) {
      await notifs.cancel(_notifId(demarcheId, i));
    }
  }
}
