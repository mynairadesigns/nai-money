import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../providers/transactions_controller.dart';
import '../providers/transactions_filter_provider.dart';
import '../widgets/transaction_row.dart';
import 'transaction_filter_sheet.dart';

/// PRD §11.2: full transaction list, date-grouped, with search +
/// filter chips + multi-select bulk delete / recategorize.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;

  /// `null` = not in selection mode. Empty set = selection mode active
  /// with nothing picked yet.
  Set<String>? _selected;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _enterSelection(String firstId) {
    setState(() => _selected = {firstId});
  }

  void _exitSelection() {
    setState(() => _selected = null);
  }

  void _toggle(String id) {
    final s = _selected;
    if (s == null) return;
    setState(() {
      if (s.contains(id)) {
        s.remove(id);
        if (s.isEmpty) _selected = null;
      } else {
        s.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(filteredTransactionsProvider);
    final filter = ref.watch(transactionsFilterProvider);
    final selection = _selected;

    return Scaffold(
      appBar: selection != null
          ? _SelectionAppBar(
              count: selection.length,
              onCancel: _exitSelection,
              onDelete: () => _confirmBulkDelete(context, selection),
              onRecategorize: () => _bulkRecategorize(context, selection),
            )
          : _BrowseAppBar(
              searchOpen: _searchOpen,
              searchCtrl: _searchCtrl,
              activeFilterCount: filter.activeCount,
              onToggleSearch: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    ref.read(transactionsSearchProvider.notifier).clear();
                  }
                });
              },
              onSearchChanged: (q) =>
                  ref.read(transactionsSearchProvider.notifier).set(q),
              onOpenFilter: () => _openFilterSheet(context),
            ),
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load transactions.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
        data: (rows) {
          if (rows.isEmpty) return const _EmptyState();
          return _GroupedList(
            rows: rows,
            selected: selection,
            onLongPressFirst: _enterSelection,
            onToggleSelect: _toggle,
            onRowTap: (id) => context.push('/transaction/$id'),
          );
        },
      ),
    );
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final current = ref.read(transactionsFilterProvider);
    final result = await showTransactionFilterSheet(context, initial: current);
    if (result != null && mounted) {
      ref.read(transactionsFilterProvider.notifier).set(result);
    }
  }

  Future<void> _confirmBulkDelete(
    BuildContext context,
    Set<String> ids,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${ids.length} transactions?'),
        content: const Text('Wallet balances will be adjusted automatically.'),
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
    if (confirmed != true) return;
    await ref
        .read(transactionsControllerProvider.notifier)
        .deleteMany(ids.toList());
    _exitSelection();
  }

  Future<void> _bulkRecategorize(
    BuildContext context,
    Set<String> ids,
  ) async {
    final cats = ref.read(categoriesListProvider).value ?? const <Category>[];
    if (cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No categories to choose from')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shrinkWrap: true,
        itemCount: cats.length,
        separatorBuilder: (_, _) => const Divider(height: 0),
        itemBuilder: (ctx, i) {
          final c = cats[i];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            title: Text(c.name),
            onTap: () => Navigator.of(ctx).pop(c.id),
          );
        },
      ),
    );
    if (picked == null) return;
    await ref
        .read(transactionsControllerProvider.notifier)
        .recategorizeMany(ids.toList(), picked);
    _exitSelection();
  }
}

// ---- App bars --------------------------------------------------------

class _BrowseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _BrowseAppBar({
    required this.searchOpen,
    required this.searchCtrl,
    required this.activeFilterCount,
    required this.onToggleSearch,
    required this.onSearchChanged,
    required this.onOpenFilter,
  });
  final bool searchOpen;
  final TextEditingController searchCtrl;
  final int activeFilterCount;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenFilter;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: searchOpen
          ? _SearchField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
            )
          : const Text('Transactions'),
      actions: [
        IconButton(
          tooltip: searchOpen ? 'Close search' : 'Search',
          icon: Icon(searchOpen ? Icons.close : Icons.search),
          onPressed: onToggleSearch,
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: 'Filter',
              icon: const Icon(Icons.filter_list),
              onPressed: onOpenFilter,
            ),
            if (activeFilterCount > 0)
              Positioned(
                top: 8,
                right: 6,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$activeFilterCount',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = widget.controller.text.isNotEmpty;
    return Container(
      height: 40,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.full,
      ),
      child: TextField(
        controller: widget.controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
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
          hintText: 'Amount, note, category, wallet…',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Clear',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onRecategorize,
  });
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRecategorize;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.close),
        onPressed: onCancel,
      ),
      title: Text('$count selected'),
      actions: [
        IconButton(
          tooltip: 'Recategorize',
          icon: const Icon(Icons.label_outline),
          onPressed: count == 0 ? null : onRecategorize,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: count == 0 ? null : onDelete,
        ),
      ],
    );
  }
}

// ---- List ------------------------------------------------------------

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.rows,
    required this.selected,
    required this.onLongPressFirst,
    required this.onToggleSelect,
    required this.onRowTap,
  });
  final List<Transaction> rows;
  final Set<String>? selected;
  final ValueChanged<String> onLongPressFirst;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onRowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_ListItem>[];
    DateTime? lastDay;
    for (final t in rows) {
      final dayStart = DateTime(t.date.year, t.date.month, t.date.day);
      if (lastDay == null || dayStart != lastDay) {
        items.add(_HeaderItem(date: dayStart));
        lastDay = dayStart;
      }
      items.add(_RowItem(transaction: t));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is _HeaderItem) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              formatTransactionDayHeader(item.date),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          );
        }
        final row = item as _RowItem;
        final id = row.transaction.id;
        final inSelection = selected != null;
        final isChecked = selected?.contains(id) ?? false;

        return GestureDetector(
          onLongPress: inSelection ? null : () => onLongPressFirst(id),
          child: Container(
            color: isChecked
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            child: Row(
              children: [
                if (inSelection)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: Checkbox(
                      value: isChecked,
                      onChanged: (_) => onToggleSelect(id),
                    ),
                  ),
                Expanded(
                  child: TransactionRow(
                    transaction: row.transaction,
                    onTap: inSelection
                        ? () => onToggleSelect(id)
                        : () => onRowTap(id),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- Empty state -----------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No transactions match', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Adjust your search or filter, or tap + to add one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  _HeaderItem({required this.date});
  final DateTime date;
}

class _RowItem extends _ListItem {
  _RowItem({required this.transaction});
  final Transaction transaction;
}
