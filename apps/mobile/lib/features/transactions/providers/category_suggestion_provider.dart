import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/remote/ai_service.dart';
import '../../categories/providers/categories_list_provider.dart';

/// Inputs that uniquely determine an AI category suggestion. Used as
/// the family key for [categorySuggestionProvider] — Riverpod caches per
/// distinct value, so typing the same text twice in a row only hits the
/// AI once.
class CategorySuggestionInput {
  const CategorySuggestionInput({
    required this.type,
    required this.amount,
    required this.note,
    required this.currency,
  });

  final String type;
  final double amount;
  final String note;
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is CategorySuggestionInput &&
      other.type == type &&
      other.amount == amount &&
      other.note == note &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(type, amount, note, currency);
}

/// Debounced AI category suggestion for the inline chip in Add
/// Transaction. Returns null while idle, debouncing, or on any error
/// (the chip simply doesn't render — never blocks manual entry).
///
/// Debounce: 600ms. If the family key changes within the window the
/// previous fetch is dropped via Riverpod's auto-dispose.
final categorySuggestionProvider = FutureProvider.autoDispose
    .family<CategorySuggestion?, CategorySuggestionInput>((ref, input) async {
  // Skip: transfers don't have categories, and we need *something* to go on.
  if (input.type == 'transfer') return null;
  if (input.note.trim().isEmpty && input.amount == 0) return null;

  // Debounce. If the user keeps typing, this provider is auto-disposed
  // and the timer is cancelled; we resolve early and return null.
  var cancelled = false;
  final completer = Completer<void>();
  final timer = Timer(const Duration(milliseconds: 600), () {
    if (!completer.isCompleted) completer.complete();
  });
  ref.onDispose(() {
    cancelled = true;
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;
  if (cancelled) return null;

  final cats = ref.read(categoriesListProvider).value ?? const [];
  final expense = [
    for (final c in cats.where((c) => c.type == 'expense'))
      (id: c.id, name: c.name),
  ];
  final income = [
    for (final c in cats.where((c) => c.type == 'income'))
      (id: c.id, name: c.name),
  ];
  if (expense.isEmpty && income.isEmpty) return null;

  try {
    final suggestion = await ref.read(aiServiceProvider).suggestCategory(
          type: input.type,
          amount: input.amount,
          currency: input.currency,
          note: input.note,
          expenseCategories: expense,
          incomeCategories: income,
        );
    return suggestion;
  } catch (e, st) {
    // Network / quota / server error — fall back to silence. Manual
    // category picker still works. Logged in debug builds so the dev
    // can see what's wrong; release builds stay quiet.
    debugPrint('categorySuggestionProvider: $e');
    debugPrintStack(stackTrace: st, label: 'suggestCategory error');
    return null;
  }
});
