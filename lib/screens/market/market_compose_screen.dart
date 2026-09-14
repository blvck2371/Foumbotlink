import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/market_compose_controller.dart';
import '../../models/market_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/foumbot_loader.dart';
import '../../widgets/feed_image.dart';
import '../../widgets/form_field_box.dart';
import '../../widgets/foumbot_app_bar.dart';

class MarketComposeScreen extends GetView<MarketComposeController> {
  const MarketComposeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

      return Scaffold(
        backgroundColor: isDark ? AppColors.black : AppColors.white,
        appBar: FoumbotAppBar(
          isDark: isDark,
          title: controller.isEditing
              ? 'Modifier l’annonce'
              : 'Nouvelle annonce',
        ),
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
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      // --- Type d’annonce ---
                      _SectionLabel('Type d’annonce', ink: ink),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _TypeOption(
                              title: 'Vente',
                              subtitle: 'Je vends / propose',
                              icon: Icons.sell_outlined,
                              selected: controller.listingType.value ==
                                  MarketListingType.vente,
                              color: AppColors.orange,
                              isDark: isDark,
                              onTap: () => controller
                                  .selectListingType(MarketListingType.vente),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TypeOption(
                              title: 'Recherche',
                              subtitle: 'Je cherche',
                              icon: Icons.search,
                              selected: controller.listingType.value ==
                                  MarketListingType.achat,
                              color: AppColors.blue,
                              isDark: isDark,
                              onTap: () => controller
                                  .selectListingType(MarketListingType.achat),
                            ),
                          ),
                        ],
                      ),

                      // --- Catégorie ---
                      const SizedBox(height: 22),
                      _SectionLabel('Catégorie', ink: ink),
                      const SizedBox(height: 10),
                      _CategorySelector(isDark: isDark, ink: ink),

                      // --- Titre ---
                      const SizedBox(height: 22),
                      _SectionLabel('Titre *', ink: ink),
                      const SizedBox(height: 8),
                      FormFieldBox(
                        isDark: isDark,
                        child: TextField(
                          controller: controller.titleCtrl,
                          style: GoogleFonts.manrope(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: 'Ex. Sac de maïs 100 kg',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),

                      // --- Description (optionnelle) ---
                      const SizedBox(height: 18),
                      _SectionLabel('Description (facultatif)', ink: ink),
                      const SizedBox(height: 8),
                      FormFieldBox(
                        isDark: isDark,
                        child: TextField(
                          controller: controller.descriptionCtrl,
                          minLines: 3,
                          maxLines: 6,
                          style: GoogleFonts.manrope(color: ink, height: 1.4),
                          decoration: InputDecoration.collapsed(
                            hintText:
                                'Décrivez votre annonce, ajoutez des détails…',
                            hintStyle: GoogleFonts.manrope(color: muted),
                          ),
                        ),
                      ),

                      // --- Condition (si applicable) ---
                      if (controller.showCondition) ...[
                        const SizedBox(height: 18),
                        _SectionLabel('État du bien', ink: ink),
                        const SizedBox(height: 8),
                        _ConditionSelector(isDark: isDark, ink: ink),
                      ],

                      // --- Prix ---
                      const SizedBox(height: 22),
                      _SectionLabel('Prix', ink: ink),
                      const SizedBox(height: 8),
                      Obx(() {
                        final priceDisabled = controller.priceOnRequest.value;
                        return Column(
                          children: [
                            AnimatedOpacity(
                              opacity: priceDisabled ? 0.4 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: FormFieldBox(
                                isDark: isDark,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: controller.priceCtrl,
                                        keyboardType: TextInputType.number,
                                        enabled: !priceDisabled,
                                        style: GoogleFonts.spaceGrotesk(
                                          color: ink,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                        ),
                                        decoration: InputDecoration.collapsed(
                                          hintText: '0',
                                          hintStyle: GoogleFonts.spaceGrotesk(
                                              color: muted),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'FCFA',
                                      style: GoogleFonts.manrope(
                                        fontWeight: FontWeight.w700,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _CheckRow(
                                  label: 'Prix à discuter',
                                  checked: controller.priceOnRequest.value,
                                  onTap: controller.togglePriceOnRequest,
                                  ink: ink,
                                ),
                                const SizedBox(width: 20),
                                if (!priceDisabled)
                                  _CheckRow(
                                    label: 'Négociable',
                                    checked: controller.negotiable.value,
                                    onTap: controller.toggleNegotiable,
                                    ink: ink,
                                  ),
                              ],
                            ),
                          ],
                        );
                      }),

                      // --- Téléphone ---
                      const SizedBox(height: 22),
                      _SectionLabel('Téléphone *', ink: ink),
                      const SizedBox(height: 8),
                      FormFieldBox(
                        isDark: isDark,
                        child: Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 18, color: muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: controller.phoneCtrl,
                                keyboardType: TextInputType.phone,
                                style: GoogleFonts.manrope(color: ink),
                                decoration: InputDecoration.collapsed(
                                  hintText: '+237 6XX XXX XXX',
                                  hintStyle: GoogleFonts.manrope(color: muted),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Votre numéro n’apparaît pas sur l’annonce. Il '
                              'n’est montré qu’à une personne connectée qui '
                              'appuie sur « Afficher le numéro ».',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                height: 1.4,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --- Localisation ---
                      const SizedBox(height: 22),
                      _SectionLabel('Lieu *', ink: ink),
                      const SizedBox(height: 8),
                      _PlaceSelector(isDark: isDark, ink: ink, muted: muted),

                      // --- Photos ---
                      const SizedBox(height: 22),
                      _SectionLabel(
                        'Photos (facultatif, max ${MarketComposeController.maxImages})',
                        ink: ink,
                      ),
                      const SizedBox(height: 10),
                      _ImagesPicker(isDark: isDark),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),

                // --- Bouton publier ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: controller.canSubmit
                          ? () async {
                              final item = await controller.submit();
                              if (item != null) Get.back(result: item);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: AppColors.white,
                        disabledBackgroundColor: muted.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      child: controller.isPublishing.value
                          ? const FoumbotLoader.button()
                          : Text(
                              controller.isEditing
                                  ? 'Enregistrer les modifications'
                                  : 'Publier l’annonce',
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type (vente / recherche)
// ---------------------------------------------------------------------------

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Material(
      color: selected
          ? color.withValues(alpha: isDark ? 0.18 : 0.1)
          : (isDark ? AppColors.blackElevated : AppColors.whiteSoft),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? color : muted, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: selected ? color : ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: muted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category selector (Wrap)
// ---------------------------------------------------------------------------

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.isDark, required this.ink});

  final bool isDark;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketComposeController>();

    return Obx(() {
      final selected = controller.category.value;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final cat in MarketCategory.values)
            GestureDetector(
              onTap: () => controller.selectCategory(cat),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected == cat
                      ? AppColors.orange.withValues(alpha: isDark ? 0.18 : 0.1)
                      : (isDark
                          ? AppColors.blackElevated
                          : AppColors.whiteSoft),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        selected == cat ? AppColors.orange : Colors.transparent,
                  ),
                ),
                child: Text(
                  '${cat.icon} ${cat.label}',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected == cat ? AppColors.orange : ink,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Condition selector
// ---------------------------------------------------------------------------

class _ConditionSelector extends StatelessWidget {
  const _ConditionSelector({required this.isDark, required this.ink});

  final bool isDark;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketComposeController>();

    return Obx(() {
      final selected = controller.condition.value;
      return Row(
        children: [
          for (final c in ItemCondition.values) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => controller.selectCondition(c),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected == c
                        ? AppColors.orange.withValues(alpha: isDark ? 0.18 : 0.1)
                        : (isDark
                            ? AppColors.blackElevated
                            : AppColors.whiteSoft),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          selected == c ? AppColors.orange : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      c.label,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected == c ? AppColors.orange : ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (c != ItemCondition.values.last) const SizedBox(width: 8),
          ],
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Check row (négociable / prix à discuter)
// ---------------------------------------------------------------------------

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onTap,
    required this.ink,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: checked,
              onChanged: (_) => onTap(),
              activeColor: AppColors.orange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Photos picker (plus grand, prévisualisation riche)
// ---------------------------------------------------------------------------

class _ImagesPicker extends StatelessWidget {
  const _ImagesPicker({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketComposeController>();
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;

    return Obx(() {
      final images = controller.images;
      final canAdd = images.length < MarketComposeController.maxImages;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length + (canAdd ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                if (i == images.length) {
                  return GestureDetector(
                    onTap: controller.pickImages,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.blackElevated
                            : AppColors.whiteSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: muted.withValues(alpha: 0.3),
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 28, color: muted),
                          const SizedBox(height: 6),
                          Text(
                            'Ajouter',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return _ImageThumb(
                  entry: images[i],
                  index: i,
                  isDark: isDark,
                  onRemove: () => controller.removeImage(i),
                  onMoveLeft: i > 0 ? () => controller.moveImage(i, i - 1) : null,
                );
              },
            ),
          ),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'La première photo sert de vignette dans le marché. '
              'Utilisez la flèche pour changer l’ordre.',
              style: GoogleFonts.manrope(fontSize: 12, color: muted),
            ),
          ],
        ],
      );
    });
  }
}

/// Vignette d'une photo du formulaire.
///
/// En modification, la liste mélange des photos déjà en ligne (des URL
/// https) et des photos qu'on vient de choisir (des fichiers locaux) :
/// les deux doivent s'afficher côte à côte, d'où la distinction ici.
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.entry,
    required this.index,
    required this.isDark,
    required this.onRemove,
    required this.onMoveLeft,
  });

  final String entry;
  final int index;
  final bool isDark;
  final VoidCallback onRemove;
  final VoidCallback? onMoveLeft;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          // FeedNetworkImage accepte aussi bien une URL qu'un chemin
          // local, ce qui est exactement ce qu'il faut ici : en
          // modification, la liste mélange les deux.
          child: SizedBox(
            width: 110,
            height: 110,
            child: FeedNetworkImage(url: entry, isDark: isDark),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
        if (onMoveLeft != null)
          Positioned(
            bottom: 6,
            right: 6,
            child: GestureDetector(
              onTap: onMoveLeft,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chevron_left,
                    size: 16, color: Colors.white),
              ),
            ),
          ),
        Positioned(
          bottom: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: index == 0
                  ? AppColors.orange
                  : Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              index == 0 ? 'Principale' : '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sélecteur de lieu
// ---------------------------------------------------------------------------

/// Liste fermée de lieux, plus une saisie libre en dernier recours.
///
/// Un champ texte libre rendait le filtre par lieu inutilisable : trois
/// personnes écrivaient le même quartier de trois façons, et aucune
/// recherche ne les rapprochait.
class _PlaceSelector extends StatelessWidget {
  const _PlaceSelector({
    required this.isDark,
    required this.ink,
    required this.muted,
  });

  final bool isDark;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MarketComposeController>();
    return Obx(() {
      final selected = controller.place.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final place in [...MarketPlaces.values, MarketPlaces.autre])
                _PlaceChip(
                  label: place,
                  selected: selected == place,
                  ink: ink,
                  onTap: () => controller.selectPlace(place),
                ),
            ],
          ),
          if (selected == MarketPlaces.autre) ...[
            const SizedBox(height: 10),
            FormFieldBox(
              isDark: isDark,
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 18, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller.customPlaceCtrl,
                      style: GoogleFonts.manrope(color: ink),
                      decoration: InputDecoration.collapsed(
                        hintText: 'Précisez le quartier',
                        hintStyle: GoogleFonts.manrope(color: muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _PlaceChip extends StatelessWidget {
  const _PlaceChip({
    required this.label,
    required this.selected,
    required this.ink,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.orange : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.orange : ink.withValues(alpha: 0.25),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : ink,
            ),
          ),
        ),
      ),
    );
  }
}
