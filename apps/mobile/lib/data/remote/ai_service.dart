import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of [AIService.suggestCategory]. Matches the server-side response
/// shape in `apps/functions/src/ai/suggest_category.ts`.
class CategorySuggestion {
  const CategorySuggestion({
    required this.suggestedCategoryId,
    required this.confidence,
    required this.reasoning,
  });
  final String suggestedCategoryId;
  final double confidence;
  final String reasoning;
}

/// Result of [AIService.scanReceipt]. Matches the server-side response
/// shape in `apps/functions/src/ai/scan_receipt.ts` (PRD §7.2).
class ReceiptScanResult {
  const ReceiptScanResult({
    required this.merchant,
    required this.total,
    required this.currency,
    required this.date,
    required this.suggestedCategoryId,
    required this.lineItems,
    required this.confidence,
    this.notes,
  });
  final String merchant;
  final double total;
  final String currency;
  final DateTime date;
  final String suggestedCategoryId;
  final List<ReceiptLineItem> lineItems;
  final double confidence;
  final String? notes;
}

class ReceiptLineItem {
  const ReceiptLineItem({required this.description, required this.amount});
  final String description;
  final double amount;
}

/// Result of [AIService.coachChat]. Matches the server-side response
/// shape in `apps/functions/src/ai/coach_chat.ts` (PRD §7.3).
class CoachChatResult {
  const CoachChatResult({
    required this.sessionId,
    required this.userMessageId,
    required this.assistantMessageId,
    required this.reply,
  });
  final String sessionId;
  final String userMessageId;
  final String assistantMessageId;
  final String reply;
}

/// Thin wrapper over both AI callables. The callable surface is the
/// boundary the rest of the codebase talks to; the dual-provider +
/// quota + rate-limit story lives on the server (CLAUDE.md §7).
class AIService {
  AIService(this._functions);
  final FirebaseFunctions _functions;

  Future<CategorySuggestion> suggestCategory({
    required String type, // 'expense' | 'income'
    required double amount,
    required String currency,
    String? note,
    String? merchant,
    required List<({String id, String name})> expenseCategories,
    required List<({String id, String name})> incomeCategories,
    List<({String? note, String categoryId})> recentTransactions = const [],
  }) async {
    final callable = _functions.httpsCallable('suggestCategory');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'type': type,
      'amount': amount,
      'currency': currency,
      'note': note,
      'merchant': merchant,
      'expenseCategories': [
        for (final c in expenseCategories) {'id': c.id, 'name': c.name},
      ],
      'incomeCategories': [
        for (final c in incomeCategories) {'id': c.id, 'name': c.name},
      ],
      'recentTransactions': [
        for (final t in recentTransactions)
          {'note': t.note, 'categoryId': t.categoryId},
      ],
    });
    final data = result.data;
    return CategorySuggestion(
      suggestedCategoryId: data['suggestedCategoryId'] as String,
      confidence: (data['confidence'] as num).toDouble(),
      reasoning: data['reasoning'] as String,
    );
  }

  Future<ReceiptScanResult> scanReceipt({
    required String imageUrl,
    required String defaultCurrency,
    required List<({String id, String name})> expenseCategories,
  }) async {
    final callable = _functions.httpsCallable('scanReceipt');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'imageUrl': imageUrl,
      'defaultCurrency': defaultCurrency,
      'expenseCategories': [
        for (final c in expenseCategories) {'id': c.id, 'name': c.name},
      ],
    });
    final data = result.data;
    final rawItems = (data['lineItems'] as List?) ?? const [];
    return ReceiptScanResult(
      merchant: data['merchant'] as String? ?? '',
      total: ((data['total'] as num?) ?? 0).toDouble(),
      currency: data['currency'] as String? ?? defaultCurrency,
      date: DateTime.parse(data['date'] as String),
      suggestedCategoryId: data['suggestedCategoryId'] as String? ?? '',
      lineItems: [
        for (final item in rawItems)
          ReceiptLineItem(
            description: (item as Map)['description'] as String? ?? '',
            amount: ((item['amount'] as num?) ?? 0).toDouble(),
          ),
      ],
      confidence: ((data['confidence'] as num?) ?? 0).toDouble(),
      notes: data['notes'] as String?,
    );
  }

  /// Send one chat turn to the AI coach.
  ///
  /// Pass `sessionId == null` to start a fresh session — the server
  /// generates and returns the new id. The callable writes both the
  /// user message and the assistant reply to Firestore under
  /// `users/{uid}/aiChats/{sessionId}/messages/`; this method just
  /// returns the ids + reply text so callers can update local state
  /// (mainly: pin the session id after turn 1).
  Future<CoachChatResult> coachChat({
    required String message,
    String? sessionId,
  }) async {
    debugPrint('coachChat: dispatching (sessionId=$sessionId, len=${message.length})');
    final callable = _functions.httpsCallable('aiCoachChat');
    try {
      final result = await callable.call<Map<dynamic, dynamic>>({
        'message': message,
        'sessionId': ?sessionId,
      });
      debugPrint('coachChat: success — sessionId=${result.data['sessionId']}');
      final data = result.data;
      return CoachChatResult(
        sessionId: data['sessionId'] as String,
        userMessageId: data['userMessageId'] as String,
        assistantMessageId: data['assistantMessageId'] as String,
        reply: data['reply'] as String,
      );
    } catch (e, st) {
      debugPrint('coachChat: threw $e');
      debugPrintStack(stackTrace: st, label: 'coachChat');
      rethrow;
    }
  }
}

/// FirebaseFunctions instance pinned to Singapore — every Function is
/// deployed to `asia-southeast1` (CLAUDE.md §7). The SDK defaults to
/// us-central1, so this pinning is mandatory.
final aiFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
);

final aiServiceProvider = Provider<AIService>(
  (ref) => AIService(ref.watch(aiFunctionsProvider)),
);
