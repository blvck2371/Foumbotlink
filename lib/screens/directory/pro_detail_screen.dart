import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../controllers/directory_controller.dart';
import '../../models/pro_listing.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/directory_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/post_image_viewer.dart';
import 'directory_widgets.dart';

/// Fiche d'un professionnel : coordonnées, note, avis des habitants.
///
/// Argument : un [ProListing] (ouverture depuis la liste, affichage
/// immédiat) ou son id (lien depuis ailleurs, chargé ici).
class ProDetailScreen extends StatefulWidget {
  const ProDetailScreen({super.key});

  @override
  State<ProDetailScreen> createState() => _ProDetailScreenState();
}

class _ProDetailScreenState extends State<ProDetailScreen> {
  final _service = Get.find<DirectoryService>();
  final _auth = Get.find<AuthService>();
  final _ctrl = Get.find<DirectoryController>();

  ProListing? _listing;
  List<ProReview> _reviews = const [];
  bool _canReview = false;
  bool _loadingReviews = true;
  bool _notFound = false;
  final _subs = <StreamSubscription<Object?>>[];

  /// Taille du flux d'avis. Tant que tous les avis y tiennent, la note
  /// affichée est recalculée ici même : elle bouge à l'instant où un avis
  /// est publié, sans attendre `onProReviewWritten`.
  static const _reviewsLimit = 50;

  String get _myUid => _auth.isSignedIn ? _auth.uid : '';
  bool get _isMine => _listing != null && _listing!.id == _myUid;

  ProReview? get _myReview =>
      _reviews.firstWhereOrNull((r) => r.reviewerUid == _myUid);

  /// Fiche avec la note recalculée à partir des avis reçus en direct.
  ProListing? get _display {
    final pro = _listing;
    if (pro == null || _loadingReviews) return pro;
    if (_reviews.length >= _reviewsLimit) return pro;
    final sum = _reviews.fold<int>(0, (s, r) => s + r.rating);
    return pro.copyWith(
      ratingCount: _reviews.length,
      ratingAvg: _reviews.isEmpty ? 0 : sum / _reviews.length,
    );
  }

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is ProListing) _listing = arg;
    final id = arg is ProListing ? arg.id : (arg is String ? arg : '');
    if (id.isEmpty) {
      _notFound = true;
    } else {
      _listen(id);
    }
  }

  void _listen(String id) {
    _subs
      ..add(_service.watch(id).listen((fresh) {
        if (!mounted) return;
        setState(() {
          _listing = fresh ?? _listing;
          _notFound = fresh == null;
        });
      }, onError: (Object _) {}))
      ..add(_service.watchReviews(id, limit: _reviewsLimit).listen(
        (list) {
          if (mounted) {
            setState(() {
              _reviews = list;
              _loadingReviews = false;
            });
          }
        },
        onError: (Object _) {
          if (mounted) setState(() => _loadingReviews = false);
        },
      ))
      ..add(_service.watchCanReview(proUid: id, myUid: _myUid).listen((can) {
        if (mounted) setState(() => _canReview = can);
      }, onError: (Object _) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Le bouton « Noter » est toujours visible ; sans contact préalable, il
  /// explique comment débloquer la notation au lieu de rester caché.
  Future<void> _openReview() async {
    final pro = _listing;
    if (pro == null) return;
    if (!_auth.isSignedIn) {
      await Get.toNamed(AppRoutes.auth);
      return;
    }
    if (!_canReview) {
      Get.snackbar(
        'Noter ce professionnel',
        'Contactez-le d’abord avec Appeler, WhatsApp ou Message : seules '
            'les personnes qui l’ont contacté peuvent laisser un avis.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    await Get.bottomSheet<ProReview>(
      _ReviewSheet(pro: pro, existing: _myReview),
      isScrollControlled: true,
    );
  }

  Future<void> _deleteListing() async {
    final ok = await confirmAction(
      title: 'Retirer ma fiche ?',
      message: 'Vous n’apparaîtrez plus dans l’annuaire. Vos avis sont '
          'conservés si vous recréez une fiche.',
      confirmLabel: 'Retirer',
    );
    if (!ok) return;
    try {
      await _service.delete(_myUid);
      _ctrl.removeLocal(_myUid);
      Get.back();
    } on Object catch (e) {
      Get.snackbar('Annuaire', 'Suppression impossible : $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _edit() async {
    final saved = await Get.toNamed(
      AppRoutes.directoryEdit,
      arguments: _listing,
    );
    if (saved is ProListing && mounted) {
      setState(() => _listing = saved);
      _ctrl.upsertLocal(saved);
    } else if (saved == false) {
      _ctrl.removeLocal(_myUid);
      Get.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = Get.find<ThemeController>().isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final pro = _display;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: 'Fiche professionnel',
          actions: [
            if (pro != null)
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => _edit(),
                  'delete' => _deleteListing(),
                  'report' => _ctrl.report(pro),
                  'profile' => Get.toNamed(
                    AppRoutes.userProfile,
                    arguments: pro.id,
                  ),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: Text('Voir le profil'),
                  ),
                  if (_isMine) ...[
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifier ma fiche'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Retirer ma fiche'),
                    ),
                  ] else
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Signaler'),
                    ),
                ],
              ),
          ],
        ),
        body: _notFound && pro == null
            ? Center(
                child: Text(
                  'Cette fiche n’existe plus.',
                  style: GoogleFonts.manrope(color: muted),
                ),
              )
            : pro == null
                ? const Center(child: FoumbotLoader())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    children: [
                      _header(pro, isDark, ink, muted),
                      if (pro.photos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _photos(context, pro, isDark),
                      ],
                      const SizedBox(height: 18),
                      if (!_isMine) _contactButtons(pro, isDark),
                      if (_isMine) _ownerHint(isDark, muted),
                      const SizedBox(height: 18),
                      ..._infos(pro, isDark, ink, muted),
                      const SizedBox(height: 22),
                      _reviewsSection(pro, isDark, ink, muted),
                    ],
                  ),
      );
    });
  }

  Widget _header(ProListing pro, bool isDark, Color ink, Color muted) {
    return Row(
      children: [
        ProAvatar(listing: pro, isDark: isDark, radius: 36),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pro.name,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                pro.categoryLabel,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.orangeSoft : AppColors.orangeReadable,
                ),
              ),
              const SizedBox(height: 6),
              RatingLine(listing: pro, ink: ink, muted: muted, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  /// Photos de l'activité, en bande ; un toucher les ouvre en grand.
  Widget _photos(BuildContext context, ProListing pro, bool isDark) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pro.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => openPostImageViewer(
            context,
            imageUrls: pro.photos,
            initialIndex: i,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: pro.photos.length == 1 ? 260 : 190,
              child: FeedNetworkImage(url: pro.photos[i], isDark: isDark),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contactButtons(ProListing pro, bool isDark) {
    Widget button(IconData icon, String label, VoidCallback onTap,
        {bool primary = false}) {
      return Expanded(
        child: SizedBox(
          height: 52,
          child: primary
              ? FilledButton.icon(
                  onPressed: onTap,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orangeReadable,
                    textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: onTap,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? AppColors.white : AppColors.black,
                    textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    side: BorderSide(
                      color: isDark
                          ? AppColors.blackElevated
                          : AppColors.black.withValues(alpha: 0.15),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
        ),
      );
    }

    return Row(
      children: [
        button(Icons.call, 'Appeler', () => _ctrl.call(pro),
            primary: true),
        const SizedBox(width: 8),
        button(Icons.chat_bubble_outline, 'WhatsApp',
            () => _ctrl.whatsapp(pro)),
        const SizedBox(width: 8),
        button(Icons.mail_outline, 'Message',
            () => _ctrl.message(pro)),
      ],
    );
  }

  Widget _ownerHint(bool isDark, Color muted) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'C’est votre fiche. Les habitants qui vous contactent depuis '
              'l’annuaire pourront vous noter : plus vous avez de bons avis, '
              'plus vous montez dans le classement.',
              style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: muted),
            ),
          ),
          IconButton(
            tooltip: 'Modifier',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, color: AppColors.orange),
          ),
        ],
      ),
    );
  }

  List<Widget> _infos(ProListing pro, bool isDark, Color ink, Color muted) {
    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(fontSize: 14.5, height: 1.4, color: ink),
            ),
          ),
        ],
      ),
    );

    return [
      if (pro.trade.isNotEmpty && pro.category != ProCategory.autre)
        row(Icons.build_outlined, pro.trade),
      if (pro.quartier.isNotEmpty) row(Icons.place_outlined, pro.quartier),
      if (pro.hours.isNotEmpty) row(Icons.schedule, pro.hours),
      if (pro.description.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          pro.description,
          style: GoogleFonts.manrope(fontSize: 14.5, height: 1.5, color: ink),
        ),
      ],
    ];
  }

  Widget _reviewsSection(ProListing pro, bool isDark, Color ink, Color muted) {
    final dateFmt = DateFormat('d MMM yyyy', 'fr_FR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Avis des habitants',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            if (!_isMine)
              TextButton.icon(
                onPressed: _openReview,
                icon: Icon(
                  _myReview == null ? Icons.star_outline : Icons.edit_outlined,
                  color: AppColors.orange,
                ),
                label: Text(
                  _myReview == null ? 'Noter' : 'Modifier mon avis',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.orangeSoft : AppColors.orangeReadable,
                  ),
                ),
              ),
          ],
        ),
        if (!_canReview && !_isMine && !_loadingReviews)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Pour garantir des avis honnêtes, seules les personnes qui ont '
              'contacté ce professionnel depuis l’app peuvent le noter.',
              style: GoogleFonts.manrope(fontSize: 12.5, height: 1.4, color: muted),
            ),
          ),
        const SizedBox(height: 8),
        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: FoumbotLoader()),
          )
        else if (_reviews.isEmpty)
          Text(
            'Aucun avis pour l’instant.',
            style: GoogleFonts.manrope(fontSize: 14, color: muted),
          )
        else
          for (final r in _reviews)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.blackSoft : AppColors.whiteSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.reviewerUid == _myUid ? 'Vous' : r.reviewerName,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: ink,
                          ),
                        ),
                      ),
                      Text(
                        dateFmt.format(r.createdAt),
                        style: GoogleFonts.manrope(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  StarRow(value: r.rating.toDouble(), size: 15, muted: muted),
                  if (r.comment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      r.comment,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.45,
                        color: ink,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

/// Feuille « Noter ce professionnel ». Renvoie l'avis publié.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.pro, this.existing});

  final ProListing pro;
  final ProReview? existing;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _commentCtrl = TextEditingController();
  int _rating = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _rating = e.rating;
      _commentCtrl.text = e.comment;
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    final auth = Get.find<AuthService>();
    final profile = Get.find<UserProfileService>().profile.value;
    final review = ProReview(
      reviewerUid: auth.uid,
      reviewerName: profile?.displayName ?? 'Habitant·e',
      rating: _rating,
      comment: _commentCtrl.text.trim(),
      createdAt: DateTime.now(),
    );
    // On referme sans attendre le serveur : l'avis est déjà dans le
    // cache local, et le flux de la fiche l'affiche à l'instant. Un refus
    // (règles, réseau) remonte ensuite par le message ci-dessous.
    unawaited(
      Get.find<DirectoryService>()
          .submitReview(proUid: widget.pro.id, review: review)
          .catchError((Object e) {
        Get.snackbar('Avis', 'Publication impossible : $e',
            snackPosition: SnackPosition.BOTTOM);
      }),
    );
    Get.back(result: review);
  }

  static const _labels = ['', 'Très mauvais', 'Décevant', 'Correct', 'Bien',
    'Excellent'];

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackSoft : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.existing != null
                  ? 'Modifier votre avis'
                  : 'Noter ${widget.pro.name}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Qualité du travail, ponctualité, prix… votre avis aide les '
              'habitants à choisir.',
              style: GoogleFonts.manrope(fontSize: 13.5, height: 1.45, color: muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    onPressed: () => setState(() => _rating = star),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    tooltip: _labels[star],
                    icon: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 38,
                      color: star <= _rating ? AppColors.orange : muted,
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  _labels[_rating],
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _commentCtrl,
                maxLines: 4,
                maxLength: 400,
                style: GoogleFonts.manrope(color: ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  counterStyle: GoogleFonts.manrope(color: muted),
                  hintText: 'Racontez votre expérience (facultatif)',
                  hintStyle: GoogleFonts.manrope(color: muted),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _rating == 0 || _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.orangeReadable,
                  disabledBackgroundColor: muted.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const FoumbotLoader.button()
                    : Text(
                        'Publier mon avis',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
