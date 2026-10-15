import '../widgets/upsell_sheet.dart';

/// Thrown by controllers when a free user crosses a free-tier ceiling.
/// Catch this in the form's `ref.listen` error path and call
/// [showUpsellSheet] with the matching [UpsellReason].
class FreeTierExceeded implements Exception {
  const FreeTierExceeded(this.reason);
  final UpsellReason reason;

  @override
  String toString() => 'FreeTierExceeded(${reason.name})';
}
