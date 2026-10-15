import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/pick_grid.dart';
import '../../../data/local/app_database.dart';
import '../../categories/data/category_catalog.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/data/wallet_catalog.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/recurring_catalog.dart';
import '../providers/recurring_controller.dart';

/// Create / edit a recurring rule (PRD §6.6). When [existing] is non-null
/// the form is pre-filled and submits via [RecurringController.edit];
/// otherwise via `.create`.
class AddRecurringScreen extends ConsumerStatefulWidget {
  const AddRecurringScreen({this.existing, super.key});

  /// `null` = add mode, non-null = edit mode.
  final RecurringRule? existing;

  @override
  ConsumerState<AddRecurringScreen> createState() => _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _formKey = GlobalKey<FormState>();
  late RecurringFormData _form;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _intervalCtrl;
  bool _showScopeError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      final template = decodeRecurringTemplate(existing.transactionTemplate);
      _form = RecurringFormData(
        id: existing.id,
        walletId: template['walletId'] as String?,
        categoryId: template['categoryId'] as String?,
        type: (template['type'] as String?) ?? 'expense',
        amount: ((template['amount'] as num?) ?? 0).toDouble(),
        note: template['note'] as String?,
        frequency: existing.frequency,
        interval: existing.interval,
        mode: existing.mode,
        startDate: existing.startDate,
        endDate: existing.endDate,
      );
      _amountCtrl = TextEditingController(text: _formatAmount(_form.amount));
      _noteCtrl = TextEditingController(text: _form.note ?? '');
      _intervalCtrl =
          TextEditingController(text: _form.interval.toString());
    } else {
      _form = RecurringFormData();
      _amountCtrl = TextEditingController();
      _noteCtrl = TextEditingController();
      _intervalCtrl = TextEditingController(text: '1');
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  String _formatAmount(double n) {
    if (n == n.truncateToDouble()) return n.toStringAsFixed(0);
    return n.toString();
  }

  Future<void> _submit() async {
    // Both checks run before returning, so a missing scope doesn't hide
    // the field errors (and vice versa).
    final formOk = _formKey.currentState!.validate();
    final scopeOk = _form.hasScope;
    setState(() => _showScopeError = !scopeOk);
    if (!formOk || !scopeOk) return;

    _form.amount = double.parse(_amountCtrl.text.trim());
    _form.interval = int.parse(_intervalCtrl.text.trim());
    final rawNote = _noteCtrl.text.trim();
    _form.note = rawNote.isEmpty ? null : rawNote;

    final controller = ref.read(recurringControllerProvider.notifier);
    if (widget.existing == null) {
      await controller.create(_form);
    } else {
      await controller.edit(_form);
    }
    if (!mounted) return;
    final result = ref.read(recurringControllerProvider);
    if (result.hasError) return;
    context.pop(true);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        _form.startDate = picked;
        // The end-date picker clamps to `firstDate: startDate`, but only
        // at pick time — moving the start forward afterwards could leave
        // an end date behind it, producing a rule that never fires.
        final end = _form.endDate;
        if (end != null && end.isBefore(picked)) _form.endDate = null;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.endDate ??
          _form.startDate.add(const Duration(days: 365)),
      firstDate: _form.startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _form.endDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(recurringControllerProvider);
    final categories =
        ref.watch(categoriesListProvider).value ?? const <Category>[];
    final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
    final isEdit = widget.existing != null;

    // Filter categories by the selected type (expense vs income).
    final filteredCategories =
        categories.where((c) => c.type == _form.type).toList();

    // Currency prefix on the amount field follows the chosen wallet.
    Wallet? selectedWallet;
    if (_form.walletId != null) {
      for (final w in wallets) {
        if (w.id == _form.walletId) {
          selectedWallet = w;
          break;
        }
      }
    }
    final currencyCode = selectedWallet?.currency ?? '';

    ref.listen<AsyncValue<void>>(recurringControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save recurring rule. Try again.'),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit recurring' : 'New recurring'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // --- Type ----------------------------------------------------
              _SectionLabel('Type'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                ],
                selected: {_form.type},
                onSelectionChanged: (s) => setState(() {
                  _form.type = s.first;
                  // Drop the category if it no longer matches the new type.
                  if (_form.categoryId != null) {
                    final stillValid = categories.any(
                      (c) => c.id == _form.categoryId && c.type == _form.type,
                    );
                    if (!stillValid) _form.categoryId = null;
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Wallet --------------------------------------------------
              _SectionLabel('Wallet'),
              const SizedBox(height: AppSpacing.sm),
              if (wallets.isEmpty)
                _MutedHint(text: 'No wallets yet. Add one first.')
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

              // --- Category ------------------------------------------------
              _SectionLabel('Category'),
              const SizedBox(height: AppSpacing.sm),
              if (filteredCategories.isEmpty)
                _MutedHint(
                  text: 'No ${_form.type} categories yet. '
                      'Add one in Categories first.',
                )
              else
                PickGrid(
                  items: [
                    for (final c in filteredCategories)
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

              // --- Amount --------------------------------------------------
              _SectionLabel('Amount'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText:
                      currencyCode.isEmpty ? '' : '$currencyCode  ',
                ),
                validator: Validators.amount,
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Note ----------------------------------------------------
              _SectionLabel('Note (optional)'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 1,
                maxLength: Validators.noteMaxLength,
                validator: (v) => Validators.optionalText(v, label: 'Note'),
                decoration: const InputDecoration(
                  labelText: 'e.g. Rent, Netflix',
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Frequency ----------------------------------------------
              _SectionLabel('Frequency'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: [
                  for (final f in kRecurringFrequencyCatalog)
                    ButtonSegment(value: f.key, label: Text(f.label)),
                ],
                selected: {_form.frequency},
                onSelectionChanged: (s) =>
                    setState(() => _form.frequency = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Interval -----------------------------------------------
              _SectionLabel('Interval'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _intervalCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Every N ${_intervalUnit(_form.frequency)}(s)',
                ),
                validator: (v) =>
                    Validators.positiveInt(v, label: 'Interval'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Mode ---------------------------------------------------
              _SectionLabel('Mode'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: [
                  for (final m in kRecurringModeCatalog)
                    ButtonSegment(value: m.key, label: Text(m.label)),
                ],
                selected: {_form.mode},
                onSelectionChanged: (s) =>
                    setState(() => _form.mode = s.first),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _form.mode == 'reminder'
                    ? 'Reminder mode ships in P7 with notifications. '
                        'For now it behaves like Auto.'
                    : 'Auto materializes a transaction on each due date.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Start date ---------------------------------------------
              _SectionLabel('Start date'),
              const SizedBox(height: AppSpacing.sm),
              _PickerTile(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(_form.startDate),
                onTap: _pickStartDate,
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- End date (optional) ------------------------------------
              _SectionLabel('End date (optional)'),
              const SizedBox(height: AppSpacing.sm),
              _PickerTile(
                icon: Icons.event_busy_outlined,
                label: _form.endDate == null
                    ? 'No end date'
                    : _formatDate(_form.endDate!),
                onTap: _pickEndDate,
                trailing: _form.endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear end date',
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            setState(() => _form.endDate = null),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_showScopeError)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    'Pick both a wallet and a category.',
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
                    : Text(isEdit ? 'Save changes' : 'Create rule'),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

String _intervalUnit(String frequency) {
  switch (frequency) {
    case 'daily':
      return 'day';
    case 'weekly':
      return 'week';
    case 'monthly':
      return 'month';
    case 'yearly':
      return 'year';
    default:
      return 'unit';
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
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

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (trailing != null)
                trailing!
              else
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
