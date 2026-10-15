import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/local/app_database.dart';
import '../data/category_catalog.dart';
import '../providers/categories_controller.dart';

/// Opens the modal sheet to either add (when [existing] is null) or edit
/// an existing category. Returns true on a successful save, false on
/// cancel.
Future<bool?> showCategoryEditSheet(
  BuildContext context, {
  Category? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => _CategoryEditSheet(existing: existing),
  );
}

class _CategoryEditSheet extends ConsumerStatefulWidget {
  const _CategoryEditSheet({required this.existing});
  final Category? existing;

  @override
  ConsumerState<_CategoryEditSheet> createState() =>
      _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<_CategoryEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final CategoryFormData _form;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _form = CategoryFormData(
      id: e?.id,
      name: e?.name ?? '',
      type: e?.type ?? 'expense',
      iconName: e?.iconName ?? 'label',
      colorHex: e?.color ?? kCategoryColorCatalog.first,
    );
    _nameCtrl = TextEditingController(text: _form.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _form.name = _nameCtrl.text;
    final ctrl = ref.read(categoriesControllerProvider.notifier);
    if (widget.existing == null) {
      await ctrl.create(_form);
    } else {
      await ctrl.edit(_form);
    }
    if (!mounted) return;
    final result = ref.read(categoriesControllerProvider);
    if (result.hasError) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final commitState = ref.watch(categoriesControllerProvider);

    ref.listen<AsyncValue<void>>(categoriesControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save category. Try again.')),
        );
      }
    });

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                widget.existing == null ? 'New category' : 'Edit category',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nameCtrl,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                maxLength: Validators.nameMaxLength,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Subscriptions',
                  counterText: '',
                ),
                validator: (v) => Validators.requiredText(v, label: 'Name'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Type'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                  ButtonSegment(value: 'income', label: Text('Income')),
                ],
                selected: {_form.type},
                onSelectionChanged: (s) =>
                    setState(() => _form.type = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Icon'),
              const SizedBox(height: AppSpacing.sm),
              _IconGrid(
                selected: _form.iconName,
                onPick: (name) => setState(() => _form.iconName = name),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionLabel('Color'),
              const SizedBox(height: AppSpacing.sm),
              _ColorGrid(
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
                    : Text(widget.existing == null ? 'Add category' : 'Save'),
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

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onPick});
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

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.selectedHex, required this.onPick});
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
