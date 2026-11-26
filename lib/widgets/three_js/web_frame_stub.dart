import 'package:flutter/widgets.dart';

/// Remplaçant hors navigateur : jamais construit (voir `ThreeJsView`).
class ThreeJsWebFrame extends StatelessWidget {
  const ThreeJsWebFrame({
    super.key,
    required this.html,
    required this.scene,
    this.onReady,
  });

  final String html;
  final String scene;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
