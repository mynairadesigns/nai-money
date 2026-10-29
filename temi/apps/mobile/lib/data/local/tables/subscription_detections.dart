import 'package:drift/drift.dart';

@DataClassName('SubscriptionDetection')
class SubscriptionDetections extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get merchantName => text()();
  RealColumn get amount => real()();
  TextColumn get currency => text()();
  TextColumn get frequency => text()(); // monthly, yearly
  IntColumn get confidence => integer()(); // 0-100
  TextColumn get status => text()(); // detected, confirmed, dismissed
  DateTimeColumn get firstSeen => dateTime()();
  DateTimeColumn get lastSeen => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
