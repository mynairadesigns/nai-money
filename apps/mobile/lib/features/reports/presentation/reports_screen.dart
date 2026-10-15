import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/spacing.dart';
import '../widgets/category_pie.dart';
import '../widgets/income_expense_bars.dart';
import '../widgets/period_selector.dart';

/// PRD §11.5 / §6.10. Period selector + income/expense bars + category
/// pie chart. Line chart, top merchants, and PDF/CSV export are
/// deferred to P5 (alongside AI insights).
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          children: const [
            PeriodSelector(),
            SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PeriodLabel(),
            ),
            SizedBox(height: AppSpacing.lg),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: IncomeExpenseBars(),
            ),
            SizedBox(height: AppSpacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: CategoryPie(),
            ),
            SizedBox(height: AppSpacing.xxxl),
          ],
        ),
      ),
    );
  }
}
