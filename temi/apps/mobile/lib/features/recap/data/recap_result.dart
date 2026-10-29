/// Result of `generateWeeklyRecap` callable. Matches the server-side
/// response shape (P5.3 spec).
class WeeklyRecapResult {
  const WeeklyRecapResult({
    required this.title,
    required this.highlights,
    required this.biggestSpend,
    required this.savingsThisWeek,
    required this.insight,
  });

  final String title;
  final List<String> highlights;
  final BiggestSpend biggestSpend;
  final double savingsThisWeek;
  final String insight;

  factory WeeklyRecapResult.fromMap(Map<dynamic, dynamic> data) {
    final rawHighlights = (data['highlights'] as List?) ?? const [];
    final biggest =
        (data['biggestSpend'] as Map?) ?? const <dynamic, dynamic>{};
    return WeeklyRecapResult(
      title: data['title'] as String? ?? 'This week',
      highlights: [
        for (final h in rawHighlights) h.toString(),
      ],
      biggestSpend: BiggestSpend(
        categoryName: biggest['categoryName'] as String? ?? '',
        amount: ((biggest['amount'] as num?) ?? 0).toDouble(),
        currency: biggest['currency'] as String? ?? '',
      ),
      savingsThisWeek: ((data['savingsThisWeek'] as num?) ?? 0).toDouble(),
      insight: data['insight'] as String? ?? '',
    );
  }
}

class BiggestSpend {
  const BiggestSpend({
    required this.categoryName,
    required this.amount,
    required this.currency,
  });
  final String categoryName;
  final double amount;
  final String currency;
}
