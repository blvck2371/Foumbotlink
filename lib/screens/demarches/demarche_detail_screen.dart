import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/demarche.dart';
import '../../widgets/demarche_deadline.dart';
import '../../routes/app_routes.dart';
import '../../services/demarche_companion.dart';
import '../../widgets/verified_badge.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_app_bar.dart';

class DemarcheDetailScreen extends StatelessWidget {
  const DemarcheDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final demarche = Get.arguments as Demarche;
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: demarche.title),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      AppColors.black,
                      AppColors.blackSoft,
                      AppColors.blackElevated,
                    ]
                  : const [
                      AppColors.white,
                      AppColors.whiteSoft,
                      AppColors.white,
                    ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      demarche.category.icon,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            demarche.title,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            demarche.category.label,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ProposedBy(demarche: demarche, isDark: isDark),
              const SizedBox(height: 20),
              Text(
                demarche.description,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  height: 1.5,
                  color: muted,
                ),
              ),
              const SizedBox(height: 24),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Lieu',
                value: demarche.lieu,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.payments_outlined,
                label: 'Coût',
                value: demarche.cout,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.access_time,
                label: 'Délai',
                value: demarche.delai,
                ink: ink,
                muted: muted,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.directions_rounded,
                      label: 'Itinéraire',
                      onTap: () => _openMaps(demarche.lieu),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.share_rounded,
                      label: 'Partager la liste',
                      onTap: () => _share(demarche),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (demarche.hasEcheance) ...[
                DemarcheDeadlineBlock(demarche: demarche, isDark: isDark),
                const SizedBox(height: 28),
              ],
              _SectionTitle(
                icon: Icons.folder_outlined,
                title: 'Pièces à réunir',
                ink: ink,
              ),
              const SizedBox(height: 12),
              _Checklist(demarche: demarche, isDark: isDark),
              const SizedBox(height: 28),
              if (demarche.etapes.isNotEmpty) ...[
                _SectionTitle(
                  icon: Icons.timeline_rounded,
                  title: 'Les étapes de votre dossier',
                  ink: ink,
                ),
                const SizedBox(height: 6),
                Text(
                  'Une fois votre dossier déposé, ${demarche.structureName} '
                  'le fait passer par ces étapes. Montrez votre QR code '
                  '(« Suivre mes dossiers ») au guichet : vous serez '
                  'prévenu à chaque étape.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    height: 1.45,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < demarche.etapes.length; i++)
                _StepItem(
                  index: i + 1,
                  text: demarche.etapes[i],
                  isLast: i == demarche.etapes.length - 1,
                  ink: ink,
                  muted: muted,
                  isDark: isDark,
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.ink,
    required this.muted,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color ink;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.ink,
  });

  final IconData icon;
  final String title;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: AppColors.orange),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.index,
    required this.text,
    required this.isLast,
    required this.ink,
    required this.muted,
    required this.isDark,
  });

  final int index;
  final String text;
  final bool isLast;
  final Color ink;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.orange.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.orange,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.orange.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ouvre la carte sur le lieu de la démarche — dans l'app Google Maps si
/// elle est installée, sinon dans le navigateur.
Future<void> _openMaps(String lieu) async {
  final query = lieu.toLowerCase().contains('foumbot')
      ? '$lieu, Cameroun'
      : '$lieu, Foumbot, Cameroun';
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': query,
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    Get.snackbar('Carte indisponible', 'Impossible d’ouvrir la carte.');
  }
}

/// Partage la liste des pièces en texte — pratique pour l'envoyer sur
/// WhatsApp à la personne qui va au guichet, ou à soi-même.
Future<void> _share(Demarche d) async {
  final companion = Get.find<DemarcheCompanion>();
  final text = StringBuffer()
    ..writeln('📋 ${d.title}')
    ..writeln()
    ..writeln('Pièces à fournir :');
  for (final doc in d.documents) {
    text.writeln('${companion.isChecked(d, doc) ? '✅' : '⬜'} $doc');
  }
  text
    ..writeln()
    ..writeln('📍 ${d.lieu}')
    ..writeln('💰 ${d.cout}')
    ..writeln('⏱️ ${d.delai}')
    ..writeln()
    ..writeln('Via Foumbot Link');
  await SharePlus.instance.share(ShareParams(text: text.toString()));
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19),
      label: Text(
        label,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orange,
        side: BorderSide(color: AppColors.orange.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// La structure qui propose la démarche — une démarche n'existe que chez
/// elle, avec ses pièces et ses tarifs. Mène à son profil.
class _ProposedBy extends StatelessWidget {
  const _ProposedBy({required this.demarche, required this.isDark});

  final Demarche demarche;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Material(
      color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: demarche.structureUid.isEmpty
            ? null
            : () => Get.toNamed(
                AppRoutes.userProfile,
                arguments: demarche.structureUid,
                preventDuplicates: false,
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_rounded,
                size: 20,
                color: AppColors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Proposée par ',
                        style: GoogleFonts.manrope(fontSize: 13, color: muted),
                      ),
                      TextSpan(
                        text: demarche.structureName,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const VerifiedBadge(size: 15),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Liste des pièces à cocher au fur et à mesure qu'on les réunit, avec
/// la jauge d'avancement. Gardée sur l'appareil.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.demarche, required this.isDark});

  final Demarche demarche;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final companion = Get.find<DemarcheCompanion>();
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      final p = companion.progress(demarche);
      final complete = p.total > 0 && p.done == p.total;
      final color = complete ? AppColors.success : AppColors.orange;
      final missing = [
        for (final doc in demarche.documents)
          if (!companion.isChecked(demarche, doc)) doc,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cochez ce que vous avez déjà : vous saurez d’un coup d’œil ce '
            'qu’il reste à trouver.',
            style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: p.total == 0 ? 0 : p.done / p.total),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 8,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${p.done}/${p.total}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final doc in demarche.documents)
            _CheckRow(
              text: doc,
              checked: companion.isChecked(demarche, doc),
              onTap: () => companion.toggle(demarche, doc),
              ink: ink,
              muted: muted,
            ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(complete),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                complete
                    ? '🎉 Dossier complet ! Vous pouvez vous présenter au '
                          'guichet.'
                    : missing.length == 1
                    ? 'Il vous manque encore : ${missing.first}.'
                    : 'Il vous manque encore ${missing.length} pièces.',
                style: GoogleFonts.manrope(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: complete ? AppColors.success : ink,
                ),
              ),
            ),
          ),
          if (p.done > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => companion.resetChecklist(demarche),
                child: Text(
                  'Tout décocher',
                  style: GoogleFonts.manrope(color: muted, fontSize: 12.5),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.text,
    required this.checked,
    required this.onTap,
    required this.ink,
    required this.muted,
  });

  final String text;
  final bool checked;
  final VoidCallback onTap;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: checked ? AppColors.success : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: checked ? AppColors.success : muted,
                  width: 1.6,
                ),
              ),
              child: checked
                  ? const Icon(
                      Icons.check_rounded,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14.5,
                  height: 1.4,
                  color: checked ? muted : ink,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  decorationColor: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
