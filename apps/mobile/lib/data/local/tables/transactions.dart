import 'package:drift/drift.dart';

import 'categories.dart';
import 'wallets.dart';

@DataClassName('Transaction')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get type => text()(); // income, expense, transfer
  RealColumn get amount => real()(); // in wallet's currency
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  RealColumn get originalAmount => real().nullable()();
  TextColumn get originalCurrency => text().nullable()();
  RealColumn get fxRate => real().nullable()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get contactId => text().nullable()();
  TextColumn get attachmentUrl => text().nullable()(); // Firebase Storage URL
  TextColumn get attachmentLocalPath => text().nullable()();
  TextColumn get tags => text().nullable()(); // JSON array
  TextColumn get transferToWalletId => text().nullable()();
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();
  TextColumn get recurringRuleId => text().nullable()();
  BoolColumn get aiCategorySuggested =>
      boolean().withDefault(const Constant(false))();
  RealColumn get aiConfidence => real().nullable()();
  TextColumn get aiSource =>
      text().nullable()(); // receipt_scan, manual, subscription_detector
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
