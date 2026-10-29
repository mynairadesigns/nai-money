import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/currency_picker_sheet.dart';
import '../../billing/data/free_tier_exception.dart';
import '../../billing/widgets/upsell_sheet.dart';
import '../../setup/data/setup_catalog.dart';
import '../data/wallet_catalog.dart';
import '../providers/wallets_controller.dart';

/// Add Wallet form (PRD §6.2). Fields: name, type, currency, opening
/// balance, icon, color. On submit → WalletsController.create → pop.
class AddWalletScreen extends ConsumerStatefulWidget {
  const AddWalletScreen({super.key});

  @override
  ConsumerState<AddWalletScreen> createState() => _AddWalletScreenState();
}

class _AddWalletScreenState extends ConsumerState<AddWalletScreen> {
  final _formKey = GlobalKey<FormState>();
  final _form = WalletFormData();
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    // Apply the first type's defaults so icon + color reflect the default.
    final firstType = kWalletTypeCatalog.first;
    _form
      ..type = firstType.key
      ..iconName = firstType.iconName
      ..colorHex = firstType.defaultColorHex;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _form
      ..name = _nameCtrl.text
      ..openingBalance = double.tryParse(_balanceCtrl.text.trim()) ?? 0;
    await ref.read(walletsControllerProvider.notifier).create(_form);
    if (!mounted) return;
    final result = ref.read(walletsControllerProvider);
    if (result.hasError) return;
    context.pop();
  }

  String _symbolFor(String code) =>
      kCurrencyCatalog.firstWhere(
        (c) => c.code == code,
        orElse: () => kCurrencyCatalog.first,
      ).symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(walletsControllerProvider);

    ref.listen<AsyncValue<void>>(walletsControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        final err = next.error;
        if (err is FreeTierExceeded) {
          showUpsellSheet(context, err.reason);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save wallet. Try again.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Add wallet')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextFormField(
                controller: _nameCtrl,
                maxLength: Validators.nameMaxLength,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Everyday checking',
                  counterText: '',
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => Validators.requiredText(v, label: 'Name'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Type'),
              const SizedBox(height: AppSpacing.sm),
              _WalletTypeGrid(
                selected: _form.type,
                onPick: (key) => setState(() {
                  final t = kWalletTypeCatalog.firstWhere((x) => x.key == key);
                  _form.type = t.key;
                  // Move icon + color presets to match the type.
                  _form.iconName = t.iconName;
                  _form.colorHex = t.defaultColorHex;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Currency'),
              const SizedBox(height: AppSpacing.sm),
              _CurrencyField(
                code: _form.currency,
                onTap: () async {
                  final picked = await showCurrencyPicker(
                    context,
                    selected: _form.currency,
                  );
                  if (picked != null && mounted) {
                    setState(() => _form.currency = picked);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Opening balance'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _balanceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '${_symbolFor(_form.currency)} ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter 0 if none';
                  // Negative is legitimate here (credit cards, overdrafts),
                  // so only the magnitude is bounded.
                  return Validators.amount(
                    v,
                    label: 'Opening balance',
                    allowZero: true,
                    allowNegative: true,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Icon'),
              const SizedBox(height: AppSpacing.sm),
              _IconPicker(
                selected: _form.iconName,
                onPick: (name) => setState(() => _form.iconName = name),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Color'),
              const SizedBox(height: AppSpacing.sm),
              _ColorPicker(
                selectedHex: _form.colorHex,
                onPick: (hex) => setState(() => _form.colorHex = hex),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: commitState.isLoading ? null : _submit,
                child: commitState.isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : const Text('Save wallet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in kWalletIconCatalog.entries)
          GestureDetector(
            onTap: () => onPick(entry.key),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected == entry.key
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: AppBorderRadius.md,
                border: selected == entry.key
                    ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: Icon(
                entry.value,
                size: 22,
                color: selected == entry.key
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _WalletTypeGrid extends StatelessWidget {
  const _WalletTypeGrid({required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final t in kWalletTypeCatalog)
              SizedBox(
                width: cardWidth,
                child: _WalletTypeCard(
                  option: t,
                  selected: selected == t.key,
                  onTap: () => onPick(t.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WalletTypeCard extends StatelessWidget {
  const _WalletTypeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final WalletTypeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = Color(int.parse('FF${option.defaultColorHex}', radix: 16));
    final icon =
        kWalletIconCatalog[option.iconName] ?? Icons.account_balance_wallet;

    final bg = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
        : theme.colorScheme.surface;
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final borderWidth = selected ? 1.5 : 1.0;

    return Material(
      color: bg,
      borderRadius: AppBorderRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: AppBorderRadius.lg,
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: AppBorderRadius.full,
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 12,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyField extends StatelessWidget {
  const _CurrencyField({required this.code, required this.onTap});
  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final option = kCurrencyCatalog.firstWhere(
      (c) => c.code == code,
      orElse: () => kCurrencyCatalog.first,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.base,
      child: InputDecorator(
        decoration: const InputDecoration(border: OutlineInputBorder()),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppBorderRadius.full,
              ),
              child: Text(
                option.symbol,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(option.code, style: theme.textTheme.titleSmall),
                  Text(
                    option.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selectedHex, required this.onPick});
  final String selectedHex;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final hex in kWalletColorCatalog)
          GestureDetector(
            onTap: () => onPick(hex),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(int.parse('FF$hex', radix: 16)),
                shape: BoxShape.circle,
                border: selectedHex == hex
                    ? Border.all(color: theme.colorScheme.primary, width: 2.5)
                    : null,
              ),
              child: selectedHex == hex
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
          ),
      ],
    );
  }
}
