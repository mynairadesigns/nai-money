/// One detected recurring-payment candidate from `detectSubscriptions`
/// (P5.3 spec). Server identifies the pattern; user confirms before any
/// recurring rule is created.
class SubscriptionCandidate {
  const SubscriptionCandidate({
    required this.candidateId,
    required this.merchant,
    required this.amount,
    required this.currency,
    required this.frequency,
    required this.occurrences,
    required this.sampleTransactionIds,
  });

  final String candidateId;
  final String merchant;
  final double amount;
  final String currency;

  /// 'weekly' | 'monthly'.
  final String frequency;
  final int occurrences;
  final List<String> sampleTransactionIds;

  factory SubscriptionCandidate.fromMap(Map<dynamic, dynamic> data) {
    final rawIds = (data['sampleTransactionIds'] as List?) ?? const [];
    return SubscriptionCandidate(
      candidateId: data['candidateId'] as String? ?? '',
      merchant: data['merchant'] as String? ?? '',
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
      currency: data['currency'] as String? ?? '',
      frequency: data['frequency'] as String? ?? 'monthly',
      occurrences: ((data['occurrences'] as num?) ?? 0).toInt(),
      sampleTransactionIds: [
        for (final id in rawIds) id.toString(),
      ],
    );
  }
}
