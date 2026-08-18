import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'foumbot_loader.dart';

/// Affiche une scène Three.js chargée depuis les assets locaux.
class ThreeJsView extends StatefulWidget {
  const ThreeJsView({
    super.key,
    required this.scene,
    this.onReady,
  });

  /// Identifiant de scène : welcome | connect | explore | ready
  final String scene;
  final VoidCallback? onReady;

  @override
  State<ThreeJsView> createState() => _ThreeJsViewState();
}

class _ThreeJsViewState extends State<ThreeJsView> {
  WebViewController? _controller;
  bool _ready = false;
  String? _error;
  String? _servedScene;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<Directory> _prepareWebRoot() async {
    final root = await getTemporaryDirectory();
    final dir = Directory('${root.path}/foumbotlik_web');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    Future<void> writeAsset(String assetPath, String fileName) async {
      final data = await rootBundle.load(assetPath);
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    await Future.wait([
      writeAsset('assets/threejs/three.min.js', 'three.min.js'),
      writeAsset('assets/web/map_geometry.js', 'map_geometry.js'),
      writeAsset('assets/web/onboarding.html', 'onboarding.html'),
    ]);

    return dir;
  }

  Future<void> _bootstrap() async {
    try {
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) async {
              await _waitUntilReady(controller);
              await _applyScene(controller, widget.scene, force: true);
              if (!mounted) return;
              setState(() => _ready = true);
              widget.onReady?.call();
            },
            onWebResourceError: (error) {
              debugPrint('WebView error: ${error.description}');
            },
          ),
        );

      if (kIsWeb) {
        // Fallback web: inline minimal bootstrap is not supported here.
        await controller.loadHtmlString(
          '<html><body style="background:transparent"></body></html>',
        );
      } else {
        final dir = await _prepareWebRoot();
        final htmlPath = '${dir.path}/onboarding.html';
        await controller.loadFile(htmlPath);
      }

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _waitUntilReady(WebViewController controller) async {
    for (var i = 0; i < 40; i++) {
      try {
        final result = await controller.runJavaScriptReturningResult(
          'window.__FOUMBOTLIK_READY === true',
        );
        final ready = result == true || result == 'true' || result == 1;
        if (ready) return;
      } catch (_) {
        // JS pas encore prêt.
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _applyScene(
    WebViewController controller,
    String scene, {
    bool force = false,
  }) async {
    if (!force && _servedScene == scene) return;
    try {
      await controller.runJavaScriptReturningResult('''
(function () {
  try {
    if (typeof window.setOnboardingScene === 'function') {
      window.setOnboardingScene("$scene");
      return 'ok';
    }
    return 'missing';
  } catch (e) {
    return String(e);
  }
})()
''');
      _servedScene = scene;
    } catch (e) {
      // Ne pas faire planter Flutter si l'évaluation JS échoue.
      debugPrint('applyScene failed: $e');
    }
  }

  @override
  void didUpdateWidget(covariant ThreeJsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene && _controller != null && _ready) {
      _applyScene(_controller!, widget.scene);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Impossible de charger la scène 3D',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: FoumbotLoader());
    }

    return AnimatedOpacity(
      opacity: _ready ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      child: WebViewWidget(controller: _controller!),
    );
  }
}
