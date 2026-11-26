import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/dossier.dart';
import '../../theme/app_colors.dart';

/// Lecture du QR code de suivi d'un habitant, au guichet.
///
/// Rend le code lu (`Get.back(result: code)`) dès qu'un QR de suivi
/// valide passe devant la caméra ; un QR étranger est signalé sans fermer.
class TrackingCodeScanner extends StatefulWidget {
  const TrackingCodeScanner({super.key});

  /// Ouvre la caméra et rend le code lu, ou `null`.
  static Future<String?> open() async => await Get.to<String>(
    () => const TrackingCodeScanner(),
    fullscreenDialog: true,
  );

  @override
  State<TrackingCodeScanner> createState() => _TrackingCodeScannerState();
}

class _TrackingCodeScannerState extends State<TrackingCodeScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  String? _warning;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final code = TrackingCode.fromScan(raw);
      if (code != null) {
        _done = true;
        Get.back(result: code);
        return;
      }
    }
    setState(
      () => _warning =
          'Ce QR code n’est pas un code de suivi Foumbot Link. Demandez à '
          'la personne d’ouvrir « Suivre mes dossiers ».',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Scanner le code de suivi',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'L’accès à la caméra est refusé. Autorisez-le dans '
                            'les réglages, ou saisissez le code à la main.'
                      : 'La caméra n’a pas pu démarrer. Saisissez le code '
                            'à la main.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          // Cadre de visée.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.orange, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _warning ??
                    'Visez le QR code affiché dans « Suivre mes dossiers » '
                        'sur le téléphone de la personne.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: _warning == null ? Colors.white : AppColors.orange,
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
