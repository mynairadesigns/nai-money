/// Typed result of `computeHealthScore` Cloud Function (PRD §7.8).
///
/// Server contract:
/// ```ts
/// {
///   score: number,                       // 0..100
///   label: 'excellent'|'good'|'fair'|'poor',
///   factors: Array<{ name: string, weight: number, value: number,
///                    explanation: string }>,
///   actionableTips: Array<string>,
/// }
/// ```
class HealthScoreResult {
  const HealthScoreResult({
    required this.score,
    required this.label,
    required this.factors,
    required this.actionableTips,
  });

  final int score;
  final HealthScoreLabel label;
  final List<HealthFactor> factors;
  final List<String> actionableTips;

  factory HealthScoreResult.fromMap(Map<dynamic, dynamic> data) {
    final rawFactors = (data['factors'] as List?) ?? const [];
    final rawTips = (data['actionableTips'] as List?) ?? const [];
    return HealthScoreResult(
      score: ((data['score'] as num?) ?? 0).toInt(),
      label: _parseLabel(data['label'] as String?),
      factors: [
        for (final f in rawFactors) HealthFactor.fromMap(f as Map),
      ],
      actionableTips: [for (final t in rawTips) t.toString()],
    );
  }

  static HealthScoreLabel _parseLabel(String? raw) {
    switch (raw) {
      case 'excellent':
        return HealthScoreLabel.excellent;
      case 'good':
        return HealthScoreLabel.good;
      case 'fair':
        return HealthScoreLabel.fair;
      case 'poor':
      default:
        return HealthScoreLabel.poor;
    }
  }
}

enum HealthScoreLabel { excellent, good, fair, poor }

extension HealthScoreLabelDisplay on HealthScoreLabel {
  String get displayName {
    switch (this) {
      case HealthScoreLabel.excellent:
        return 'Excellent';
      case HealthScoreLabel.good:
        return 'Good';
      case HealthScoreLabel.fair:
        return 'Fair';
      case HealthScoreLabel.poor:
        return 'Poor';
    }
  }
}

class HealthFactor {
  const HealthFactor({
    required this.name,
    required this.weight,
    required this.value,
    required this.explanation,
  });

  final String name;
  final double weight;
  final double value;
  final String explanation;

  factory HealthFactor.fromMap(Map<dynamic, dynamic> data) {
    return HealthFactor(
      name: data['name'] as String? ?? '',
      weight: ((data['weight'] as num?) ?? 0).toDouble(),
      value: ((data['value'] as num?) ?? 0).toDouble(),
      explanation: data['explanation'] as String? ?? '',
    );
  }
}
