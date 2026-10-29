import 'package:drift/drift.dart';

@DataClassName('AIChatMessage')
class AIChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get sessionId => text()();
  TextColumn get role => text()(); // user, assistant, system
  TextColumn get content => text()();
  TextColumn get contextData =>
      text().nullable()(); // JSON: transactions used for RAG
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
