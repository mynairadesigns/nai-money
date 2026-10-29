import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// Form payload for create / edit. Plain mutable POJO — UI mutates in
/// place, then calls [CategoriesController.create] or `.edit`.
class CategoryFormData {
  CategoryFormData({
    this.id,
    this.name = '',
    this.type = 'expense',
    this.iconName = 'label',
    this.colorHex = '8a4f37',
  });

  /// Non-null when editing an existing category.
  String? id;
  String name;
  String type; // 'expense' | 'income'
  String iconName;
  String colorHex;
}

final categoriesControllerProvider =
    AsyncNotifierProvider<CategoriesController, void>(
  CategoriesController.new,
);

class CategoriesController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Inserts a new user-defined category. `isDefault: false` distinguishes
  /// these from the setup-wizard starters (which use `isDefault: true`).
  Future<void> create(CategoryFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a category while signed out');
      }
      final dao = ref.read(categoryDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_c_${now.microsecondsSinceEpoch}';
      await dao.insertOne(
        CategoriesCompanion(
          id: Value(id),
          userId: Value(user.uid),
          name: Value(form.name.trim()),
          type: Value(form.type),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          isDefault: const Value(false),
          sortOrder: Value(now.microsecondsSinceEpoch ~/ 1000),
          createdAt: Value(now),
          updatedAt: Value(now),
          // syncStatus defaults to 'pending' — sync engine mirrors it.
        ),
      );
    });
  }

  /// Updates an existing category's name/type/icon/color. Must reset
  /// `syncStatus` to 'pending' so the sync engine re-mirrors (per
  /// CLAUDE.md §8). Named `edit` to avoid colliding with
  /// AsyncNotifier.update.
  Future<void> edit(CategoryFormData form) async {
    final id = form.id;
    if (id == null) {
      throw ArgumentError('edit requires a non-null id');
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(categoryDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Category $id not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        CategoriesCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(form.name.trim()),
          type: Value(form.type),
          iconName: Value(form.iconName),
          color: Value(form.colorHex),
          parentId: Value(existing.parentId),
          isDefault: Value(existing.isDefault),
          sortOrder: Value(existing.sortOrder),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  /// Deletes a category. Transaction-reference safety check lands in
  /// P2.3 when Transactions are real (PRD §6.3 wired); for now we trust
  /// the caller. Firestore delete-mirror lands in P2.6.
  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(categoryDaoProvider);
      await dao.deleteById(id);
    });
  }
}
