import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cache disque des photos du fil, avec des délais d'expiration.
///
/// Le gestionnaire par défaut n'en a aucun : sur une connexion faible, un
/// téléchargement qui cale ne se termine jamais. Pire, il est partagé —
/// toute nouvelle demande de la même photo (dont le bouton « recharger »)
/// se raccroche au téléchargement bloqué —, et il occupe l'un des dix
/// créneaux de téléchargement simultanés : quelques photos bloquées
/// suffisaient à figer toutes les autres.
///
/// Ici, un téléchargement qui ne reçoit plus rien pendant [_idle] échoue
/// proprement : le créneau se libère et la photo peut être redemandée.
class FeedCacheManager extends CacheManager with ImageCacheManager {
  FeedCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 400,
          fileService: TimeoutFileService(),
        ),
      );

  static const key = 'feedImagesV2';

  static final instance = FeedCacheManager._();
}

/// Délai pour recevoir les en-têtes de la réponse.
const _connect = Duration(seconds: 20);

/// Silence maximal entre deux morceaux de l'image en cours de réception.
const _idle = Duration(seconds: 20);

/// Téléchargement borné dans le temps — public pour être testé.
class TimeoutFileService extends FileService {
  TimeoutFileService({
    FileService? inner,
    this.connect = _connect,
    this.idle = _idle,
  }) : _inner = inner ?? HttpFileService();

  final FileService _inner;
  final Duration connect;
  final Duration idle;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _inner
        .get(url, headers: headers)
        .timeout(connect);
    return _TimeoutResponse(response, idle);
  }
}

class _TimeoutResponse implements FileServiceResponse {
  _TimeoutResponse(this._inner, this._idleLimit);

  final FileServiceResponse _inner;
  final Duration _idleLimit;

  @override
  Stream<List<int>> get content => _inner.content.timeout(
    _idleLimit,
    onTimeout: (sink) {
      sink.addError(
        TimeoutException('Photo : plus de données reçues', _idleLimit),
      );
      sink.close();
    },
  );

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  DateTime get validTill => _inner.validTill;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}
