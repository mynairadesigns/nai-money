import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/currency_picker_sheet.dart';
import '../../../core/widgets/pick_grid.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../budget_generator/presentation/budget_generator_sheet.dart';
import '../../setup/data/setup_catalog.dart';
import '../../wallets/data/wallet_catalog.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/budget_catalog.dart';
import '../providers/budgets_controller.dart';

/// Create / edit a budget. When [existing] is non-null the form is
/// pre-filled and submits via `BudgetsController.edit`, otherwise it
/// submits via `.create`. PRD §6.5.
class AddBudgetScreen extends ConsumerStatefulWidget {
  const AddBudgetScreen({this.existing, super.key});

  /// `null` = add mode, non-null = edit mode.
  final Budget? existing;

  @override
  ConsumerState<AddBudgetScreen> createState() => _AddBudgetScreenState();
}

class _AddBudgetScreenState extends ConsumerState<AddBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  late BudgetFormData _form;
  late final TextEditingController _amountCtrl;
  bool _showScopeError = false;
  bool _showRangeError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _form = BudgetFormData(
        id: existing.id,
        categoryId: existing.categoryId,
        walletId: existing.walletId,
        period: existing.period,
        amount: existing.amount,
        currency: existing.currency,
        rollover: existing.rollover,
        thresholdPercent: existing.thresholdPercent,
        startDate: existing.startDate,
        endDate: existing.endDate,
      );
      _amountCtrl = TextEditingController(text: _formatAmount(existing.amount));
    } else {
      _form = BudgetFormData();
      _amountCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  String _formatAmount(double n) {
    if (n == n.truncateToDouble()) return n.toStringAsFixed(0);
    return n.toString();
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    // Scope and the custom range are picker-driven, so they can't be Form
    // validators. Evaluate them *alongside* validate() rather than before
    // it — returning early used to suppress the amount error whenever the
    // scope was also missing, so fixing one revealed the other.
    final scopeOk = _form.hasScope;
    // A custom period with no end date silently became start+30d in the
    // controller, which is not what the user picked.
    final rangeOk = _form.period != 'custom' || _form.endDate != null;
    setState(() {
      _showScopeError = !scopeOk;
      _showRangeError = !rangeOk;
    });
    if (!formOk || !scopeOk || !rangeOk) return;
    _form.amount = double.parse(_amountCtrl.text.trim());

    final controller = ref.read(budgetsControllerProvider.notifier);
    if (widget.existing == null) {
      await controller.create(_form);
    } else {
      await controller.edit(_form);
    }
    if (!mounted) return;
    final result = ref.read(budgetsControllerProvider);
    if (result.hasError) return;
    context.pop(true);
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this budget?'),
        content: const Text(
          'This removes the budget. Transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(budgetsControllerProvider.notifier).delete(existing.id);
    if (!mounted) return;
    final result = ref.read(budgetsControllerProvider);
    if (result.hasError) return;
    // Pop off the form AND the detail screen below it.
    context.pop();
    if (mounted) context.pop();
  }

  Future<void> _pickDateRange() async {
    final initial = DateTimeRange(
      start: _form.startDate,
      end: _form.endDate ??
          _form.startDate.add(const Duration(days: 30)),
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _form.startDate = picked.start;
        _form.endDate = picked.end;
        _showRangeError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(budgetsControllerProvider);
    final categories =
        ref.watch(categoriesListProvider).value ?? const <Category>[];
    final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
    final isEdit = widget.existing != null;

    ref.listen<AsyncValue<void>>(budgetsControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save budget. Try again.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit budget' : 'New budget'),
        actions: [
          if (isEdit)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // --- Generate with AI (P5.3) ------------------------------
              _AIBudgetGeneratorRow(
                onTap: () async {
                  final pick = await showBudgetGenerator(
                    context,
                    defaultCurrency: _form.currency,
                  );
                  if (pick == null || !mounted) return;
                  setState(() {
                    _form.categoryId = pick.categoryId;
                    _form.amount = pick.suggestedAmount;
                    _form.currency = pick.currency;
                    _amountCtrl.text = _formatAmount(pick.suggestedAmount);
                    _showScopeError = false;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Category ---------------------------------------------
              _SectionLabel('Category (optional)'),
              const SizedBox(height: AppSpacing.sm),
              if (categories.isEmpty)
                _MutedHint(text: 'No categories yet.')
              else
                PickGrid(
                  items: [
                    for (final c in categories)
                      PickItem(
                        key: c.id,
                        label: c.name,
                        iconData: iconForCategory(c.iconName),
                        colorHex: c.color,
                      ),
                  ],
                  selected: {
                    if (_form.categoryId != null) _form.categoryId!,
                  },
                  onToggle: (key, sel) => setState(() {
                    _form.categoryId = sel ? key : null;
                    if (sel) _showScopeError = false;
                  }),
                ),
              const SizedBox(height: AppSpacing.lg),

              // --- Wallet -----------------------------------------------
              _SectionLabel('Wallet (optional)'),
              const SizedBox(height: AppSpacing.sm),
              if (wallets.isEmpty)
                _MutedHint(text: 'No wallets yet.')
              else
                PickGrid(
                  items: [
                    for (final w in wallets)
                      PickItem(
                        key: w.id,
                        label: w.name,
                        iconData: kWalletIconCatalog[w.iconName] ??
                            Icons.account_balance_wallet_outlined,
                        colorHex: w.color,
                      ),
                  ],
                  selected: {
                    if (_form.walletId != null) _form.walletId!,
                  },
                  onToggle: (key, sel) => setState(() {
                    _form.walletId = sel ? key : null;
                    if (sel) _showScopeError = false;
                  }),
                ),
              const SizedBox(height: AppSpacing.lg),

              // --- Period -----------------------------------------------
              _SectionLabel('Period'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: [
                  for (final p in kBudgetPeriodCatalog)
                    ButtonSegment(value: p.key, label: Text(p.label)),
                ],
                selected: {_form.period},
                onSelectionChanged: (s) =>
                    setState(() => _form.period = s.first),
              ),
              if (_form.period == 'custom') ...[
                const SizedBox(height: AppSpacing.md),
                _DateRangeTile(
                  start: _form.startDate,
                  end: _form.endDate,
                  onTap: _pickDateRange,
                ),
                if (_showRangeError) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Pick a start and end date for the custom period.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),

              // --- Amount -----------------------------------------------
              _SectionLabel('Amount'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${_form.currency}  ',
                ),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Currency ---------------------------------------------
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

              // --- Threshold --------------------------------------------
              _SectionLabel('Alert at'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final pct in kBudgetThresholdOptions)
                    ChoiceChip(
                      label: Text('$pct%'),
                      selected: _form.thresholdPercent == pct,
                      onSelected: (_) =>
                          setState(() => _form.thresholdPercent = pct),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Rollover ---------------------------------------------
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Roll over unspent into next period'),
                value: _form.rollover,
                onChanged: (v) => setState(() => _form.rollover = v),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_showScopeError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Pick at least one category or wallet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),

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
                    : Text(isEdit ? 'Save changes' : 'Create budget'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AIBudgetGeneratorRow extends StatelessWidget {
  const _AIBudgetGeneratorRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: AppBorderRadius.lg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Generate with AI',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      'Suggested amounts based on your spending',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onPrimaryContainer,
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

class _MutedHint extends StatelessWidget {
  const _MutedHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _DateRangeTile extends StatelessWidget {
  const _DateRangeTile({
    required this.start,
    required this.end,
    required this.onTap,
  });
  final DateTime start;
  final DateTime? end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasRange = end != null;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: AppBorderRadius.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                  hasRange
                      ? '${_formatDate(start)} – ${_formatDate(end!)}'
                      : 'Pick a date range',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasRange
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
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

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
