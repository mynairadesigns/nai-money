import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/currency_picker_sheet.dart';
import '../../../data/local/app_database.dart';
import '../../contacts/providers/contacts_list_provider.dart';
import '../../contacts/widgets/contact_picker_sheet.dart';
import '../../setup/data/setup_catalog.dart';
import '../providers/debts_controller.dart';

/// Create / edit a debt. When [existing] is non-null the form is
/// pre-filled and submits via `DebtsController.edit`, otherwise it
/// submits via `.create`. PRD §6.7.
class AddDebtScreen extends ConsumerStatefulWidget {
  const AddDebtScreen({this.existing, super.key});

  /// `null` = add mode, non-null = edit mode.
  final Debt? existing;

  @override
  ConsumerState<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends ConsumerState<AddDebtScreen> {
  final _formKey = GlobalKey<FormState>();
  late DebtFormData _form;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  bool _showContactError = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _form = DebtFormData(
        id: existing.id,
        type: existing.type,
        contactName: existing.contactName,
        contactId: existing.contactId,
        originalAmount: existing.originalAmount,
        currency: existing.currency,
        dueDate: existing.dueDate,
        notes: existing.notes,
      );
      _amountCtrl = TextEditingController(
        text: _formatAmount(existing.originalAmount),
      );
      _notesCtrl = TextEditingController(text: existing.notes ?? '');
    } else {
      _form = DebtFormData();
      _amountCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _formatAmount(double n) {
    if (n == n.truncateToDouble()) return n.toStringAsFixed(0);
    return n.toString();
  }

  Future<void> _pickContact() async {
    final picked = await showContactPicker(context, initialId: _form.contactId);
    if (picked == null || !mounted) return;
    final rows =
        ref.read(contactsListProvider).value ?? const <Contact>[];
    final match = rows.where((c) => c.id == picked).toList();
    setState(() {
      _form.contactId = picked;
      if (match.isNotEmpty) _form.contactName = match.first.name;
      _showContactError = false;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _form.dueDate ?? DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _form.dueDate = picked);
    }
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    // The contact is a tap tile, not a field, so it can't carry a Form
    // validator — surface it inline alongside the field errors instead of
    // as a SnackBar fired after validate() already passed.
    final contactOk = _form.contactId != null;
    setState(() => _showContactError = !contactOk);
    if (!formOk || !contactOk) return;
    _form.originalAmount = double.parse(_amountCtrl.text.trim());
    _form.notes = _notesCtrl.text.trim();
    final ctrl = ref.read(debtsControllerProvider.notifier);
    if (widget.existing == null) {
      await ctrl.create(_form);
    } else {
      await ctrl.edit(_form);
    }
    if (!mounted) return;
    final result = ref.read(debtsControllerProvider);
    if (result.hasError) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commitState = ref.watch(debtsControllerProvider);
    final isEdit = widget.existing != null;

    ref.listen<AsyncValue<void>>(debtsControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save debt. Try again.')),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit debt' : 'New debt')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // --- Type -------------------------------------------------
              _SectionLabel('Type'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lent', label: Text('I lent money')),
                  ButtonSegment(
                      value: 'borrowed', label: Text('I borrowed money')),
                ],
                selected: {_form.type},
                onSelectionChanged: (s) =>
                    setState(() => _form.type = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Contact ----------------------------------------------
              _SectionLabel('Contact'),
              const SizedBox(height: AppSpacing.sm),
              _ContactTile(
                name: _form.contactName,
                onTap: _pickContact,
              ),
              if (_showContactError) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Pick a contact for this debt.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
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

              // --- Due date ---------------------------------------------
              _SectionLabel('Due date (optional)'),
              const SizedBox(height: AppSpacing.sm),
              _DueDateTile(
                date: _form.dueDate,
                onTap: _pickDueDate,
                onClear: _form.dueDate == null
                    ? null
                    : () => setState(() => _form.dueDate = null),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Notes ------------------------------------------------
              _SectionLabel('Notes (optional)'),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                maxLength: Validators.noteMaxLength,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => Validators.optionalText(v, label: 'Notes'),
                decoration: const InputDecoration(
                  hintText: 'Context, repayment terms, etc.',
                ),
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
                    : Text(isEdit ? 'Save changes' : 'Add debt'),
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.name, required this.onTap});
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = name.trim().isNotEmpty;
    final initial = hasName ? name.trim()[0].toUpperCase() : '?';
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
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasName
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surface,
                  borderRadius: AppBorderRadius.full,
                ),
                child: Text(
                  initial,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: hasName
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  hasName ? name : 'Pick a contact',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasName
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
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

class _DueDateTile extends StatelessWidget {
  const _DueDateTile({
    required this.date,
    required this.onTap,
    required this.onClear,
  });
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDate = date != null;
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
                Icons.event_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  hasDate ? _formatDate(date!) : 'No due date',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasDate
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final local = d.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
