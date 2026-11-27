import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/market_controller.dart';
import '../../models/market_filters.dart';
import '../../models/market_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';

/// Feuille « Filtrer et trier ».
///
/// Les critères sont édités sur une copie locale et appliqués d'un seul
/// coup à la validation : sur un réseau lent, recharger la grille à
/// chaque case cochée donnerait une impression de blocage.
Future<void> showMarketFiltersSheet() {
  final controller = Get.find<MarketController>();
  return Get.bottomSheet<void>(
    _MarketFiltersSheet(initial: controller.filters.value),
    isScrollControlled: true,
    ignoreSafeArea: false,
  );
}

class _MarketFiltersSheet extends StatefulWidget {
  const _MarketFiltersSheet({required this.initial});

  final MarketFilters initial;

  @override
  State<_MarketFiltersSheet> createState() => _MarketFiltersSheetState();
}

class _MarketFiltersSheetState extends State<_MarketFiltersSheet> {
  late MarketFilters _draft = widget.initial;
  late final TextEditingController _minCtrl = TextEditingController(
    text: widget.initial.minPrice?.toString() ?? '',
  );
  late final TextEditingController _maxCtrl = TextEditingController(
    text: widget.initial.maxPrice?.toString() ?? '',
  );

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController c) {
    final digits = c.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  void _apply() {
    final min = _parse(_minCtrl);
    final max = _parse(_maxCtrl);
    Get.back();
    Get.find<MarketController>().applyFilters(
      _draft.copyWith(
        minPrice: min,
        clearMinPrice: min == null,
        maxPrice: max,
        clearMaxPrice: max == null,
      ),
    );
  }

  void _reset() {
    setState(() {
      _draft = _draft.cleared();
      _minCtrl.clear();
      _maxCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.find<ThemeController>().isDarkMode;
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    final surface = isDark ? AppColors.blackSoft : AppColors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtrer et trier',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _reset,
                    child: Text(
                      'Tout effacer',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  _Label('Ordre d’affichage', ink: ink),
                  const SizedBox(height: 4),
                  Text(
                    'Au hasard donne sa chance à chaque vendeur, pas '
                    'seulement au dernier qui a publié.',
                    style: GoogleFonts.manrope(fontSize: 12.5, color: muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sort in MarketSort.values)
                        _Choice(
                          label: sort.label,
                          selected: _draft.sort == sort,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(sort: sort),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Label('Type', ink: ink),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Choice(
                        label: 'Tout',
                        selected: _draft.listingType == null,
                        isDark: isDark,
                        onTap: () => setState(
                          () =>
                              _draft = _draft.copyWith(clearListingType: true),
                        ),
                      ),
                      for (final type in MarketListingType.values)
                        _Choice(
                          label: type.pluralLabel,
                          selected: _draft.listingType == type,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(listingType: type),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Label('Catégorie', ink: ink),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Choice(
                        label: 'Toutes',
                        selected: _draft.category == null,
                        isDark: isDark,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(clearCategory: true),
                        ),
                      ),
                      for (final cat in MarketCategory.values)
                        _Choice(
                          label: '${cat.icon} ${cat.label}',
                          selected: _draft.category == cat,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(category: cat),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Label('Lieu', ink: ink),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Choice(
                        label: 'Partout',
                        selected: _draft.place == null,
                        isDark: isDark,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(clearPlace: true),
                        ),
                      ),
                      for (final p in MarketPlaces.values)
                        _Choice(
                          label: p,
                          selected: _draft.place == p,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(place: p),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Label('État', ink: ink),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Choice(
                        label: 'Peu importe',
                        selected: _draft.condition == null,
                        isDark: isDark,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(clearCondition: true),
                        ),
                      ),
                      for (final c in ItemCondition.values)
                        _Choice(
                          label: c.label,
                          selected: _draft.condition == c,
                          isDark: isDark,
                          onTap: () => setState(
                            () => _draft = _draft.copyWith(condition: c),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _Label('Prix (FCFA)', ink: ink),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PriceField(
                          controller: _minCtrl,
                          hint: 'Minimum',
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PriceField(
                          controller: _maxCtrl,
                          hint: 'Maximum',
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Les annonces « prix à discuter » sont écartées dès '
                    'qu’une fourchette est demandée.',
                    style: GoogleFonts.manrope(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _apply,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Voir les annonces',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.ink});

  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.manrope(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
      color: ink,
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
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

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.hint,
    required this.isDark,
  });

  final TextEditingController controller;
  final String hint;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? AppColors.white : AppColors.black;
    final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.blackElevated : AppColors.whiteSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: GoogleFonts.manrope(color: ink),
        decoration: InputDecoration.collapsed(
          hintText: hint,
          hintStyle: GoogleFonts.manrope(color: muted),
        ),
      ),
    );
  }
}
