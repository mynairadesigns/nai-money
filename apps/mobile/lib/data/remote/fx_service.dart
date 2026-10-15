import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tuple returned by [FxService.fetch]. `rate` is the source→dest
/// conversion factor; multiply `sourceAmount * rate` to get the
/// destination-currency amount. `asOf` is whenever the underlying API
/// returned this rate (cached or fresh), as reported by the server.
class FxRate {
  const FxRate({required this.rate, required this.asOf});
  final double rate;
  final DateTime asOf;
}

/// Wraps the `getFxRate` Firebase callable. Region-pinned client-side
/// to match the function's deployment region (`europe-west1`) — the
/// SDK defaults to `us-central1` otherwise.
///
/// Maintains an in-memory per-session cache keyed by `"<FROM>-<TO>"`,
/// so repeated reads inside the Add Transaction sheet (e.g. user toggles
/// source / dest) don't re-hit the function.
class FxService {
  FxService(this._functions);

  final FirebaseFunctions _functions;
  final Map<String, FxRate> _cache = {};

  static const String _region = 'europe-west1';

  Future<FxRate> fetch({required String from, required String to}) async {
    final key = '$from-$to';
    final cached = _cache[key];
    if (cached != null) return cached;

    final callable =
        _functions.httpsCallable('getFxRate');
    final result = await callable.call<Map<dynamic, dynamic>>({
      'from': from,
      'to': to,
    });
    final data = result.data;
    final rate = (data['rate'] as num).toDouble();
    final asOf = DateTime.parse(data['asOf'] as String);
    final fx = FxRate(rate: rate, asOf: asOf);
    _cache[key] = fx;
    return fx;
  }

  void clearCache() => _cache.clear();
}

/// FirebaseFunctions instance pinned to the deployment region.
final firebaseFunctionsProvider = Provider<FirebaseFunctions>(
  (_) => FirebaseFunctions.instanceFor(region: FxService._region),
);

final fxServiceProvider = Provider<FxService>(
  (ref) => FxService(ref.watch(firebaseFunctionsProvider)),
);
