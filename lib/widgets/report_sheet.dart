import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/report.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

/// Ce que l'utilisateur a choisi dans la feuille de signalement.
typedef ReportChoice = ({ReportReason reason, String details});

/// Feuille de signalement : choix du motif, puis précision facultative
/// (obligatoire pour « Autre »). Renvoie `null` si l'utilisateur ferme la
/// feuille sans aller au bout.
Future<ReportChoice?> showReportSheet({
  required String targetLabel,
}) {
  return Get.bottomSheet<ReportChoice>(
    _ReportSheet(targetLabel: targetLabel),
    isScrollControlled: true,
    ignoreSafeArea: false,
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.targetLabel});

  final String targetLabel;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _detailsCtrl = TextEditingController();

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final reason = _reason;
    if (reason == null) return false;
    // « Autre » n'apprend rien à la modération sans explication.
    if (reason == ReportReason.autre) {
      return _detailsCtrl.text.trim().length >= 5;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signaler ${widget.targetLabel}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Votre signalement reste anonyme. Les contenus les plus '
                    'signalés sont retirés automatiquement, puis examinés.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                children: [
                  RadioGroup<ReportReason>(
                    groupValue: _reason,
                    onChanged: (v) => setState(() => _reason = v),
                    child: Column(
                      children: [
                        for (final reason in ReportReason.values)
                          RadioListTile<ReportReason>(
                            value: reason,
                            activeColor: AppColors.orange,
                            dense: true,
                            title: Text(
                              reason.label,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: ink,
                              ),
                            ),
                            subtitle: Text(
                              reason.description,
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                color: muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_reason != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: TextField(
                        controller: _detailsCtrl,
                        onChanged: (_) => setState(() {}),
                        maxLines: 3,
                        maxLength: 500,
                        style: GoogleFonts.manrope(color: ink, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: _reason == ReportReason.autre
                              ? 'Expliquez ce qui pose problème (requis)'
                              : 'Précision (facultatif)',
                          hintStyle:
                              GoogleFonts.manrope(color: muted, fontSize: 13),
                          filled: true,
                          fillColor: isDark
                              ? AppColors.blackElevated
                              : AppColors.whiteSoft,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit
                      ? () => Get.back<ReportChoice>(
                            result: (
                              reason: _reason!,
                              details: _detailsCtrl.text.trim(),
                            ),
                          )
                      : null,
                  child: const Text('Envoyer le signalement'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
