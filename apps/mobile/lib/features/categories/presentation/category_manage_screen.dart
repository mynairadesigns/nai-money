import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../data/category_catalog.dart';
import '../providers/categories_controller.dart';
import '../providers/categories_list_provider.dart';
import 'category_edit_sheet.dart';

/// PRD `/category/manage` route. Sectioned list of the user's categories
/// (Expenses + Income), with edit/delete on each row and a +Add FAB that
/// opens [showCategoryEditSheet].
class CategoryManageScreen extends ConsumerWidget {
  const CategoryManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expenses = ref.watch(expenseCategoriesProvider);
    final incomes = ref.watch(incomeCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCategoryEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: SafeArea(
        child: expenses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load categories.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          data: (expenseList) {
            final incomeList = incomes.value ?? const <Category>[];
            if (expenseList.isEmpty && incomeList.isEmpty) {
              return _EmptyState(theme: theme);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxxl, // leave room for the FAB
              ),
              children: [
                if (expenseList.isNotEmpty) ...[
                  _SectionHeader(label: 'Expenses'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final c in expenseList)
                    _CategoryTile(category: c),
                ],
                if (expenseList.isNotEmpty && incomeList.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                if (incomeList.isNotEmpty) ...[
                  _SectionHeader(label: 'Income'),
                  const SizedBox(height: AppSpacing.sm),
                  for (final c in incomeList)
                    _CategoryTile(category: c),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No categories yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tap "Add category" to create one.',
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = Color(int.parse('FF${category.color}', radix: 16));
    final icon = iconForCategory(category.iconName);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppBorderRadius.lg,
        onTap: () => showCategoryEditSheet(context, existing: category),
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
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppBorderRadius.full,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => _confirmDelete(context, ref, category),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: const Text(
          'Transactions using this category will keep their reference '
          'but the category itself will be gone.',
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
    if (confirmed != true) return;
    await ref.read(categoriesControllerProvider.notifier).delete(category.id);
  }
}
