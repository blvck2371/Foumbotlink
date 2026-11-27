import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/utils/feed_cache_manager.dart';

/// Réponse dont le contenu envoie un morceau puis cale pour de bon —
/// ce que fait une photo sur une connexion faible.
class _StalledResponse implements FileServiceResponse {
  @override
  Stream<List<int>> get content {
    final c = StreamController<List<int>>();
    c.add([1, 2, 3]);
    return c.stream; // jamais fermé
  }

  @override
  int? get contentLength => 1000;
  @override
  int get statusCode => 200;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
  @override
  String? get eTag => null;
  @override
  String get fileExtension => '.jpg';
}

class _Fake extends FileService {
  _Fake(this._response);
  final Future<FileServiceResponse> _response;
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) =>
      _response;
}

void main() {
  test('un téléchargement qui cale échoue au lieu de bloquer', () async {
    final service = TimeoutFileService(
      inner: _Fake(Future.value(_StalledResponse())),
      idle: const Duration(milliseconds: 50),
    );
    final response = await service.get('https://exemple/photo.jpg');
    await expectLater(
      response.content.toList(),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('un serveur qui ne répond pas échoue au lieu de bloquer', () async {
    final service = TimeoutFileService(
      inner: _Fake(Completer<FileServiceResponse>().future),
      connect: const Duration(milliseconds: 50),
    );
    await expectLater(
      service.get('https://exemple/photo.jpg'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
