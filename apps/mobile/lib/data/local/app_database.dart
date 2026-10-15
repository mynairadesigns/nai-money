import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/ai_chat_message_dao.dart';
import 'daos/budget_dao.dart';
import 'daos/category_dao.dart';
import 'daos/contact_dao.dart';
import 'daos/debt_dao.dart';
import 'daos/goal_dao.dart';
import 'daos/recurring_rule_dao.dart';
import 'daos/subscription_detection_dao.dart';
import 'daos/transaction_dao.dart';
import 'daos/wallet_dao.dart';
import 'tables/ai_chat_messages.dart';
import 'tables/budgets.dart';
import 'tables/categories.dart';
import 'tables/contacts.dart';
import 'tables/debt_payments.dart';
import 'tables/debts.dart';
import 'tables/goals.dart';
import 'tables/recurring_rules.dart';
import 'tables/subscription_detections.dart';
import 'tables/transactions.dart';
import 'tables/wallets.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    Budgets,
    RecurringRules,
    Debts,
    DebtPayments,
    Goals,
    Contacts,
    AIChatMessages,
    SubscriptionDetections,
  ],
  daos: [
    WalletDao,
    CategoryDao,
    TransactionDao,
    BudgetDao,
    RecurringRuleDao,
    DebtDao,
    GoalDao,
    ContactDao,
    AIChatMessageDao,
    SubscriptionDetectionDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 → v2: PRD §5.1 alignment — every table now carries
          // `userId`, `updatedAt`, `syncStatus`. P1 testers had no real
          // data, so we recreate every table rather than write per-table
          // ALTERs. Sacrifices any local-only v1 rows.
          if (from < 2) {
            for (final table in allTables.toList().reversed) {
              await m.deleteTable(table.actualTableName);
            }
            await m.createAll();
          }
        },
      );
}

QueryExecutor _openConnection() {
  // drift_flutter's `driftDatabase` helper handles the application documents
  // directory, isolate setup, and uses `sqlite3_flutter_libs` under the hood.
  // SQLCipher encryption will be wired up in P7 polish.
  return driftDatabase(name: 'finance_ai');
}
