import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/market_item.dart';

class MarketService {
  static const pageSize = 10;

  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _marketRef =>
      _db.collection('market');

  DocumentSnapshot? _lastDoc;

  // -----------------------------------------------------------------------
  // Pages
  // -----------------------------------------------------------------------

  Future<List<MarketItem>> fetchPage({
    required int page,
    MarketCategory? category,
    MarketListingType? listingType,
    String? query,
    bool reset = false,
  }) async {
    if (reset || page == 0) _lastDoc = null;

    Query<Map<String, dynamic>> q =
        _marketRef.orderBy('createdAt', descending: true);

    if (category != null) {
      q = q.where('category', isEqualTo: category.name);
    }
    if (listingType != null) {
      q = q.where('listingType', isEqualTo: listingType.name);
    }

    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    final snapshot = await q.limit(pageSize).get();
    if (snapshot.docs.isNotEmpty) _lastDoc = snapshot.docs.last;

    var results = snapshot.docs
        .map((doc) => _itemFromDoc(doc))
        .toList();

    if (query != null && query.trim().isNotEmpty) {
      final low = query.trim().toLowerCase();
      results = results
          .where((e) =>
              e.title.toLowerCase().contains(low) ||
              e.description.toLowerCase().contains(low))
          .toList();
    }

    return results;
  }

  Future<MarketItem?> getById(String id) async {
    final doc = await _marketRef.doc(id).get();
    if (!doc.exists) return null;
    return _itemFromDoc(doc);
  }

  MarketItem _itemFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return MarketItem(
      id: doc.id,
      listingType: MarketListingType.values.firstWhere(
        (t) => t.name == d['listingType'],
        orElse: () => MarketListingType.vente,
      ),
      category: MarketCategory.values.firstWhere(
        (c) => c.name == d['category'],
        orElse: () => MarketCategory.divers,
      ),
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      price: d['price'] as int? ?? 0,
      negotiable: d['negotiable'] as bool? ?? false,
      priceOnRequest: d['priceOnRequest'] as bool? ?? false,
      condition: d['condition'] != null
          ? ItemCondition.values.firstWhere(
              (c) => c.name == d['condition'],
              orElse: () => ItemCondition.bonEtat,
            )
          : null,
      sellerUid: d['sellerUid'] as String? ?? '',
      sellerName: d['sellerName'] as String? ?? '',
      sellerPhone: d['sellerPhone'] as String? ?? '',
      location: d['location'] as String? ?? '',
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      imageUrls: List<String>.from(d['imageUrls'] ?? []),
    );
  }

  // -----------------------------------------------------------------------
  // Créer une annonce
  // -----------------------------------------------------------------------

  Future<MarketItem> createListing({
    required MarketListingType listingType,
    required MarketCategory category,
    required String title,
    required String sellerUid,
    required String sellerName,
    required String sellerPhone,
    required String location,
    String description = '',
    int price = 0,
    bool negotiable = false,
    bool priceOnRequest = false,
    ItemCondition? condition,
    List<String> localImagePaths = const [],
  }) async {
    final docRef = _marketRef.doc();

    final imageUrls = await _uploadImages(
      localImagePaths,
      'market/${docRef.id}',
    );

    final now = DateTime.now();
    await docRef.set({
      'listingType': listingType.name,
      'category': category.name,
      'title': title.trim(),
      'description': description.trim(),
      'price': price,
      'negotiable': negotiable,
      'priceOnRequest': priceOnRequest,
      'condition': condition?.name,
      'sellerUid': sellerUid,
      'sellerName': sellerName.trim(),
      'sellerPhone': sellerPhone.trim(),
      'location': location.trim(),
      'createdAt': Timestamp.fromDate(now),
      'imageUrls': imageUrls,
    });

    return MarketItem(
      id: docRef.id,
      listingType: listingType,
      category: category,
      title: title.trim(),
      description: description.trim(),
      price: price,
      negotiable: negotiable,
      priceOnRequest: priceOnRequest,
      condition: condition,
      sellerUid: sellerUid,
      sellerName: sellerName.trim(),
      sellerPhone: sellerPhone.trim(),
      location: location.trim(),
      createdAt: now,
      imageUrls: imageUrls,
    );
  }

  // -----------------------------------------------------------------------
  // Temps réel
  // -----------------------------------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchMarket({
    required void Function(MarketItem item) onAdded,
    required void Function(MarketItem item) onModified,
    required void Function(String id) onRemoved,
  }) {
    return _marketRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
            onAdded(_itemFromDoc(change.doc));
          case DocumentChangeType.modified:
            onModified(_itemFromDoc(change.doc));
          case DocumentChangeType.removed:
            onRemoved(change.doc.id);
        }
      }
    });
  }

  // -----------------------------------------------------------------------
  // Upload d'images
  // -----------------------------------------------------------------------

  Future<List<String>> _uploadImages(
    List<String> localPaths,
    String storagePath,
  ) async {
    final urls = <String>[];
    for (var i = 0; i < localPaths.length; i++) {
      final file = File(localPaths[i]);
      final ref = _storage.ref('$storagePath/$i.jpg');
      await ref.putFile(file);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}
