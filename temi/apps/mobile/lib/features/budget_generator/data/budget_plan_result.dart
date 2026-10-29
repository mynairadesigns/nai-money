/// Result of `generateBudgetPlan` callable (P5.3 spec).
class BudgetPlanResult {
  const BudgetPlanResult({
    required this.suggestions,
    required this.totalSuggested,
    required this.notes,
  });

  final List<BudgetSuggestion> suggestions;
  final double totalSuggested;
  final String notes;

  factory BudgetPlanResult.fromMap(Map<dynamic, dynamic> data) {
    final raw = (data['suggestions'] as List?) ?? const [];
    return BudgetPlanResult(
      suggestions: [
        for (final s in raw)
          BudgetSuggestion.fromMap((s as Map).cast<dynamic, dynamic>()),
      ],
      totalSuggested: ((data['totalSuggested'] as num?) ?? 0).toDouble(),
      notes: data['notes'] as String? ?? '',
    );
  }
}

class BudgetSuggestion {
  const BudgetSuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.suggestedAmount,
    required this.reasoning,
  });

  final String categoryId;
  final String categoryName;
  final double suggestedAmount;
  final String reasoning;

  factory BudgetSuggestion.fromMap(Map<dynamic, dynamic> data) {
    return BudgetSuggestion(
      categoryId: data['categoryId'] as String? ?? '',
      categoryName: data['categoryName'] as String? ?? '',
      suggestedAmount: ((data['suggestedAmount'] as num?) ?? 0).toDouble(),
      reasoning: data['reasoning'] as String? ?? '',
    );
  }
}
