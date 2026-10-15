/// Typed result of `detectAnomalies` Cloud Function (PRD §7.5).
///
/// Server contract:
/// ```ts
/// {
///   anomalies: Array<{
///     transactionId?: string,
///     categoryName: string,
///     amount: number,
///     currency: string,
///     summary: string,
///     severity: 'low'|'medium'|'high',
///   }>,
///   summary: string,
/// }
/// ```
class AnomaliesResult {
  const AnomaliesResult({
    required this.anomalies,
    required this.summary,
  });

  final List<AnomalyItem> anomalies;
  final String summary;

  factory AnomaliesResult.fromMap(Map<dynamic, dynamic> data) {
    final rawItems = (data['anomalies'] as List?) ?? const [];
    return AnomaliesResult(
      anomalies: [
        for (final item in rawItems) AnomalyItem.fromMap(item as Map),
      ],
      summary: data['summary'] as String? ?? '',
    );
  }
}

enum AnomalySeverity { low, medium, high }

class AnomalyItem {
  const AnomalyItem({
    required this.transactionId,
    required this.categoryName,
    required this.amount,
    required this.currency,
    required this.summary,
    required this.severity,
  });

  final String? transactionId;
  final String categoryName;
  final double amount;
  final String currency;
  final String summary;
  final AnomalySeverity severity;

  factory AnomalyItem.fromMap(Map<dynamic, dynamic> data) {
    return AnomalyItem(
      transactionId: data['transactionId'] as String?,
      categoryName: data['categoryName'] as String? ?? '',
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
      currency: data['currency'] as String? ?? 'USD',
      summary: data['summary'] as String? ?? '',
      severity: _parseSeverity(data['severity'] as String?),
    );
  }

  static AnomalySeverity _parseSeverity(String? raw) {
    switch (raw) {
      case 'high':
        return AnomalySeverity.high;
      case 'medium':
        return AnomalySeverity.medium;
      case 'low':
      default:
        return AnomalySeverity.low;
    }
  }
}
