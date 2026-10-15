import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/providers/setup_state_provider.dart';
import '../../../data/local/app_database.dart';
import '../data/setup_catalog.dart';

/// Form state carried across the wizard's PageView. Mutable in place so
/// each step can update its own slice without the wizard rebuilding from
/// scratch.
class SetupFormState {
  SetupFormState({
    this.currency = 'USD',
    this.monthlyIncome,
    Set<String>? selectedCategoryKeys,
  }) : selectedCategoryKeys = selectedCategoryKeys ?? <String>{};

  String currency;
  double? monthlyIncome;
  Set<String> selectedCategoryKeys;

  bool get hasMinCategories =>
      selectedCategoryKeys.length >= kMinCategoryPicks;
  bool get hasMaxCategories =>
      selectedCategoryKeys.length >= kMaxCategoryPicks;
}

final setupFormProvider = Provider<SetupFormState>((ref) => SetupFormState());

/// Drives the wizard's final commit: writes Drift categories, mirrors to
/// Firestore, flips the local completion flag. UI watches the
/// [AsyncValue] for loading + error.
final setupControllerProvider =
    AsyncNotifierProvider<SetupController, void>(SetupController.new);

class SetupController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> commit() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot complete setup without an authenticated user');
      }
      final form = ref.read(setupFormProvider);
      final categoryDao = ref.read(categoryDaoProvider);
      final firestore = ref.read(firestoreServiceProvider);

      final now = DateTime.now().toUtc();
      final selected = kStarterCategories
          .where((c) => form.selectedCategoryKeys.contains(c.key))
          .toList();

      for (var i = 0; i < selected.length; i++) {
        final c = selected[i];
        await categoryDao.insertOne(
          CategoriesCompanion(
            id: Value('${user.uid}_${c.key}'),
            userId: Value(user.uid),
            name: Value(c.name),
            type: Value(c.type),
            iconName: Value(c.iconName),
            color: Value(c.colorHex),
            isDefault: const Value(true),
            sortOrder: Value(i),
            createdAt: Value(now),
            updatedAt: Value(now),
            // syncStatus defaults to 'pending' per PRD §5.3 — the next
            // slice (per-table write-through) flips it to 'synced'.
          ),
        );
      }

      // Bounded: offline, the Firestore SDK holds the write in its local
      // queue and only resolves this future once the server acks, which
      // would hang the wizard forever. The queued write still replays on
      // reconnect, so timing out here loses nothing.
      await firestore
          .updateUserSetup(
            uid: user.uid,
            defaultCurrency: form.currency,
            monthlyIncome: form.monthlyIncome,
          )
          .timeout(const Duration(seconds: 8), onTimeout: () {});

      // Local flag last, and keyed by uid — this is what lets a re-login
      // skip the wizard without waiting on a network read.
      await ref.read(setupStatusProvider.notifier).markCompleted(user.uid);
    });
  }
}
