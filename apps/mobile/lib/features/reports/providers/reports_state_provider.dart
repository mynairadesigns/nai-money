import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selectable periods for the Reports tab (PRD §6.10). `custom` is
/// driven by an explicit `customRange` on [ReportsFilter].
enum ReportsPeriod { day, week, month, quarter, year, custom }

class ReportsFilter {
  const ReportsFilter({
    this.period = ReportsPeriod.month,
    this.customRange,
  });

  final ReportsPeriod period;

  /// Required iff [period] is [ReportsPeriod.custom]; ignored otherwise.
  final DateTimeRange? customRange;

  ReportsFilter copyWith({
    ReportsPeriod? period,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return ReportsFilter(
      period: period ?? this.period,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  /// Resolves the period to a concrete [DateTimeRange] anchored at `now`.
  DateTimeRange range({DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (period) {
      case ReportsPeriod.day:
        return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
      case ReportsPeriod.week:
        // Week starts Monday.
        final weekday = today.weekday; // 1=Mon..7=Sun
        final start = today.subtract(Duration(days: weekday - 1));
        return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
      case ReportsPeriod.month:
        final start = DateTime(n.year, n.month, 1);
        final end = DateTime(n.year, n.month + 1, 1);
        return DateTimeRange(start: start, end: end);
      case ReportsPeriod.quarter:
        final qStartMonth = ((n.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(n.year, qStartMonth, 1);
        final end = DateTime(n.year, qStartMonth + 3, 1);
        return DateTimeRange(start: start, end: end);
      case ReportsPeriod.year:
        return DateTimeRange(
          start: DateTime(n.year, 1, 1),
          end: DateTime(n.year + 1, 1, 1),
        );
      case ReportsPeriod.custom:
        return customRange ??
            DateTimeRange(
              start: DateTime(n.year, n.month, 1),
              end: DateTime(n.year, n.month + 1, 1),
            );
    }
  }
}

/// Holds the currently-selected reports filter. Widgets watch this to
/// trigger recomputation when the period or custom range changes.
final reportsFilterProvider = NotifierProvider<ReportsFilterController, ReportsFilter>(
  ReportsFilterController.new,
);

class ReportsFilterController extends Notifier<ReportsFilter> {
  @override
  ReportsFilter build() => const ReportsFilter();

  void setPeriod(ReportsPeriod period) {
    state = state.copyWith(period: period, clearCustomRange: period != ReportsPeriod.custom);
  }

  void setCustomRange(DateTimeRange range) {
    state = ReportsFilter(period: ReportsPeriod.custom, customRange: range);
  }
}
