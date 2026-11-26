import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/report.dart';
import '../../routes/app_routes.dart';
import '../../services/moderation_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../utils/image_url.dart';

/// Dossier de la file de modération (`moderationQueue/{id}`), tel
/// qu'écrit par `onReportCreated`.
class ModerationEntry {
  ModerationEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc)
      : id = doc.id,
        targetType = doc.data()?['targetType'] as String? ?? '',
        targetPath = doc.data()?['targetPath'] as String? ?? '',
        ownerUid = doc.data()?['targetOwnerUid'] as String?,
        reportsCount = doc.data()?['reportsCount'] as int? ?? 0,
        priority = doc.data()?['priority'] as String? ?? 'normal',
        reasons = Map<String, dynamic>.from(
          doc.data()?['reasons'] as Map? ?? const {},
        ),
        snapshot = Map<String, dynamic>.from(
          doc.data()?['snapshot'] as Map? ?? const {},
        ),
        excerpt = doc.data()?['excerpt'] as String? ?? '',
        lastReportAt =
            (doc.data()?['lastReportAt'] as Timestamp?)?.toDate();

  final String id;
  final String targetType;
  final String targetPath;
  final String? ownerUid;
  final int reportsCount;
  final String priority;
  final Map<String, dynamic> reasons;

  /// Copie du contenu faite par le serveur au premier signalement.
  final Map<String, dynamic> snapshot;
  final String excerpt;
  final DateTime? lastReportAt;

  bool get isUrgent => priority == 'high';

  String get typeLabel => switch (targetType) {
        'post' => 'Publication',
        'comment' => 'Commentaire',
        'user' => 'Profil',
        'marketItem' => 'Annonce',
        'message' => 'Message privé',
        'status' => 'Statut',
        'live' => 'Live',
        _ => 'Contenu',
      };

  /// Motifs, du plus fréquent au moins fréquent, avec leur libellé.
  List<String> get reasonLabels {
    final entries = reasons.entries.toList()
      ..sort((a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0));
    return [
      for (final e in entries)
        '${ReportReason.values.firstWhereOrNull((r) => r.name == e.key)?.label ?? e.key} (${e.value})',
    ];
  }

  /// Texte à juger, lu d'abord dans la copie serveur, faute de quoi dans
  /// l'aperçu envoyé par l'app du signaleur.
  String get text {
    final isTextMessage = targetType != 'message' ||
        (snapshot['type'] as String? ?? 'text') == 'text';
    for (final key in ['text', 'body', 'title', 'description', 'displayName', 'bio']) {
      final v = snapshot[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final content = snapshot['content'];
    if (isTextMessage && content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    return excerpt.trim();
  }

  /// Première image du contenu, s'il en a une.
  String? get imageUrl {
    for (final key in ['imageUrl', 'photoUrl', 'thumbUrl']) {
      final v = snapshot[key];
      if (v is String && v.startsWith('http')) return v;
    }
    final urls = snapshot['imageUrls'];
    if (urls is List && urls.isNotEmpty && urls.first is String) {
      return urls.first as String;
    }
    if (targetType == 'message' && snapshot['type'] == 'image') {
      final c = snapshot['content'];
      if (c is String && c.startsWith('http')) return c;
    }
    return null;
  }
}

/// File de modération, réservée aux administrateurs (`admins/{uid}`).
///
/// Les dossiers ouverts arrivent en direct, les prioritaires en tête. Les
/// décisions passent par la fonction serveur `moderate`, qui revérifie le
/// rôle de l'appelant : cet écran n'est qu'une interface.
class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  final _busy = <String>{};

  Stream<List<ModerationEntry>> get _openEntries => FirebaseFirestore.instance
      .collection('moderationQueue')
      .where('status', isEqualTo: 'open')
      .orderBy('lastReportAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) {
        final list = snap.docs.map(ModerationEntry.fromDoc).toList();
        // Les urgents d'abord, puis le plus récent.
        list.sort((a, b) {
          if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
          return (b.lastReportAt ?? DateTime(0))
              .compareTo(a.lastReportAt ?? DateTime(0));
        });
        return list;
      });

  Future<void> _decide(ModerationEntry entry, String action) async {
    final (title, message, label) = switch (action) {
      'dismiss' => (
          'Rejeter les signalements ?',
          'Le contenu ne pose pas de problème. S\'il avait été masqué '
              'automatiquement, il sera remis en ligne.',
          'Rejeter',
        ),
      'remove' => (
          'Retirer ce contenu ?',
          'Il sera supprimé pour tout le monde. La copie reste dans le '
              'dossier de modération.',
          'Retirer',
        ),
      _ => (
          'Suspendre l\'auteur ?',
          'Son compte sera désactivé et ses sessions fermées : il ne '
              'pourra plus se connecter. Réversible depuis la console '
              'Firebase (Authentication).',
          'Suspendre',
        ),
    };
    final ok = await confirmAction(
      title: title,
      message: message,
      confirmLabel: label,
      destructive: action != 'dismiss',
    );
    if (!ok) return;

    setState(() => _busy.add(entry.id));
    try {
      await FirebaseFunctions.instance
          .httpsCallable('moderate')
          .call<Map<String, dynamic>>({'entryId': entry.id, 'action': action});
      Get.snackbar('Dossier traité', '${entry.typeLabel} : $label.');
    } on FirebaseFunctionsException catch (e) {
      Get.snackbar('Action impossible', e.message ?? e.code);
    } catch (e) {
      Get.snackbar('Action impossible', '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    final moderation = Get.find<ModerationService>();

    return Obx(() {
      final isDark = theme.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(isDark: isDark, title: 'Modération'),
        body: !moderation.isAdmin.value
            ? _Message(
                icon: Icons.lock_outline,
                text: 'Cet écran est réservé aux administrateurs.',
                muted: muted,
              )
            : StreamBuilder<List<ModerationEntry>>(
                stream: _openEntries,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _Message(
                      icon: Icons.error_outline,
                      text: 'Impossible de charger la file.\n${snap.error}',
                      muted: muted,
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: FoumbotLoader());
                  }
                  final entries = snap.data!;
                  if (entries.isEmpty) {
                    return _Message(
                      icon: Icons.verified_user_outlined,
                      text: 'Aucun signalement en attente.',
                      muted: muted,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _EntryCard(
                      entry: entries[i],
                      isDark: isDark,
                      ink: ink,
                      muted: muted,
                      busy: _busy.contains(entries[i].id),
                      onDecide: (action) => _decide(entries[i], action),
                    ),
                  );
                },
              ),
      );
    });
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, required this.muted});

  final IconData icon;
  final String text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: muted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.isDark,
    required this.ink,
    required this.muted,
    required this.busy,
    required this.onDecide,
  });

  final ModerationEntry entry;
  final bool isDark;
  final Color ink;
  final Color muted;
  final bool busy;
  final void Function(String action) onDecide;

  @override
  Widget build(BuildContext context) {
    final date = entry.lastReportAt;
    final image = entry.imageUrl;
    final text = entry.text;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.isUrgent
              ? AppColors.danger.withValues(alpha: 0.6)
              : AppColors.orange.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (entry.isUrgent) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'PRIORITAIRE',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  entry.typeLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              Text(
                '${entry.reportsCount} signalement'
                '${entry.reportsCount > 1 ? 's' : ''}',
                style: GoogleFonts.manrope(fontSize: 12, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entry.reasonLabels.join(' · '),
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.orange,
            ),
          ),
          if (date != null)
            Text(
              'Dernier signalement : '
              '${DateFormat("d MMM 'à' HH:mm", 'fr_FR').format(date)}',
              style: GoogleFonts.manrope(fontSize: 12, color: muted),
            ),
          const SizedBox(height: 10),
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: displayImageUrl(image),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (text.isNotEmpty)
            Text(
              text,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 14, color: ink),
            )
          else
            Text(
              'Contenu indisponible (supprimé avant le signalement).',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: muted,
              ),
            ),
          if (entry.ownerUid != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: muted,
              ),
              onPressed: () =>
                  Get.toNamed(AppRoutes.userProfile, arguments: entry.ownerUid),
              icon: const Icon(Icons.person_outline, size: 16),
              label: Text(
                'Voir le profil de l\'auteur',
                style: GoogleFonts.manrope(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (busy)
            const Center(child: FoumbotLoader())
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onDecide('dismiss'),
                  child: const Text('Rejeter'),
                ),
                if (entry.targetType != 'user')
                  FilledButton.tonal(
                    onPressed: () => onDecide('remove'),
                    child: const Text('Retirer le contenu'),
                  ),
                if (entry.ownerUid != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: () => onDecide('suspend'),
                    child: const Text('Suspendre l\'auteur'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
