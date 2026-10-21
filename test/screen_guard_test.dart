import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foumbotlik/services/screen_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('foumbot/screen_guard');
  late List<String> calls;

  void respondWith(Future<Object?>? Function(MethodCall)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call.method);
          return handler?.call(call) ?? Future<Object?>.value();
        });
  }

  setUp(() {
    calls = <String>[];
    respondWith(null);
  });

  tearDown(() async {
    // Chaque test doit reposer la protection : sinon le compteur, qui est
    // statique, fuirait d'un test à l'autre.
    expect(calls.where((c) => c == 'secure').length, lessThanOrEqualTo(1));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('une prise isolée verrouille puis déverrouille', () async {
    await ScreenGuard.acquire();
    expect(calls, ['secure']);
    await ScreenGuard.release();
    expect(calls, ['secure', 'unsecure']);
  });

  test('deux prises imbriquées ne verrouillent qu’une fois', () async {
    await ScreenGuard.acquire();
    await ScreenGuard.acquire();
    expect(calls, ['secure']);

    // La première libération ne lève rien : l'autre contenu est encore
    // à l'écran.
    await ScreenGuard.release();
    expect(calls, ['secure']);

    await ScreenGuard.release();
    expect(calls, ['secure', 'unsecure']);
  });

  test('une libération de trop ne déverrouille pas par accident', () async {
    await ScreenGuard.release();
    expect(calls, isEmpty);

    await ScreenGuard.acquire();
    await ScreenGuard.release();
    await ScreenGuard.release();
    expect(calls, ['secure', 'unsecure']);
  });

  test('guard rend la protection même si l’affichage échoue', () async {
    await expectLater(
      ScreenGuard.guard<void>(() async => throw StateError('visionneuse')),
      throwsStateError,
    );
    expect(calls, ['secure', 'unsecure']);
  });

  test('une plateforme sans implémentation ne fait pas échouer', () async {
    respondWith((_) => throw MissingPluginException('non implémenté'));

    await ScreenGuard.acquire();
    await ScreenGuard.release();
    expect(calls, ['secure', 'unsecure']);
  });

  test('une erreur de la plateforme est avalée, pas propagée', () async {
    respondWith(
      (_) => throw PlatformException(code: 'no_activity'),
    );

    await ScreenGuard.acquire();
    await ScreenGuard.release();
    expect(calls, ['secure', 'unsecure']);
  });
  group('signaux de capture (iOS)', () {
    /// Simule ce que le natif envoie à Dart.
    Future<void> fromNative(String method, [Object? args]) async {
      await TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            'foumbot/screen_guard',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
    }

    test('un enregistrement en cours lève puis retombe le drapeau', () async {
      await ScreenGuard.acquire();
      expect(ScreenGuard.isCaptured.value, false);

      await fromNative('captured', true);
      expect(ScreenGuard.isCaptured.value, true);

      await fromNative('captured', false);
      expect(ScreenGuard.isCaptured.value, false);

      await ScreenGuard.release();
    });

    test('rendre la protection remet le drapeau à plat', () async {
      await ScreenGuard.acquire();
      await fromNative('captured', true);
      expect(ScreenGuard.isCaptured.value, true);

      // Même si le natif ne dit rien en s'arrêtant, l'état ne doit pas
      // rester coincé : le prochain affichage démarrerait masqué.
      await ScreenGuard.release();
      expect(ScreenGuard.isCaptured.value, false);
    });

    test('une capture d’écran est diffusée à qui écoute', () async {
      await ScreenGuard.acquire();
      final seen = <void>[];
      final sub = ScreenGuard.onScreenshot.listen(seen.add);

      await fromNative('screenshot');
      await fromNative('screenshot');
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await sub.cancel();
      await ScreenGuard.release();
    });

    test('personne n’écoute : la capture ne fait pas échouer', () async {
      await ScreenGuard.acquire();
      await fromNative('screenshot');
      await ScreenGuard.release();
      expect(ScreenGuard.isCaptured.value, false);
    });
  });

}
