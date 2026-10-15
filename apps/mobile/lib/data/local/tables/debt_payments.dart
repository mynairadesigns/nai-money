import 'package:drift/drift.dart';

import 'debts.dart';

@DataClassName('DebtPayment')
class DebtPayments extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get debtId => text().references(Debts, #id)();
  RealColumn get amount => real()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
