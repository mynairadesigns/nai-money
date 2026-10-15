import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/recap_result.dart';
import '../data/recap_service.dart';

/// One-shot weekly recap fetch. Auto-disposes when the screen leaves the
/// tree so re-entry triggers a fresh call.
final weeklyRecapProvider = FutureProvider.autoDispose<WeeklyRecapResult>(
  (ref) async {
    final service = ref.watch(recapServiceProvider);
    return service.recap();
  },
);
