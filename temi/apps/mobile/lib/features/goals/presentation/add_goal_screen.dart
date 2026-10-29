import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/currency_picker_sheet.dart';
import '../../../data/local/app_database.dart';
import '../../setup/data/setup_catalog.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/goal_catalog.dart';
import '../providers/goals_controller.dart';

/// Create / edit a goal. When [existing] is non-null the form is
/// pre-filled and submits via `GoalsController.edit`, otherwise it
/// submits via `.create`. PRD §6.8.
class AddGoalScreen extends ConsumerStatefulWidget {
  const AddGoalScreen({this.existing, super.key});

  /// `null` = add mode, non-null = edit mode.
  final Goal? existing;

  @override
  ConsumerState<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends ConsumerState<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  late GoalFormData _form;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _form = GoalFormData(
        id: existing.id,
        name: existing.name,
        targetAmount: existing.targetAmount,
        currency: existing.currency,
        deadline: existing.deadline,
        walletId: existing.walletId,
        iconName: existing.iconName,
        colorHex: existing.color,
      );
      _nameCtrl = TextEditingController(text: existing.name);
      _amountCtrl =
          TextEditingController(text: _formatAmount(existing.targetAmount));
    } else {
      _form = GoalFormData();
      _nameCtrl = TextEditingController();
      _amountCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String _formatAmount(double n) {
    if (n == n.truncateToDouble()) return n.toStringAsFixed(0);
    return n.toString();
  }

  String _symbolFor(String code) =>
      kCurrencyCatalog.firstWhere(
        (c) => c.code == code,
        orElse: () => kCurrencyCatalog.first,
      ).symbol;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _form
      ..name = _nameCtrl.text
      ..targetAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    final controller = ref.read(goalsControllerProvider.notifier);
    if (widget.existing == null) {
      await controller.create(_form);
    } else {
      await controller.edit(_form);
    }
    if (!mounted) return;
    final result = ref.read(goalsControllerProvider);
    if (result.hasError) return;
    context.pop(true);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = _form.deadline ?? now.add(const Duration(days: 90));
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 30),
      initialDate: initial.isBefore(now) ? now : initial,
    );
    if (picked != null && mounted) {
      setState(() => _form.deadline = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(goalsControllerProvider);
    final wallets = ref.watch(walletsListProvider).value ?? const <Wallet>[];
    final isEdit = widget.existing != null;

    ref.listen<AsyncValue<void>>(goalsControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save goal. Try again.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit goal' : 'New goal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // --- Name -------------------------------------------------
              const _SectionLabel('Name'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLength: Validators.nameMaxLength,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Emergency fund',
                  counterText: '',
                ),
                validator: (v) => Validators.requiredText(v, label: 'Name'),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Target amount ----------------------------------------
              const _SectionLabel('Target amount'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target',
                  prefixText: '${_symbolFor(_form.currency)} ',
                ),
                validator: (v) {
                  final base = Validators.amount(v, label: 'Target');
                  if (base != null) return base;
                  // Editing down below what's already saved would render
                  // the goal permanently >100% complete.
                  final saved = widget.existing?.currentAmount;
                  if (saved != null && double.parse(v!.trim()) < saved) {
                    return 'Below the ${saved.toStringAsFixed(2)} '
                        'already saved';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Currency ---------------------------------------------
              const _SectionLabel('Currency'),
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

              // --- Deadline ---------------------------------------------
              const _SectionLabel('Deadline'),
              const SizedBox(height: AppSpacing.sm),
              _DeadlineTile(
                deadline: _form.deadline,
                onTap: _pickDeadline,
                onClear: () => setState(() => _form.deadline = null),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Optional — without one we'll just track progress.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Linked wallet ----------------------------------------
              const _SectionLabel('Linked wallet'),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                initialValue: _form.walletId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None'),
                  ),
                  for (final w in wallets)
                    DropdownMenuItem<String?>(
                      value: w.id,
                      child: Text(w.name),
                    ),
                ],
                onChanged: (v) => setState(() => _form.walletId = v),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Optional — for grouping; doesn't enforce balance interactions.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Icon -------------------------------------------------
              const _SectionLabel('Icon'),
              const SizedBox(height: AppSpacing.sm),
              _IconPicker(
                selected: _form.iconName,
                onPick: (name) => setState(() => _form.iconName = name),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Color ------------------------------------------------
              const _SectionLabel('Color'),
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
                    : Text(isEdit ? 'Save changes' : 'Create goal'),
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

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({
    required this.deadline,
    required this.onTap,
    required this.onClear,
  });
  final DateTime? deadline;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDeadline = deadline != null;
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
                  hasDeadline ? _formatDate(deadline!) : 'Pick a deadline',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasDeadline
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasDeadline)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear deadline',
                  onPressed: onClear,
                )
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
        for (final entry in kCategoryIconCatalog.entries)
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
        for (final hex in kCategoryColorCatalog)
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

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
