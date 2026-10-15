import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/ai_chat_messages.dart';

part 'ai_chat_message_dao.g.dart';

@DriftAccessor(tables: [AIChatMessages])
class AIChatMessageDao extends DatabaseAccessor<AppDatabase>
    with _$AIChatMessageDaoMixin {
  AIChatMessageDao(super.db);

  Stream<List<AIChatMessage>> watchAll() => select(aIChatMessages).watch();

  Future<AIChatMessage?> getById(String id) =>
      (select(aIChatMessages)..where((m) => m.id.equals(id)))
          .getSingleOrNull();

  Future<void> insertOne(AIChatMessagesCompanion row) =>
      into(aIChatMessages).insert(row);

  Future<bool> updateOne(AIChatMessagesCompanion row) =>
      update(aIChatMessages).replace(row);

  Future<int> deleteById(String id) =>
      (delete(aIChatMessages)..where((m) => m.id.equals(id))).go();
}
