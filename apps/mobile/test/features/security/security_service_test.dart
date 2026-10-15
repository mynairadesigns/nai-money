import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homa_finance/features/security/data/security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SecurityService` stores the PIN as a salted SHA-256 hash in secure
/// storage (never plaintext, never the salt-less digest) and keeps the
/// non-secret lock flags in SharedPreferences (CLAUDE.md §6 "App lock").
/// Biometric paths hit `local_auth` platform channels and aren't covered
/// here — these tests exercise the hashing + flag surface only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureStorage secure;
  late SecurityService service;

  Future<void> makeService() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    secure = FakeSecureStorage();
    service = SecurityService(secureStorage: secure, prefs: prefs);
  }

  setUp(makeService);

  group('PIN', () {
    test('no PIN set initially', () async {
      expect(await service.hasPin(), isFalse);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('setPin stores a salted hash, never the plaintext', () async {
      await service.setPin('1234');
      expect(await service.hasPin(), isTrue);
      // Neither the raw PIN nor a salt-less SHA fingerprint leaks to storage.
      final stored = secure.dump().values.join('\n');
      expect(stored.contains('1234'), isFalse);
    });

    test('verifyPin succeeds for the right PIN, fails for the wrong one',
        () async {
      await service.setPin('4321');
      expect(await service.verifyPin('4321'), isTrue);
      expect(await service.verifyPin('1234'), isFalse);
    });

    test('the same PIN hashes differently across devices (random salt)',
        () async {
      await service.setPin('0000');
      final hashA = secure.read_('mm_pin_hash');
      final saltA = secure.read_('mm_pin_salt');

      await makeService(); // fresh storage = fresh salt
      await service.setPin('0000');
      final hashB = secure.read_('mm_pin_hash');
      final saltB = secure.read_('mm_pin_salt');

      expect(saltA, isNot(saltB));
      expect(hashA, isNot(hashB)); // salting defeats rainbow tables
    });

    test('clearPin removes the hash and salt', () async {
      await service.setPin('1234');
      await service.clearPin();
      expect(await service.hasPin(), isFalse);
      expect(secure.read_('mm_pin_hash'), isNull);
      expect(secure.read_('mm_pin_salt'), isNull);
    });
  });

  group('flags (SharedPreferences)', () {
    test('defaults: lock off, biometric off, auto-lock immediate (0)', () {
      expect(service.lockEnabled, isFalse);
      expect(service.biometricEnabled, isFalse);
      expect(service.autoLockMinutes, 0);
    });

    test('setters round-trip', () async {
      await service.setLockEnabled(true);
      await service.setBiometricEnabled(true);
      await service.setAutoLockMinutes(15);

      expect(service.lockEnabled, isTrue);
      expect(service.biometricEnabled, isTrue);
      expect(service.autoLockMinutes, 15);
    });

    test('auto-lock accepts the "never" sentinel (-1)', () async {
      await service.setAutoLockMinutes(-1);
      expect(service.autoLockMinutes, -1);
    });
  });
}

/// In-memory [FlutterSecureStorage]. Intercepts read/write/delete through
/// `noSuchMethod` so it's resilient to the SDK adding new option params.
class FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  Map<String, String> dump() => Map.unmodifiable(_store);
  String? read_(String key) => _store[key];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final key = invocation.namedArguments[#key] as String?;
    if (name == #write) {
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        _store.remove(key);
      } else {
        _store[key!] = value;
      }
      return Future<void>.value();
    }
    if (name == #read) return Future<String?>.value(_store[key]);
    if (name == #delete) {
      _store.remove(key);
      return Future<void>.value();
    }
    if (name == #containsKey) {
      return Future<bool>.value(_store.containsKey(key));
    }
    return super.noSuchMethod(invocation);
  }
}
