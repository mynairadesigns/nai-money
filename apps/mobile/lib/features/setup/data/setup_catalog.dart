import 'package:flutter/material.dart';

/// Currency picker options for the setup wizard (PRD §6.1 step 1).
///
/// Top 20 by app-relevant usage. Order matters — defaults to USD at top.
/// `name` is the localized display label (English only in v1 per CLAUDE.md
/// §6); the picker shows `code · name` rows.
class CurrencyOption {
  const CurrencyOption(this.code, this.name, this.symbol);
  final String code;
  final String name;
  final String symbol;
}

const kCurrencyCatalog = <CurrencyOption>[
  CurrencyOption('USD', 'US Dollar', '\$'),
  CurrencyOption('EUR', 'Euro', '€'),
  CurrencyOption('GBP', 'British Pound', '£'),
  CurrencyOption('JPY', 'Japanese Yen', '¥'),
  CurrencyOption('CNY', 'Chinese Yuan', '¥'),
  CurrencyOption('CHF', 'Swiss Franc', 'CHF'),
  CurrencyOption('CAD', 'Canadian Dollar', 'C\$'),
  CurrencyOption('AUD', 'Australian Dollar', 'A\$'),
  CurrencyOption('HKD', 'Hong Kong Dollar', 'HK\$'),
  CurrencyOption('SGD', 'Singapore Dollar', 'S\$'),
  CurrencyOption('KRW', 'South Korean Won', '₩'),
  CurrencyOption('INR', 'Indian Rupee', '₹'),
  CurrencyOption('MXN', 'Mexican Peso', 'MX\$'),
  CurrencyOption('BRL', 'Brazilian Real', 'R\$'),
  CurrencyOption('ZAR', 'South African Rand', 'R'),
  CurrencyOption('SEK', 'Swedish Krona', 'kr'),
  CurrencyOption('NOK', 'Norwegian Krone', 'kr'),
  CurrencyOption('NZD', 'New Zealand Dollar', 'NZ\$'),
  CurrencyOption('THB', 'Thai Baht', '฿'),
  CurrencyOption('IDR', 'Indonesian Rupiah', 'Rp'),
];

/// Starter categories offered in the setup wizard (PRD §6.1 step 3).
/// The user picks 4–6 from this list. Each becomes a row in the Drift
/// `Categories` table on commit, scoped to `auth.currentUser.uid`.
///
/// Colors are hex strings (no `#`) and resolve through whatever rendering
/// layer eventually maps them. Icons reference Material icon names; the
/// Category renderer translates name → IconData (see [setupIconLookup]).
class StarterCategory {
  const StarterCategory({
    required this.key,
    required this.name,
    required this.type, // 'income' | 'expense'
    required this.iconName,
    required this.colorHex,
  });
  final String key;
  final String name;
  final String type;
  final String iconName;
  final String colorHex;
}

const kStarterCategories = <StarterCategory>[
  // ----- Expense -----
  StarterCategory(
    key: 'food',
    name: 'Food & Dining',
    type: 'expense',
    iconName: 'restaurant',
    colorHex: 'c47a5a',
  ),
  StarterCategory(
    key: 'groceries',
    name: 'Groceries',
    type: 'expense',
    iconName: 'shopping_basket',
    colorHex: '526256',
  ),
  StarterCategory(
    key: 'transport',
    name: 'Transport',
    type: 'expense',
    iconName: 'directions_car',
    colorHex: '6b8e8e',
  ),
  StarterCategory(
    key: 'bills',
    name: 'Bills & Utilities',
    type: 'expense',
    iconName: 'receipt_long',
    colorHex: '708090',
  ),
  StarterCategory(
    key: 'housing',
    name: 'Housing',
    type: 'expense',
    iconName: 'home',
    colorHex: '8a4f37',
  ),
  StarterCategory(
    key: 'shopping',
    name: 'Shopping',
    type: 'expense',
    iconName: 'shopping_bag',
    colorHex: 'b08080',
  ),
  StarterCategory(
    key: 'entertainment',
    name: 'Entertainment',
    type: 'expense',
    iconName: 'movie',
    colorHex: '8e6b8a',
  ),
  StarterCategory(
    key: 'health',
    name: 'Health',
    type: 'expense',
    iconName: 'favorite',
    colorHex: 'b85c5c',
  ),
  StarterCategory(
    key: 'education',
    name: 'Education',
    type: 'expense',
    iconName: 'school',
    colorHex: '5a7588',
  ),
  StarterCategory(
    key: 'travel',
    name: 'Travel',
    type: 'expense',
    iconName: 'flight',
    colorHex: '4a7a8c',
  ),
  StarterCategory(
    key: 'personal',
    name: 'Personal Care',
    type: 'expense',
    iconName: 'spa',
    colorHex: 'c4a484',
  ),
  StarterCategory(
    key: 'gifts',
    name: 'Gifts',
    type: 'expense',
    iconName: 'card_giftcard',
    colorHex: 'b89968',
  ),
  // ----- Income -----
  StarterCategory(
    key: 'salary',
    name: 'Salary',
    type: 'income',
    iconName: 'work',
    colorHex: '5a7558',
  ),
  StarterCategory(
    key: 'freelance',
    name: 'Freelance',
    type: 'income',
    iconName: 'laptop',
    colorHex: '6b8e8e',
  ),
  StarterCategory(
    key: 'other_income',
    name: 'Other Income',
    type: 'income',
    iconName: 'attach_money',
    colorHex: '708070',
  ),
];

/// Maps the icon names from [kStarterCategories] to Material `IconData`.
/// Used by the setup wizard chip preview; the global category renderer
/// (P2 work) will eventually own a more complete lookup table.
const setupIconLookup = <String, IconData>{
  'restaurant': Icons.restaurant,
  'shopping_basket': Icons.shopping_basket,
  'directions_car': Icons.directions_car,
  'receipt_long': Icons.receipt_long,
  'home': Icons.home,
  'shopping_bag': Icons.shopping_bag,
  'movie': Icons.movie,
  'favorite': Icons.favorite,
  'school': Icons.school,
  'flight': Icons.flight,
  'spa': Icons.spa,
  'card_giftcard': Icons.card_giftcard,
  'work': Icons.work,
  'laptop': Icons.laptop,
  'attach_money': Icons.attach_money,
};

const kMinCategoryPicks = 4;
const kMaxCategoryPicks = 6;
