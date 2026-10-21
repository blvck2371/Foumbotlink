import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'capture_shield.dart';
import 'foumbot_loader.dart';

/// Visionneuse d'une **photo à vue unique**.
///
/// Volontairement distincte de `openPostImageViewer`, qui sert le fil et
/// le marché : celle-là zoome, se glisse d'une photo à l'autre et se
/// partage — autant de gestes qui n'ont pas leur place ici. Celle-ci ne
/// fait qu'une chose, et la retire dès qu'un enregistrement d'écran
/// commence (voir [CaptureShield]).
Future<void> openSealedImageViewer(
  BuildContext context, {
  required String imageUrl,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _SealedImageViewer(imageUrl: imageUrl),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _SealedImageViewer extends StatelessWidget {
  const _SealedImageViewer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.black.withValues(alpha: 0.96),
        body: Stack(
          children: [
            Positioned.fill(
              child: CaptureShield(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const Center(child: FoumbotLoader()),
                  errorWidget: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.whiteMuted,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close_rounded, color: AppColors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
