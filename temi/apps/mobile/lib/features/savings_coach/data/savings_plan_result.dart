/// Result of `generateSavingsPlan` callable (P5.3 spec).
class SavingsPlanResult {
  const SavingsPlanResult({
    required this.requiredPerMonth,
    required this.onTrack,
    required this.suggestions,
    required this.summary,
    required this.timelineWeeks,
  });

  final double requiredPerMonth;
  final bool onTrack;
  final List<SavingsCutSuggestion> suggestions;
  final String summary;
  final int timelineWeeks;

  factory SavingsPlanResult.fromMap(Map<dynamic, dynamic> data) {
    final raw = (data['suggestions'] as List?) ?? const [];
    return SavingsPlanResult(
      requiredPerMonth: ((data['requiredPerMonth'] as num?) ?? 0).toDouble(),
      onTrack: data['onTrack'] as bool? ?? false,
      suggestions: [
        for (final s in raw)
          SavingsCutSuggestion.fromMap((s as Map).cast<dynamic, dynamic>()),
      ],
      summary: data['summary'] as String? ?? '',
      timelineWeeks: ((data['timelineWeeks'] as num?) ?? 0).toInt(),
    );
  }
}

class SavingsCutSuggestion {
  const SavingsCutSuggestion({
    required this.categoryName,
    required this.currentMonthlySpend,
    required this.suggestedCut,
    required this.monthlySavingsImpact,
  });

  final String categoryName;
  final double currentMonthlySpend;
  final double suggestedCut;
  final double monthlySavingsImpact;

  factory SavingsCutSuggestion.fromMap(Map<dynamic, dynamic> data) {
    return SavingsCutSuggestion(
      categoryName: data['categoryName'] as String? ?? '',
      currentMonthlySpend:
          ((data['currentMonthlySpend'] as num?) ?? 0).toDouble(),
      suggestedCut: ((data['suggestedCut'] as num?) ?? 0).toDouble(),
      monthlySavingsImpact:
          ((data['monthlySavingsImpact'] as num?) ?? 0).toDouble(),
    );
  }
}
