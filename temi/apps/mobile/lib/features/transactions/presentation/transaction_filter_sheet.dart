import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/pick_grid.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/data/wallet_catalog.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/transactions_filter.dart';

/// Opens the transactions filter sheet. Returns the new filter on Apply,
/// `const TransactionsFilter()` on Clear, or `null` on dismiss.
Future<TransactionsFilter?> showTransactionFilterSheet(
  BuildContext context, {
  required TransactionsFilter initial,
}) {
  return showModalBottomSheet<TransactionsFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => _TransactionFilterSheet(initial: initial),
  );
}

class _TransactionFilterSheet extends ConsumerStatefulWidget {
  const _TransactionFilterSheet({required this.initial});
  final TransactionsFilter initial;

  @override
  ConsumerState<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState
    extends ConsumerState<_TransactionFilterSheet> {
  late Set<String> _types;
  late Set<String> _walletIds;
  late Set<String> _categoryIds;
  DateTimeRange? _dateRange;
  double? _minAmount;
  double? _maxAmount;

  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;

  @override
  void initState() {
    super.initState();
    _types = {...widget.initial.types};
    _walletIds = {...widget.initial.walletIds};
    _categoryIds = {...widget.initial.categoryIds};
    _dateRange = widget.initial.dateRange;
    _minAmount = widget.initial.minAmount;
    _maxAmount = widget.initial.maxAmount;
    _minCtrl = TextEditingController(
      text: _minAmount == null ? '' : _minAmount.toString(),
    );
    _maxCtrl = TextEditingController(
      text: _maxAmount == null ? '' : _maxAmount.toString(),
    );
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  /// Builds Expense + Income subsections with a `PickGrid` each.
  List<Widget> _buildCategorySections(List<Category> categories) {
    final expenses = categories.where((c) => c.type == 'expense').toList();
    final incomes = categories.where((c) => c.type == 'income').toList();
    final out = <Widget>[];
    if (expenses.isNotEmpty) {
      out.add(_SubSectionLabel('Expense'));
      out.add(const SizedBox(height: AppSpacing.xs));
      out.add(PickGrid(
        items: [
          for (final c in expenses)
            PickItem(
              key: c.id,
              label: c.name,
              iconData: iconForCategory(c.iconName),
              colorHex: c.color,
            ),
        ],
        selected: _categoryIds,
        onToggle: (id, sel) => setState(() {
          if (sel) {
            _categoryIds.add(id);
          } else {
            _categoryIds.remove(id);
          }
        }),
      ));
    }
    if (incomes.isNotEmpty) {
      if (expenses.isNotEmpty) {
        out.add(const SizedBox(height: AppSpacing.md));
      }
      out.add(_SubSectionLabel('Income'));
      out.add(const SizedBox(height: AppSpacing.xs));
      out.add(PickGrid(
        items: [
          for (final c in incomes)
            PickItem(
              key: c.id,
              label: c.name,
              iconData: iconForCategory(c.iconName),
              colorHex: c.color,
            ),
        ],
        selected: _categoryIds,
        onToggle: (id, sel) => setState(() {
          if (sel) {
            _categoryIds.add(id);
          } else {
            _categoryIds.remove(id);
          }
        }),
      ));
    }
    return out;
  }

  /// Inline error for one of the amount boxes. Empty is fine (the bound
  /// is simply unset); text that doesn't parse is not.
  String? _amountFieldError(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Not a number';
    if (parsed < 0) return "Can't be negative";
    return null;
  }

  bool get _rangeInverted {
    final min = _minAmount;
    final max = _maxAmount;
    return min != null && max != null && min > max;
  }

  bool get _canApply =>
      !_rangeInverted &&
      _amountFieldError(_minCtrl.text) == null &&
      _amountFieldError(_maxCtrl.text) == null;

  TransactionsFilter _buildResult() {
    return TransactionsFilter(
      types: _types,
      walletIds: _walletIds,
      categoryIds: _categoryIds,
      dateRange: _dateRange,
      minAmount: _minAmount,
      maxAmount: _maxAmount,
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    // Archived wallets remain in the picker so historical txns are
    // still reachable via filter.
    final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
    final categories =
        ref.watch(categoriesListProvider).value ?? const <Category>[];

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter transactions',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const TransactionsFilter(),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Type ---------------------------------------------------
            const _SectionLabel('Type'),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in const [
                  ('expense', 'Expense'),
                  ('income', 'Income'),
                  ('transfer', 'Transfer'),
                ])
                  FilterChip(
                    label: Text(entry.$2),
                    selected: _types.contains(entry.$1),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _types.add(entry.$1);
                      } else {
                        _types.remove(entry.$1);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Date range --------------------------------------------
            const _SectionLabel('Date range'),
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: AppBorderRadius.md,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _pickDateRange,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _dateRange == null
                              ? 'Any date'
                              : _formatRange(_dateRange!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _dateRange == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear date range',
                          onPressed: () =>
                              setState(() => _dateRange = null),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // --- Wallets ------------------------------------------------
            const _SectionLabel('Wallets'),
            const SizedBox(height: AppSpacing.sm),
            if (wallets.isEmpty)
              Text(
                'No wallets yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              PickGrid(
                items: [
                  for (final w in wallets)
                    PickItem(
                      key: w.id,
                      label: w.name,
                      iconData: _walletIconFor(w.iconName),
                      colorHex: w.color,
                    ),
                ],
                selected: _walletIds,
                onToggle: (id, sel) => setState(() {
                  if (sel) {
                    _walletIds.add(id);
                  } else {
                    _walletIds.remove(id);
                  }
                }),
              ),
            const SizedBox(height: AppSpacing.lg),

            // --- Categories --------------------------------------------
            const _SectionLabel('Categories'),
            const SizedBox(height: AppSpacing.sm),
            if (categories.isEmpty)
              Text(
                'No categories yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ..._buildCategorySections(categories),
            const SizedBox(height: AppSpacing.lg),

            // --- Amount -------------------------------------------------
            const _SectionLabel('Amount'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Min',
                      border: const OutlineInputBorder(),
                      errorText: _amountFieldError(_minCtrl.text),
                    ),
                    onChanged: (raw) {
                      final trimmed = raw.trim();
                      setState(() {
                        _minAmount =
                            trimmed.isEmpty ? null : double.tryParse(trimmed);
                      });
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Max',
                      border: const OutlineInputBorder(),
                      errorText: _amountFieldError(_maxCtrl.text),
                    ),
                    onChanged: (raw) {
                      final trimmed = raw.trim();
                      setState(() {
                        _maxAmount =
                            trimmed.isEmpty ? null : double.tryParse(trimmed);
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_rangeInverted) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Min must be less than or equal to Max.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            FilledButton(
              // An inverted or unparseable range would silently return
              // zero rows, which reads as "no transactions" rather than
              // "bad filter".
              onPressed: _canApply
                  ? () => Navigator.of(context).pop(_buildResult())
                  : null,
              child: const Text('Apply'),
            ),
          ],
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

class _SubSectionLabel extends StatelessWidget {
  const _SubSectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Resolves a wallet's stored `iconName` to a Material IconData using the
/// shared [kWalletIconCatalog], with a generic-wallet fallback.
IconData _walletIconFor(String iconName) =>
    kWalletIconCatalog[iconName] ?? Icons.account_balance_wallet_outlined;

String _formatRange(DateTimeRange r) =>
    '${_formatDate(r.start)} – ${_formatDate(r.end)}';

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
