/// Mutable form payload for Add / Edit Transaction. UI mutates in place,
/// then submits via [TransactionsController.create] or `.edit`.
class TransactionFormData {
  TransactionFormData({
    this.id,
    this.type = 'expense', // 'expense' | 'income' | 'transfer'
    this.amount = 0,
    this.walletId,
    this.categoryId,
    DateTime? date,
    this.note,
    this.transferToWalletId,
    this.aiCategorySuggested = false,
    this.aiConfidence,
    this.aiSource,
    this.attachmentUrl,
    this.attachmentLocalPath,
  }) : date = date ?? DateTime.now();

  /// Non-null when editing.
  String? id;

  String type;
  double amount;
  String? walletId;

  /// For expense/income: required. For transfer: ignored (we still store
  /// a categoryId for analytics — a hidden "Transfer" category — but
  /// that lands in P2.4).
  String? categoryId;

  DateTime date;
  String? note;

  /// Only set on transfer-type transactions.
  String? transferToWalletId;

  /// True when the user accepted an AI-suggested category (chip tap or
  /// receipt-scan prefill). Stamps `Transaction.aiCategorySuggested`.
  bool aiCategorySuggested;

  /// AI provider confidence (0..1). Stamps `Transaction.aiConfidence`.
  double? aiConfidence;

  /// `'manual_suggest'` | `'receipt_scan'` | `'subscription_detector'`.
  /// Stamps `Transaction.aiSource`.
  String? aiSource;

  /// Permanent attachment URL (Firebase Storage). Set after the receipt
  /// scanner moves the temp upload to its final per-tx path on save.
  String? attachmentUrl;

  /// Local-only cache path or temp Storage URL surfaced from the receipt
  /// scanner; never mirrored to Firestore (sync_mappers strips it).
  String? attachmentLocalPath;

  bool get isReady {
    if (amount <= 0) return false;
    if (walletId == null) return false;
    if (type != 'transfer' && categoryId == null) return false;
    return true;
  }
}

/// Pre-fill payload from [ReceiptScannerScreen]. Threaded into
/// [showAddTransactionSheet]'s optional `prefill` param.
class ReceiptPrefill {
  const ReceiptPrefill({
    required this.merchant,
    required this.total,
    required this.currency,
    required this.date,
    required this.suggestedCategoryId,
    required this.confidence,
    required this.tempReceiptUrl,
  });
  final String merchant;
  final double total;
  final String currency;
  final DateTime date;
  final String suggestedCategoryId;
  final double confidence;
  final String tempReceiptUrl;
}
