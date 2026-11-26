import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// La page Three.js de l'accueil dans un `iframe` (`srcdoc`, même
/// origine) : on peut y appeler `setOnboardingScene` directement, comme la
/// WebView mobile le fait par `runJavaScript`.
class ThreeJsWebFrame extends StatefulWidget {
  const ThreeJsWebFrame({
    super.key,
    required this.html,
    required this.scene,
    this.onReady,
  });

  /// Page complète, scripts compris (pas de fichiers à côté).
  final String html;
  final String scene;
  final VoidCallback? onReady;

  @override
  State<ThreeJsWebFrame> createState() => _ThreeJsWebFrameState();
}

class _ThreeJsWebFrameState extends State<ThreeJsWebFrame> {
  static int _seq = 0;
  late final String _viewType = 'foumbot-threejs-${_seq++}';
  late final web.HTMLIFrameElement _frame;
  Timer? _poll;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _frame = web.HTMLIFrameElement()
      ..setAttribute('srcdoc', widget.html)
      ..setAttribute('allowtransparency', 'true');
    _frame.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%'
      ..background = 'transparent';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _frame);
    // La page signale qu'elle est prête par `window.__FOUMBOTLIK_READY`.
    _poll = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (t.tick > 200) t.cancel(); // 20 s : on n'attend pas indéfiniment
      final win = _window;
      if (win == null) return;
      if (win.getProperty<JSAny?>('__FOUMBOTLIK_READY'.toJS)?.dartify() !=
          true) {
        return;
      }
      t.cancel();
      _ready = true;
      _applyScene();
      widget.onReady?.call();
    });
  }

  JSObject? get _window {
    final w = _frame.contentWindow;
    return w == null ? null : w as JSObject;
  }

  void _applyScene() {
    final win = _window;
    if (!_ready || win == null) return;
    try {
      if (win.has('setOnboardingScene')) {
        win.callMethod<JSAny?>('setOnboardingScene'.toJS, widget.scene.toJS);
      }
    } on Object catch (e) {
      debugPrint('applyScene (web) failed: $e');
    }
  }

  @override
  void didUpdateWidget(covariant ThreeJsWebFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene) _applyScene();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
