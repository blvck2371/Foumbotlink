import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/market_item.dart';
import '../../models/seller_review.dart';
import '../../services/auth_service.dart';
import '../../services/seller_review_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';

/// Feuille « Noter ce vendeur ». Renvoie `true` si un avis a été publié.
///
/// Réservée aux personnes ayant réellement pris contact : le bouton n'est
/// proposé qu'après vérification (`SellerReviewService.canReview`), et les
/// règles Firestore refusent l'écriture dans le cas contraire.
Future<bool> showSellerReviewSheet({
  required String sellerUid,
  required String sellerName,
  MarketItem? item,
}) async {
  final result = await Get.bottomSheet<bool>(
    _SellerReviewSheet(
      sellerUid: sellerUid,
      sellerName: sellerName,
      item: item,
    ),
    isScrollControlled: true,
    ignoreSafeArea: false,
  );
  return result == true;
}

class _SellerReviewSheet extends StatefulWidget {
  const _SellerReviewSheet({
    required this.sellerUid,
    required this.sellerName,
    this.item,
  });

  final String sellerUid;
  final String sellerName;
  final MarketItem? item;

  @override
  State<_SellerReviewSheet> createState() => _SellerReviewSheetState();
}

class _SellerReviewSheetState extends State<_SellerReviewSheet> {
  final _service = Get.find<SellerReviewService>();
  final _commentCtrl = TextEditingController();

  int _rating = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _hasExisting = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  /// Un avis déjà laissé rouvre la feuille pré-remplie : publier écrase
  /// le précédent, personne ne se retrouve avec deux notes.
  Future<void> _loadExisting() async {
    final auth = Get.find<AuthService>();
    if (!auth.isSignedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final existing = await _service.myReview(
      sellerUid: widget.sellerUid,
      myUid: auth.uid,
    );
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _rating = existing.rating;
        _commentCtrl.text = existing.comment;
        _hasExisting = true;
      }
      _loading = false;
    });
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
    try {
      await _service.submit(
        sellerUid: widget.sellerUid,
        review: SellerReview(
          reviewerUid: auth.uid,
          reviewerName: profile?.displayName ?? 'Habitant·e',
          rating: _rating,
          comment: _commentCtrl.text,
          createdAt: DateTime.now(),
          itemId: widget.item?.id,
          itemTitle: widget.item?.title ?? '',
        ),
      );
      Get.back(result: true);
    } on Object catch (e) {
      if (mounted) setState(() => _submitting = false);
      Get.snackbar('Avis', 'Publication impossible : $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

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
              _hasExisting ? 'Modifier votre avis' : 'Noter ${widget.sellerName}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Votre avis aide les autres habitants à savoir à qui ils ont '
              'affaire avant de se déplacer.',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.45,
                color: muted,
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.orange),
              ))
            else ...[
              Row(
                children: [
                  for (var star = 1; star <= 5; star++)
                    IconButton(
                      onPressed: () => setState(() => _rating = star),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        star <= _rating ? Icons.star : Icons.star_border,
                        size: 34,
                        color: star <= _rating ? AppColors.orange : muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    hintText:
                        'Comment s’est passée la rencontre ? (facultatif)',
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
                    backgroundColor: AppColors.orange,
                    disabledBackgroundColor: muted.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _submitting ? 'Envoi…' : 'Publier mon avis',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
