import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temi_finance/data/remote/fx_service.dart';

/// `FxService` wraps the region-pinned `getFxRate` Firebase callable and keeps
/// an in-memory `"<FROM>-<TO>"` cache so the Add Transaction sheet doesn't
/// re-hit the function when the user toggles source/dest. These tests guard the
/// two things that matter: the payload parse (server `rate` may arrive as an
/// int but must coerce to double; `asOf` is an ISO string) and the cache
/// semantics (one network call per distinct pair until `clearCache`).
///
/// We never touch Firebase: `FxService` takes a `FirebaseFunctions` in its
/// constructor, so a hand-rolled `noSuchMethod` fake stands in for the SDK and
/// counts how many times the underlying callable actually fired.

/// Fake `FirebaseFunctions`: `httpsCallable(...)` returns a [_FakeCallable]
/// bound to a shared invocation counter and the configured response map.
class _FakeFunctions implements FirebaseFunctions {
  _FakeFunctions(this.responseData);

  /// Map returned as `HttpsCallableResult.data` for every call.
  Map<dynamic, dynamic> responseData;

  /// How many times the underlying callable actually fired.
  int callCount = 0;

  /// Params captured from the most recent `.call(...)`.
  Map<dynamic, dynamic>? lastParams;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #httpsCallable) {
      return _FakeCallable(this);
    }
    return super.noSuchMethod(invocation);
  }
}

/// Fake `HttpsCallable`: each `call(...)` bumps the parent counter and resolves
/// to a [_FakeResult] wrapping the configured map.
class _FakeCallable implements HttpsCallable {
  _FakeCallable(this._parent);

  final _FakeFunctions _parent;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #call) {
      _parent.callCount++;
      final args = invocation.positionalArguments;
      if (args.isNotEmpty && args.first is Map) {
        _parent.lastParams = args.first as Map<dynamic, dynamic>;
      }
      return Future.value(_FakeResult(_parent.responseData));
    }
    return super.noSuchMethod(invocation);
  }
}

/// Fake `HttpsCallableResult`: exposes the configured map via `.data`.
class _FakeResult implements HttpsCallableResult<Map<dynamic, dynamic>> {
  _FakeResult(this._data);

  final Map<dynamic, dynamic> _data;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #data) {
      return _data;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('FxService.fetch', () {
    test('parses an int rate as double and ISO asOf', () async {
      final functions = _FakeFunctions({
        'rate': 2, // int in the payload — must coerce to 2.0
        'asOf': '2026-05-01T00:00:00.000Z',
      });
      final service = FxService(functions);

      final fx = await service.fetch(from: 'USD', to: 'EUR');

      expect(fx.rate, isA<double>());
      expect(fx.rate, 2.0);
      expect(fx.asOf, DateTime.parse('2026-05-01T00:00:00.000Z'));
      expect(functions.lastParams, {'from': 'USD', 'to': 'EUR'});
      expect(functions.callCount, 1);
    });

    test('a double rate round-trips without precision loss', () async {
      final functions = _FakeFunctions({
        'rate': 1.2345,
        'asOf': '2026-05-01T00:00:00.000Z',
      });
      final service = FxService(functions);

      final fx = await service.fetch(from: 'USD', to: 'GBP');

      expect(fx.rate, 1.2345);
    });

    test('repeated fetch of the same pair serves the cache (one call)',
        () async {
      final functions = _FakeFunctions({
        'rate': 1.1,
        'asOf': '2026-05-01T00:00:00.000Z',
      });
      final service = FxService(functions);

      final first = await service.fetch(from: 'USD', to: 'EUR');
      final second = await service.fetch(from: 'USD', to: 'EUR');

      expect(functions.callCount, 1);
      expect(second.rate, first.rate);
      expect(second.asOf, first.asOf);
    });

    test('distinct pairs each trigger their own call', () async {
      final functions = _FakeFunctions({
        'rate': 1.1,
        'asOf': '2026-05-01T00:00:00.000Z',
      });
      final service = FxService(functions);

      await service.fetch(from: 'USD', to: 'EUR');
      await service.fetch(from: 'USD', to: 'GBP');
      await service.fetch(from: 'EUR', to: 'USD');

      expect(functions.callCount, 3);
    });

    test('clearCache forces a previously-cached pair to call again', () async {
      final functions = _FakeFunctions({
        'rate': 1.1,
        'asOf': '2026-05-01T00:00:00.000Z',
      });
      final service = FxService(functions);

      await service.fetch(from: 'USD', to: 'EUR');
      expect(functions.callCount, 1);

      service.clearCache();
      await service.fetch(from: 'USD', to: 'EUR');

      expect(functions.callCount, 2);
    });
  });
}
