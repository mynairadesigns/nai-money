import 'package:drift/drift.dart';

@DataClassName('Wallet')
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // cash, bank, credit_card, e_wallet, investment
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  RealColumn get balance => real().withDefault(const Constant(0))();
  TextColumn get iconName => text()();
  TextColumn get color => text()();
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
