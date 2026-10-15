import 'package:drift/drift.dart';

@DataClassName('Debt')
class Debts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get type => text()(); // lent, borrowed
  TextColumn get contactName => text()();
  TextColumn get contactId => text().nullable()();
  RealColumn get originalAmount => real()();
  RealColumn get remainingAmount => real()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => text()(); // open, due_soon, overdue, settled
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get settledAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
