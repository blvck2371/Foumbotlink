import 'dart:ui';

import '../models/market_item.dart';
import 'app_colors.dart';

/// Couleur d'un type d'annonce : orange pour une vente, bleu pour une
/// recherche, vert pour une location.
Color marketTypeColor(MarketListingType type) => switch (type) {
  MarketListingType.vente => AppColors.orange,
  MarketListingType.achat => AppColors.blue,
  MarketListingType.location => AppColors.success,
};
