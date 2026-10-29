import 'package:drift/drift.dart';

@DataClassName('RecurringRule')
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get transactionTemplate =>
      text()(); // JSON: type, amount, walletId, categoryId, note
  TextColumn get frequency => text()(); // daily, weekly, monthly, yearly
  IntColumn get interval => integer().withDefault(const Constant(1))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get nextDueDate => dateTime()();
  TextColumn get mode => text()(); // auto, reminder
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
