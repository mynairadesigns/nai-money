/// Typed result of `forecastSpending` Cloud Function (PRD §7.4).
///
/// Server contract:
/// ```ts
/// {
///   projectedTotal: number,
///   confidence: number,                  // 0..1
///   breakdown: Array<{ categoryName: string, projected: number,
///                      trend: 'up'|'down'|'flat' }>,
///   headline: string,
///   reasoning: string,
/// }
/// ```
class ForecastResult {
  const ForecastResult({
    required this.projectedTotal,
    required this.confidence,
    required this.breakdown,
    required this.headline,
    required this.reasoning,
  });

  final double projectedTotal;
  final double confidence;
  final List<ForecastBreakdownItem> breakdown;
  final String headline;
  final String reasoning;

  factory ForecastResult.fromMap(Map<dynamic, dynamic> data) {
    final rawItems = (data['breakdown'] as List?) ?? const [];
    return ForecastResult(
      projectedTotal: ((data['projectedTotal'] as num?) ?? 0).toDouble(),
      confidence: ((data['confidence'] as num?) ?? 0).toDouble(),
      breakdown: [
        for (final item in rawItems)
          ForecastBreakdownItem.fromMap(item as Map),
      ],
      headline: data['headline'] as String? ?? '',
      reasoning: data['reasoning'] as String? ?? '',
    );
  }
}

enum ForecastTrend { up, down, flat }

class ForecastBreakdownItem {
  const ForecastBreakdownItem({
    required this.categoryName,
    required this.projected,
    required this.trend,
  });

  final String categoryName;
  final double projected;
  final ForecastTrend trend;

  factory ForecastBreakdownItem.fromMap(Map<dynamic, dynamic> data) {
    return ForecastBreakdownItem(
      categoryName: data['categoryName'] as String? ?? '',
      projected: ((data['projected'] as num?) ?? 0).toDouble(),
      trend: _parseTrend(data['trend'] as String?),
    );
  }

  static ForecastTrend _parseTrend(String? raw) {
    switch (raw) {
      case 'up':
        return ForecastTrend.up;
      case 'down':
        return ForecastTrend.down;
      case 'flat':
      default:
        return ForecastTrend.flat;
    }
  }
}
