import 'package:flutter/material.dart';

/// Wallet type options per PRD §6.2 — cash, bank, credit_card, e_wallet,
/// investment. The form's type dropdown reads from this list; the
/// `Wallets.type` Drift column stores the [key].
class WalletTypeOption {
  const WalletTypeOption({
    required this.key,
    required this.label,
    required this.iconName,
    required this.defaultColorHex,
  });
  final String key;
  final String label;
  final String iconName;
  final String defaultColorHex;
}

const kWalletTypeCatalog = <WalletTypeOption>[
  WalletTypeOption(
    key: 'cash',
    label: 'Cash',
    iconName: 'payments',
    defaultColorHex: '8a4f37',
  ),
  WalletTypeOption(
    key: 'bank',
    label: 'Bank',
    iconName: 'account_balance',
    defaultColorHex: '526256',
  ),
  WalletTypeOption(
    key: 'credit_card',
    label: 'Credit Card',
    iconName: 'credit_card',
    defaultColorHex: '708090',
  ),
  WalletTypeOption(
    key: 'e_wallet',
    label: 'E-Wallet',
    iconName: 'smartphone',
    defaultColorHex: '6b8e8e',
  ),
  WalletTypeOption(
    key: 'investment',
    label: 'Investment',
    iconName: 'trending_up',
    defaultColorHex: 'b89968',
  ),
];

/// Wallet-appropriate icons offered in the Add Wallet form's icon picker.
/// (Smaller than the full Material set — keeps the picker scannable.)
const kWalletIconCatalog = <String, IconData>{
  'payments': Icons.payments,
  'account_balance': Icons.account_balance,
  'credit_card': Icons.credit_card,
  'smartphone': Icons.smartphone,
  'trending_up': Icons.trending_up,
  'savings': Icons.savings,
  'attach_money': Icons.attach_money,
  'monetization_on': Icons.monetization_on,
  'currency_exchange': Icons.currency_exchange,
  'account_balance_wallet': Icons.account_balance_wallet,
};

/// Warm-palette color presets aligned with DESIGN.md tokens. Stored as
/// 6-char hex (no `#` prefix) to match the rest of the codebase
/// (`Categories.color`, `StarterCategory.colorHex`).
const kWalletColorCatalog = <String>[
  '8a4f37', // warm clay (primary)
  '526256', // muted sage (secondary)
  'c4a484', // sand
  'b08080', // dusty rose
  '6b8e8e', // soft teal
  'b89968', // goldenrod
  '8e6b8a', // plum
  '5a7558', // forest
  'c47a5a', // terracotta
  '708090', // slate
];
