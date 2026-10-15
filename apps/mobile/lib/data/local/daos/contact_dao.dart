import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/contacts.dart';

part 'contact_dao.g.dart';

@DriftAccessor(tables: [Contacts])
class ContactDao extends DatabaseAccessor<AppDatabase> with _$ContactDaoMixin {
  ContactDao(super.db);

  Stream<List<Contact>> watchAll() => select(contacts).watch();

  Future<Contact?> getById(String id) =>
      (select(contacts)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<void> insertOne(ContactsCompanion row) => into(contacts).insert(row);

  Future<void> upsertOne(ContactsCompanion row) =>
      into(contacts).insertOnConflictUpdate(row);

  Future<bool> updateOne(ContactsCompanion row) =>
      update(contacts).replace(row);

  Future<int> deleteById(String id) =>
      (delete(contacts)..where((c) => c.id.equals(id))).go();

  Stream<List<Contact>> watchPendingForUser(String userId) =>
      (select(contacts)
            ..where(
              (c) => c.userId.equals(userId) & c.syncStatus.equals('pending'),
            ))
          .watch();

  Future<void> markSynced(String id) =>
      (update(contacts)..where((c) => c.id.equals(id)))
          .write(const ContactsCompanion(syncStatus: Value('synced')));
}
