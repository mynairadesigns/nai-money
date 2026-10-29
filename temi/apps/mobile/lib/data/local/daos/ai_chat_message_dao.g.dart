// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_chat_message_dao.dart';

// ignore_for_file: type=lint
mixin _$AIChatMessageDaoMixin on DatabaseAccessor<AppDatabase> {
  $AIChatMessagesTable get aIChatMessages => attachedDatabase.aIChatMessages;
  AIChatMessageDaoManager get managers => AIChatMessageDaoManager(this);
}

class AIChatMessageDaoManager {
  final _$AIChatMessageDaoMixin _db;
  AIChatMessageDaoManager(this._db);
  $$AIChatMessagesTableTableManager get aIChatMessages =>
      $$AIChatMessagesTableTableManager(
        _db.attachedDatabase,
        _db.aIChatMessages,
      );
}
