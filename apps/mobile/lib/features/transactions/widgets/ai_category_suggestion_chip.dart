import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/remote/ai_service.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../providers/category_suggestion_provider.dart';

/// Inline "✨ Looks like Food & Dining — tap to accept" chip rendered
/// between the wallet picker and the category picker in
/// AddTransactionSheet. Silently renders nothing while idle, loading,
/// or low-confidence; PRD §6.4.2 — should never pester.
class AICategorySuggestionChip extends ConsumerWidget {
  const AICategorySuggestionChip({
    required this.type,
    required this.amount,
    required this.note,
    required this.currency,
    required this.onAccept,
    super.key,
  });

  final String type;
  final double amount;
  final String note;
  final String currency;
  final void Function(CategorySuggestion) onAccept;

  static const _confidenceFloor = 0.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (type == 'transfer') return const SizedBox.shrink();
    if (note.trim().isEmpty && amount == 0) return const SizedBox.shrink();

    final input = CategorySuggestionInput(
      type: type,
      amount: amount,
      note: note.trim(),
      currency: currency,
    );
    final async = ref.watch(categorySuggestionProvider(input));
    final suggestion = async.value;
    if (suggestion == null) return const SizedBox.shrink();
    if (suggestion.confidence < _confidenceFloor) {
      return const SizedBox.shrink();
    }

    final categories = ref.watch(categoriesListProvider).value ?? const [];
    String? categoryName;
    for (final c in categories) {
      if (c.id == suggestion.suggestedCategoryId) {
        categoryName = c.name;
        break;
      }
    }
    if (categoryName == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Material(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.full,
        child: InkWell(
          borderRadius: AppBorderRadius.full,
          onTap: () => onAccept(suggestion),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'Looks like $categoryName · tap to accept',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
