import 'package:flutter/material.dart';

import '../../setup/data/setup_catalog.dart' as setup;
import '../../wallets/data/wallet_catalog.dart' as wallets;

/// Icons available in the category edit sheet. Superset of the icons the
/// setup wizard uses, so any starter category created by the wizard still
/// resolves through this lookup.
const kCategoryIconCatalog = <String, IconData>{
  // Food & dining
  'restaurant': Icons.restaurant,
  'local_cafe': Icons.local_cafe,
  'shopping_basket': Icons.shopping_basket,
  // Transport
  'directions_car': Icons.directions_car,
  'directions_bus': Icons.directions_bus,
  'local_gas_station': Icons.local_gas_station,
  'flight': Icons.flight,
  // Home & bills
  'home': Icons.home,
  'receipt_long': Icons.receipt_long,
  'bolt': Icons.bolt,
  // Shopping & gifts
  'shopping_bag': Icons.shopping_bag,
  'card_giftcard': Icons.card_giftcard,
  // Entertainment & wellness
  'movie': Icons.movie,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'spa': Icons.spa,
  // Health & education
  'favorite': Icons.favorite,
  'medical_services': Icons.medical_services,
  'school': Icons.school,
  // Money / work
  'work': Icons.work,
  'laptop': Icons.laptop,
  'attach_money': Icons.attach_money,
  'savings': Icons.savings,
  // Default / fallback
  'label': Icons.label_outline,
};

/// Color palette for category swatches. Mirrors [wallets.kWalletColorCatalog]
/// so wallets and categories feel visually unified; duplicated for clarity.
const kCategoryColorCatalog = <String>[
  '8a4f37',
  '526256',
  'c4a484',
  'b08080',
  '6b8e8e',
  'b89968',
  '8e6b8a',
  '5a7558',
  'c47a5a',
  '708090',
];

/// Resolves a category's stored icon name to an `IconData`, falling back
/// through the legacy setup map and finally to a generic label icon.
IconData iconForCategory(String name) {
  return kCategoryIconCatalog[name] ??
      setup.setupIconLookup[name] ??
      Icons.label_outline;
}
