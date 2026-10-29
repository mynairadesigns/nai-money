import 'package:drift/drift.dart';

@DataClassName('Budget')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get categoryId => text().nullable()(); // null = wallet-wide
  TextColumn get walletId => text().nullable()();
  TextColumn get period => text()(); // weekly, monthly, custom
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  RealColumn get amount => real()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  IntColumn get thresholdPercent =>
      integer().withDefault(const Constant(80))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
