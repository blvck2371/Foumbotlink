import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/pro_listing.dart';
import '../../services/auth_service.dart';
import '../../services/directory_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../utils/local_media.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/foumbot_app_bar.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/form_field_box.dart';

/// Créer ou modifier sa fiche dans l'annuaire.
///
/// Argument : la fiche existante, ou `null` pour une création. Renvoie la
/// fiche enregistrée, ou `false` si elle a été retirée.
class ProEditScreen extends StatefulWidget {
  const ProEditScreen({super.key});

  @override
  State<ProEditScreen> createState() => _ProEditScreenState();
}

class _ProEditScreenState extends State<ProEditScreen> {
  final _service = Get.find<DirectoryService>();
  final _auth = Get.find<AuthService>();
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _trade = TextEditingController();
  final _description = TextEditingController();
  final _quartier = TextEditingController();
  final _hours = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();

  ProListing? _existing;
  ProCategory? _category;

  /// URLs déjà en ligne et fichiers locaux à envoyer, dans l'ordre
  /// d'affichage. La première photo sert de vignette dans la liste.
  final _photos = <String>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    _existing = arg is ProListing ? arg : null;
    _prefill();
  }

  Future<void> _prefill() async {
    final profile = Get.find<UserProfileService>().profile.value;
    final e = _existing;
    if (e != null) {
      _name.text = e.name;
      _category = e.category;
      _trade.text = e.trade;
      _description.text = e.description;
      _quartier.text = e.quartier;
      _hours.text = e.hours;
      _photos.addAll(e.photos);
      try {
        final c = await _service.contact(e.id);
        _phone.text = c.phone;
        _whatsapp.text = c.whatsapp;
      } on Object catch (_) {}
    } else {
      _name.text = profile?.displayName ?? '';
      _phone.text = profile?.phoneNumber ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [
      _name, _trade, _description, _quartier, _hours, _phone, _whatsapp,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Photos réduites à 1280 px, qualité 70 : assez pour montrer un
  /// travail, sans coûter son forfait à chaque habitant qui ouvre la fiche.
  Future<void> _pickPhotos() async {
    final room = ProListing.maxPhotos - _photos.length;
    if (room <= 0) return;
    final picked = await ImagePicker().pickMultiImage(
      limit: room,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (!mounted || picked.isEmpty) return;
    setState(() => _photos.addAll(picked.take(room).map((f) => f.path)));
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_category == null) {
      Get.snackbar('Annuaire', 'Choisissez votre métier.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (_photos.isEmpty) {
      Get.snackbar('Annuaire', 'Ajoutez au moins une photo de votre activité.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    setState(() => _saving = true);
    final e = _existing;
    final listing = ProListing(
      id: _auth.uid,
      name: _name.text.trim(),
      category: _category!,
      trade: _trade.text.trim(),
      description: _description.text.trim(),
      quartier: _quartier.text.trim(),
      hours: _hours.text.trim(),
      photoUrl: Get.find<UserProfileService>().profile.value?.photoUrl,
      ratingCount: e?.ratingCount ?? 0,
      ratingAvg: e?.ratingAvg ?? 0,
      rankScore: e?.rankScore ?? ProListing.rankPrior,
      createdAt: e?.createdAt,
    );
    try {
      final saved = await _service.save(
        listing,
        ProContact(phone: _phone.text.trim(), whatsapp: _whatsapp.text.trim()),
        photos: _photos,
        previousPhotos: e?.photos ?? const [],
      );
      Get.back(result: saved);
    } on Object catch (err) {
      if (mounted) setState(() => _saving = false);
      Get.snackbar('Annuaire', 'Enregistrement impossible : $err',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      title: 'Retirer ma fiche ?',
      message: 'Vous n’apparaîtrez plus dans l’annuaire. Vos avis sont '
          'conservés si vous recréez une fiche.',
      confirmLabel: 'Retirer',
    );
    if (!ok) return;
    try {
      await _service.delete(_auth.uid);
      Get.back(result: false);
    } on Object catch (err) {
      Get.snackbar('Annuaire', 'Suppression impossible : $err',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _photoPicker(bool isDark, Color muted) {
    const size = 100.0;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < _photos.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: LocalMedia.isLocal(_photos[i])
                      ? Image(
                          image: LocalMedia.image(_photos[i]),
                          fit: BoxFit.cover,
                        )
                      : FeedNetworkImage(url: _photos[i], isDark: isDark),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: AppColors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _photos.removeAt(i)),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: AppColors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (_photos.length < ProListing.maxPhotos)
          InkWell(
            onTap: _pickPhotos,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined, color: AppColors.orange),
                  const SizedBox(height: 6),
                  Text(
                    'Ajouter',
                    style: GoogleFonts.manrope(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDark = Get.find<ThemeController>().isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      Widget label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          text,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
      );

      Widget field(
        TextEditingController ctrl,
        String hint, {
        int maxLines = 1,
        int? maxLength,
        TextInputType? keyboard,
        String? Function(String?)? validator,
      }) => FormFieldBox(
        isDark: isDark,
        child: TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboard,
          validator: validator,
          style: GoogleFonts.manrope(color: ink, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: GoogleFonts.manrope(color: muted),
            counterStyle: GoogleFonts.manrope(color: muted),
          ),
        ),
      );

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: _existing == null ? 'Créer ma fiche pro' : 'Modifier ma fiche',
          actions: [
            if (_existing != null)
              IconButton(
                tooltip: 'Retirer ma fiche',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: FoumbotLoader())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    Text(
                      'Votre fiche apparaît dans l’annuaire de la commune. '
                      'Les habitants qui vous contactent pourront vous noter.',
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        height: 1.45,
                        color: muted,
                      ),
                    ),
                    label('Nom affiché *'),
                    field(
                      _name,
                      'Ex. Froid Service Foumbot, Jean le frigoriste',
                      maxLength: 60,
                      validator: (v) => (v ?? '').trim().length < 2
                          ? 'Indiquez un nom'
                          : null,
                    ),
                    label('Métier *'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in ProCategory.values)
                          ChoiceChip(
                            avatar: Icon(
                              c.icon,
                              size: 16,
                              color: _category == c ? AppColors.white : ink,
                            ),
                            label: Text(c.label),
                            selected: _category == c,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _category = c),
                            selectedColor: AppColors.orangeReadable,
                            backgroundColor: isDark
                                ? AppColors.blackElevated
                                : AppColors.whiteSoft,
                            side: BorderSide.none,
                            labelStyle: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              color: _category == c ? AppColors.white : ink,
                            ),
                          ),
                      ],
                    ),
                    label(
                      _category == ProCategory.autre
                          ? 'Votre métier *'
                          : 'Spécialité',
                    ),
                    field(
                      _trade,
                      'Ex. Climatisation, chambres froides',
                      maxLength: 60,
                      validator: (v) => _category == ProCategory.autre &&
                              (v ?? '').trim().isEmpty
                          ? 'Précisez votre métier'
                          : null,
                    ),
                    label(
                      'Photos de votre activité * '
                      '(${_photos.length}/${ProListing.maxPhotos})',
                    ),
                    Text(
                      'Au moins une photo : vos réalisations, votre atelier, '
                      'votre matériel. Les habitants choisissent plus '
                      'volontiers un pro qui montre son travail.',
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.4,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _photoPicker(isDark, muted),
                    label('Téléphone *'),
                    field(
                      _phone,
                      'Ex. 6 77 12 34 56',
                      keyboard: TextInputType.phone,
                      validator: (v) =>
                          (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 8
                              ? 'Numéro invalide'
                              : null,
                    ),
                    label('WhatsApp (si différent)'),
                    field(
                      _whatsapp,
                      'Laisser vide si c’est le même numéro',
                      keyboard: TextInputType.phone,
                    ),
                    label('Quartier'),
                    field(_quartier, 'Ex. Centre-ville, près du marché', maxLength: 60),
                    label('Horaires'),
                    field(_hours, 'Ex. Lun–Sam, 8 h–18 h', maxLength: 60),
                    label('Présentation'),
                    field(
                      _description,
                      'Vos services, votre expérience, vos zones d’intervention…',
                      maxLines: 5,
                      maxLength: 600,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orangeReadable,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const FoumbotLoader.button()
                            : Text(
                                _existing == null
                                    ? 'Publier ma fiche'
                                    : 'Enregistrer',
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
    });
  }
}
