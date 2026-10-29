import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../data/local/app_database.dart';

/// Form payload for create / edit. Mutable POJO — UI mutates in place,
/// then calls [ContactsController.create] or `.edit`.
class ContactFormData {
  ContactFormData({
    this.id,
    this.name = '',
    this.phone,
    this.email,
  });

  /// Non-null when editing an existing contact.
  String? id;
  String name;
  String? phone;
  String? email;
}

final contactsControllerProvider =
    AsyncNotifierProvider<ContactsController, void>(ContactsController.new);

/// AsyncNotifier driving contact create / edit / delete and the
/// "find-or-create by name" lookup used by the inline picker tile.
///
/// Naming: `edit` (not `update`) to avoid colliding with
/// `AsyncNotifier.update`.
class ContactsController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> create(ContactFormData form) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = ref.read(authServiceProvider).currentUser;
      if (user == null) {
        throw StateError('Cannot create a contact while signed out');
      }
      final dao = ref.read(contactDaoProvider);
      final now = DateTime.now().toUtc();
      final id = '${user.uid}_ct_${now.microsecondsSinceEpoch}';
      await dao.insertOne(
        ContactsCompanion(
          id: Value(id),
          userId: Value(user.uid),
          name: Value(form.name.trim()),
          phone: Value(_nullIfBlank(form.phone)),
          email: Value(_nullIfBlank(form.email)),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> edit(ContactFormData form) async {
    final id = form.id;
    if (id == null) throw ArgumentError('edit requires a non-null id');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final dao = ref.read(contactDaoProvider);
      final existing = await dao.getById(id);
      if (existing == null) throw StateError('Contact $id not found');
      final now = DateTime.now().toUtc();
      await dao.updateOne(
        ContactsCompanion(
          id: Value(id),
          userId: Value(existing.userId),
          name: Value(form.name.trim()),
          phone: Value(_nullIfBlank(form.phone)),
          email: Value(_nullIfBlank(form.email)),
          createdAt: Value(existing.createdAt),
          updatedAt: Value(now),
          syncStatus: const Value('pending'),
        ),
      );
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(contactDaoProvider).deleteById(id);
    });
  }

  /// Case-insensitive lookup against the current user's contacts. If a
  /// row with the same trimmed name exists, returns its id; otherwise
  /// inserts a new contact (name only) and returns the new id.
  ///
  /// Used by the contact picker's inline `Create '<typed>'` tile.
  Future<String> findOrCreateByName(String rawName) async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) {
      throw StateError('Cannot create a contact while signed out');
    }
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Contact name cannot be empty');
    }
    final dao = ref.read(contactDaoProvider);
    final rows = await dao.watchAll().first;
    final lower = name.toLowerCase();
    for (final c in rows) {
      if (c.userId == user.uid && c.name.toLowerCase() == lower) {
        return c.id;
      }
    }
    final now = DateTime.now().toUtc();
    final id = '${user.uid}_ct_${now.microsecondsSinceEpoch}';
    await dao.insertOne(
      ContactsCompanion(
        id: Value(id),
        userId: Value(user.uid),
        name: Value(name),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  String? _nullIfBlank(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
