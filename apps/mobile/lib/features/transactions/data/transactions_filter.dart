import 'package:flutter/material.dart';

/// Immutable filter state for the transactions list. Constructed in the
/// filter sheet, consumed by the transactions list provider. Empty sets +
/// null fields mean "no constraint on that dimension".
class TransactionsFilter {
  const TransactionsFilter({
    this.types = const <String>{},
    this.walletIds = const <String>{},
    this.categoryIds = const <String>{},
    this.dateRange,
    this.minAmount,
    this.maxAmount,
  });

  /// 'expense' | 'income' | 'transfer'. Empty = all.
  final Set<String> types;

  /// Empty = all wallets.
  final Set<String> walletIds;

  /// Empty = all categories.
  final Set<String> categoryIds;

  /// Null = no date filter.
  final DateTimeRange? dateRange;

  final double? minAmount;
  final double? maxAmount;

  bool get isEmpty =>
      types.isEmpty &&
      walletIds.isEmpty &&
      categoryIds.isEmpty &&
      dateRange == null &&
      minAmount == null &&
      maxAmount == null;

  /// Number of *dimensions* currently constrained. Used to render the
  /// little "3" badge on the filter button when any constraint is active.
  int get activeCount {
    var n = 0;
    if (types.isNotEmpty) n++;
    if (walletIds.isNotEmpty) n++;
    if (categoryIds.isNotEmpty) n++;
    if (dateRange != null) n++;
    if (minAmount != null || maxAmount != null) n++;
    return n;
  }

  TransactionsFilter copyWith({
    Set<String>? types,
    Set<String>? walletIds,
    Set<String>? categoryIds,
    DateTimeRange? dateRange,
    bool clearDateRange = false,
    double? minAmount,
    bool clearMinAmount = false,
    double? maxAmount,
    bool clearMaxAmount = false,
  }) {
    return TransactionsFilter(
      types: types ?? this.types,
      walletIds: walletIds ?? this.walletIds,
      categoryIds: categoryIds ?? this.categoryIds,
      dateRange: clearDateRange ? null : (dateRange ?? this.dateRange),
      minAmount: clearMinAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMaxAmount ? null : (maxAmount ?? this.maxAmount),
    );
  }
}
