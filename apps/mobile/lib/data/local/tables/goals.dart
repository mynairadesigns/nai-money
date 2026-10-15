import 'package:drift/drift.dart';

@DataClassName('Goal')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentAmount => real().withDefault(const Constant(0))();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get deadline => dateTime().nullable()();
  TextColumn get walletId => text().nullable()();
  TextColumn get iconName => text()();
  TextColumn get color => text()();
  TextColumn get aiPlan =>
      text().nullable()(); // JSON: AI-generated savings plan
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
