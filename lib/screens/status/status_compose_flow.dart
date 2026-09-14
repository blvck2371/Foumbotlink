import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/status_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import 'status_composer_screen.dart';

/// Le parcours complet « publier un statut » : choix du support, prise du
/// média, composition, publication.
///
/// Réuni ici parce qu'il part maintenant de deux endroits — la barre de
/// statuts de l'accueil et le profil. Le porter dans un contrôleur
/// obligerait chacun des deux à en dépendre ; c'est un enchaînement
/// d'écrans, il vit avec eux.
enum StatusSource { photoGallery, photoCamera, videoGallery, videoCamera, text }

/// Enchaîne tout et renvoie vrai si un statut a bien été publié.
Future<bool> composeAndPublishStatus(BuildContext context) async {
  final source = await askStatusSource();
  if (source == null) return false;

  String? imagePath;
  String? videoPath;
  switch (source) {
    case StatusSource.photoGallery:
      imagePath = await pickStatusPhoto(ImageSource.gallery);
    case StatusSource.photoCamera:
      imagePath = await pickStatusPhoto(ImageSource.camera);
    case StatusSource.videoGallery:
      videoPath = await pickStatusVideo(ImageSource.gallery);
    case StatusSource.videoCamera:
      videoPath = await pickStatusVideo(ImageSource.camera);
    case StatusSource.text:
      break;
  }

  // Sélecteur refermé sans rien choisir : on n'ouvre pas la composition
  // sur un média absent.
  if (source != StatusSource.text && imagePath == null && videoPath == null) {
    return false;
  }

  final draft = await Get.to<StatusDraft>(
    () => StatusComposerScreen(imagePath: imagePath, videoPath: videoPath),
  );
  if (draft == null) return false;
  return publishStatusDraft(draft);
}

/// Photo de statut : compressée à la sélection comme celles des
/// publications — un statut se regarde quelques secondes, il ne justifie
/// pas d'envoyer l'original de l'appareil photo.
Future<String?> pickStatusPhoto(ImageSource source) async {
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    return picked?.path;
  } catch (e) {
    developer.log('Photo de statut', name: 'StatusComposeFlow', error: e);
    Get.snackbar(
      'Photos indisponibles',
      'Impossible d’ouvrir la galerie.',
      duration: const Duration(seconds: 4),
    );
    return null;
  }
}

/// Vidéo de statut : bornée en durée à la prise de vue. Un statut se
/// regarde d'une traite — au-delà d'une demi-minute, ce n'est plus un
/// statut, et le fichier pèserait sur le forfait de qui le publie comme de
/// qui le regarde.
Future<String?> pickStatusVideo(ImageSource source) async {
  try {
    final picked = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 30),
    );
    return picked?.path;
  } catch (e) {
    developer.log('Vidéo de statut', name: 'StatusComposeFlow', error: e);
    Get.snackbar(
      'Vidéo indisponible',
      'Impossible d’ouvrir la vidéo choisie.',
      duration: const Duration(seconds: 4),
    );
    return null;
  }
}

/// Publie le statut composé. Le flux temps réel se recale tout seul
/// ensuite : rien n'est inséré à la main dans les listes.
Future<bool> publishStatusDraft(StatusDraft draft) async {
  final auth = Get.find<AuthService>();
  final me = Get.find<UserProfileService>().profile.value;
  if (draft.isEmpty || !auth.isSignedIn || me == null) return false;

  try {
    await Get.find<StatusService>().createStatus(
      authorUid: auth.uid,
      authorName: me.displayName,
      authorPhotoUrl: me.photoUrl,
      localImagePath: draft.imagePath,
      localVideoPath: draft.videoPath,
      text: draft.text,
      backgroundColor: draft.backgroundColor,
    );
    Get.snackbar(
      'Statut publié',
      'Il disparaîtra dans 24 heures.',
      duration: const Duration(seconds: 3),
    );
    return true;
  } on StatusMediaTooLarge catch (e) {
    Get.snackbar(
      'Vidéo trop lourde',
      'Elle pèse ${e.sizeLabel} ; le maximum est ${e.maxLabel}. '
          'Filmez une séquence plus courte, ou baissez la définition vidéo '
          'dans les réglages de l’appareil.',
      duration: const Duration(seconds: 8),
    );
  } on FirebaseException catch (e) {
    // Le code d'erreur est montré tel quel : « unauthorized » (règles
    // Storage non déployées, ou fichier hors plafond) ne se corrige pas du
    // tout comme « retry-limit-exceeded » (réseau). Un message unique
    // « vérifiez votre connexion » envoyait sur la mauvaise piste.
    developer.log('Publication du statut', name: 'StatusComposeFlow', error: e);
    Get.snackbar(
      'Publication impossible',
      '${e.code} — ${e.message ?? 'erreur inconnue'}',
      duration: const Duration(seconds: 8),
    );
  } catch (e) {
    developer.log('Publication du statut', name: 'StatusComposeFlow', error: e);
    Get.snackbar(
      'Publication impossible',
      '$e',
      duration: const Duration(seconds: 8),
    );
  }
  return false;
}

/// Feuille de choix du support.
Future<StatusSource?> askStatusSource() {
  final isDark = Get.find<ThemeController>().isDarkMode;
  final ink = isDark ? AppColors.white : AppColors.black;
  final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

  Widget option({
    required IconData icon,
    required String title,
    required String subtitle,
    required StatusSource value,
  }) =>
      ListTile(
        onTap: () => Get.back<StatusSource>(result: value),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.orange, size: 21),
        ),
        title: Text(
          title,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: ink,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
        ),
      );

  return Get.bottomSheet<StatusSource>(
    Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            option(
              icon: Icons.photo_camera_outlined,
              title: 'Prendre une photo',
              subtitle: 'Avec l’appareil',
              value: StatusSource.photoCamera,
            ),
            option(
              icon: Icons.photo_library_outlined,
              title: 'Choisir une photo',
              subtitle: 'Dans la galerie',
              value: StatusSource.photoGallery,
            ),
            option(
              icon: Icons.videocam_outlined,
              title: 'Filmer une vidéo',
              subtitle: '30 secondes au maximum',
              value: StatusSource.videoCamera,
            ),
            option(
              icon: Icons.video_library_outlined,
              title: 'Choisir une vidéo',
              subtitle: 'Dans la galerie',
              value: StatusSource.videoGallery,
            ),
            option(
              icon: Icons.text_fields_rounded,
              title: 'Écrire un texte',
              subtitle: 'Sur un fond coloré',
              value: StatusSource.text,
            ),
          ],
        ),
      ),
    ),
  );
}
