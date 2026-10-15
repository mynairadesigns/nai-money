import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../providers/reports_state_provider.dart';

/// Horizontal chip strip — Day / Week / Month / Quarter / Year / Custom.
/// Sits at the top of the Reports tab and the drill-down screen header.
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportsFilterProvider);
    final ctrl = ref.read(reportsFilterProvider.notifier);

    Widget chip(ReportsPeriod p, String label) {
      final selected = filter.period == p;
      return ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) async {
          if (p == ReportsPeriod.custom) {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDateRange: filter.customRange,
            );
            if (picked != null) ctrl.setCustomRange(picked);
          } else {
            ctrl.setPeriod(p);
          }
        },
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          chip(ReportsPeriod.day, 'Day'),
          const SizedBox(width: AppSpacing.xs),
          chip(ReportsPeriod.week, 'Week'),
          const SizedBox(width: AppSpacing.xs),
          chip(ReportsPeriod.month, 'Month'),
          const SizedBox(width: AppSpacing.xs),
          chip(ReportsPeriod.quarter, 'Quarter'),
          const SizedBox(width: AppSpacing.xs),
          chip(ReportsPeriod.year, 'Year'),
          const SizedBox(width: AppSpacing.xs),
          chip(ReportsPeriod.custom, 'Custom'),
        ],
      ),
    );
  }
}

/// Small read-only label below the chip strip showing the currently-
/// resolved date range, e.g. "1 May 2026 – 21 May 2026".
class PeriodLabel extends ConsumerWidget {
  const PeriodLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final range = ref.watch(reportsFilterProvider).range();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: AppBorderRadius.full,
      ),
      child: Text(
        _formatRange(range.start, range.end),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static String _formatRange(DateTime start, DateTime end) {
    // `end` is half-open (exclusive), so show end - 1 day.
    final inclusiveEnd = end.subtract(const Duration(days: 1));
    final sameYear = start.year == inclusiveEnd.year;
    final s = _formatDay(start, includeYear: !sameYear);
    final e = _formatDay(inclusiveEnd, includeYear: true);
    return '$s – $e';
  }

  static String _formatDay(DateTime d, {required bool includeYear}) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final base = '${d.day} ${months[d.month - 1]}';
    return includeYear ? '$base ${d.year}' : base;
  }
}
