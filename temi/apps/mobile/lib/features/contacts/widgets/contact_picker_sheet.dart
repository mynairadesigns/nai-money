import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/local/app_database.dart';
import '../providers/contacts_controller.dart';
import '../providers/contacts_list_provider.dart';

/// Opens a modal bottom sheet picking a contact for debts / shared
/// expenses. Returns the chosen contact id (existing or freshly created
/// via the inline `Create '<typed>'` tile), or `null` on dismiss.
Future<String?> showContactPicker(
  BuildContext context, {
  String? initialId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => _ContactPickerSheet(initialId: initialId),
  );
}

class _ContactPickerSheet extends ConsumerStatefulWidget {
  const _ContactPickerSheet({required this.initialId});
  final String? initialId;

  @override
  ConsumerState<_ContactPickerSheet> createState() =>
      _ContactPickerSheetState();
}

class _ContactPickerSheetState extends ConsumerState<_ContactPickerSheet> {
  late final TextEditingController _searchCtrl;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Contact> _filtered(List<Contact> rows) {
    if (_query.isEmpty) return rows;
    final q = _query.toLowerCase();
    return rows.where((c) {
      if (c.name.toLowerCase().contains(q)) return true;
      final phone = c.phone;
      if (phone != null && phone.toLowerCase().contains(q)) return true;
      final email = c.email;
      if (email != null && email.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  bool _hasExactMatch(List<Contact> rows) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final c in rows) {
      if (c.name.trim().toLowerCase() == q) return true;
    }
    return false;
  }

  Future<void> _createAndReturn(String typed) async {
    final id = await ref
        .read(contactsControllerProvider.notifier)
        .findOrCreateByName(typed);
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final asyncRows = ref.watch(contactsListProvider);
    final rows = asyncRows.value ?? const <Contact>[];
    final filtered = _filtered(rows);
    // The typed query becomes a persisted contact name, so it has to
    // clear the same bar as any other name field before we offer to
    // create it.
    final showCreateTile = _query.trim().isNotEmpty &&
        !_hasExactMatch(rows) &&
        Validators.requiredText(_query, label: 'Name') == null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose contact', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  _SearchField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: asyncRows.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    'Could not load contacts.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                data: (_) {
                  if (filtered.isEmpty && !showCreateTile) {
                    return Center(
                      child: Text(
                        rows.isEmpty
                            ? 'No contacts yet'
                            : 'No matches',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      if (showCreateTile)
                        _CreateContactTile(
                          typed: _query.trim(),
                          onTap: () => _createAndReturn(_query.trim()),
                        ),
                      for (final c in filtered)
                        _ContactTile(
                          contact: c,
                          isSelected: c.id == widget.initialId,
                          onTap: () => Navigator.of(context).pop(c.id),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.full,
      ),
      child: TextField(
        controller: controller,
        autofocus: false,
        textInputAction: TextInputAction.search,
        // Doubles as the name for a newly-created contact, so it carries
        // the same ceiling as other name fields.
        maxLength: Validators.nameMaxLength,
        style: theme.textTheme.bodyMedium,
        onChanged: onChanged,
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
          hintText: 'Search or type a new name',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _CreateContactTile extends StatelessWidget {
  const _CreateContactTile({required this.typed, required this.onTap});
  final String typed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: AppBorderRadius.full,
        ),
        child: Icon(
          Icons.add,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text("Create '$typed'"),
      subtitle: Text(
        'Add a new contact',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.onTap,
  });
  final Contact contact;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = contact.name.isNotEmpty
        ? contact.name.trim()[0].toUpperCase()
        : '?';
    final phone = contact.phone;
    final email = contact.email;
    String? subtitle;
    if (phone != null && phone.isNotEmpty) {
      subtitle = phone;
    } else if (email != null && email.isNotEmpty) {
      subtitle = email;
    }

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppBorderRadius.full,
        ),
        child: Text(
          initial,
          style: theme.textTheme.titleSmall?.copyWith(
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(contact.name),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
    );
  }
}
