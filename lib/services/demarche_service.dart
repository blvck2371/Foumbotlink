import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/demarche.dart';

/// Les démarches publiées par les structures (`demarches/{id}`).
///
/// Tout est servi en écoute temps réel : une structure qui corrige un
/// tarif au guichet doit voir le changement apparaître sur le téléphone
/// des habitants sans que personne rafraîchisse quoi que ce soit.
class DemarcheService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _ref =>
      _db.collection('demarches');

  /// Le catalogue public, toutes structures confondues.
  ///
  /// Trié côté client : la liste est petite (quelques dizaines
  /// d'entrées), et trier ici évite d'imposer un index composite de plus
  /// pour un gain nul à cette échelle.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchAll({
    required void Function(List<Demarche>) onData,
    void Function(Object error)? onError,
  }) {
    return _ref.snapshots().listen(
      (snap) => onData(_sorted(snap)),
      onError: (Object e) {
        developer.log('watchAll', name: 'DemarcheService', error: e);
        onError?.call(e);
      },
    );
  }

  /// Les démarches d'une structure — sa propre liste de gestion.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchByStructure({
    required String structureUid,
    required void Function(List<Demarche>) onData,
    void Function(Object error)? onError,
  }) {
    return _ref
        .where('structureUid', isEqualTo: structureUid)
        .snapshots()
        .listen(
          (snap) => onData(_sorted(snap)),
          onError: (Object e) {
            developer.log(
              'watchByStructure',
              name: 'DemarcheService',
              error: e,
            );
            onError?.call(e);
          },
        );
  }

  static List<Demarche> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(Demarche.fromDoc).toList();
    list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  Future<String> create({
    required String structureUid,
    required String structureName,
    required DemarcheCategory category,
    required String title,
    required String description,
    required List<String> documents,
    required String lieu,
    required String cout,
    required String delai,
    required List<String> etapes,
    int? echeanceJours,
    String? echeanceDepuis,
  }) async {
    final doc = _ref.doc();
    final echeance =
        (echeanceJours ?? 0) > 0 && (echeanceDepuis ?? '').trim().isNotEmpty;
    await doc.set({
      'structureUid': structureUid,
      'structureName': structureName,
      'category': category.name,
      'title': title.trim(),
      'description': description.trim(),
      'documents': documents,
      'lieu': lieu.trim(),
      'cout': cout.trim(),
      'delai': delai.trim(),
      'etapes': etapes,
      if (echeance) 'echeanceJours': echeanceJours,
      if (echeance) 'echeanceDepuis': echeanceDepuis!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// `structureUid` n'est jamais réécrit : une démarche ne change pas de
  /// propriétaire, et les règles refuseraient de toute façon.
  Future<void> update(Demarche demarche) async {
    await _ref.doc(demarche.id).update({
      'structureName': demarche.structureName,
      'category': demarche.category.name,
      'title': demarche.title.trim(),
      'description': demarche.description.trim(),
      'documents': demarche.documents,
      'lieu': demarche.lieu.trim(),
      'cout': demarche.cout.trim(),
      'delai': demarche.delai.trim(),
      'etapes': demarche.etapes,
      // Délai retiré par la structure : le champ disparaît, et les rappels
      // des habitants avec (voir `DemarcheCompanion.sync`).
      'echeanceJours': demarche.hasEcheance
          ? demarche.echeanceJours
          : FieldValue.delete(),
      'echeanceDepuis': demarche.hasEcheance
          ? demarche.echeanceDepuis!.trim()
          : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _ref.doc(id).delete();
}
