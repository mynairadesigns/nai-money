import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/daos/ai_chat_message_dao.dart';
import '../../data/local/daos/budget_dao.dart';
import '../../data/local/daos/category_dao.dart';
import '../../data/local/daos/contact_dao.dart';
import '../../data/local/daos/debt_dao.dart';
import '../../data/local/daos/goal_dao.dart';
import '../../data/local/daos/recurring_rule_dao.dart';
import '../../data/local/daos/subscription_detection_dao.dart';
import '../../data/local/daos/transaction_dao.dart';
import '../../data/local/daos/wallet_dao.dart';

/// App-wide [AppDatabase] singleton (Drift, source of truth on device).
/// Closed automatically when the ProviderScope tears down.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// DAO providers — feature code reads these (never appDatabaseProvider directly)
// so individual features depend on the smallest surface they need.

final walletDaoProvider = Provider<WalletDao>(
  (ref) => ref.watch(appDatabaseProvider).walletDao,
);

final categoryDaoProvider = Provider<CategoryDao>(
  (ref) => ref.watch(appDatabaseProvider).categoryDao,
);

final transactionDaoProvider = Provider<TransactionDao>(
  (ref) => ref.watch(appDatabaseProvider).transactionDao,
);

final budgetDaoProvider = Provider<BudgetDao>(
  (ref) => ref.watch(appDatabaseProvider).budgetDao,
);

final recurringRuleDaoProvider = Provider<RecurringRuleDao>(
  (ref) => ref.watch(appDatabaseProvider).recurringRuleDao,
);

final debtDaoProvider = Provider<DebtDao>(
  (ref) => ref.watch(appDatabaseProvider).debtDao,
);

final goalDaoProvider = Provider<GoalDao>(
  (ref) => ref.watch(appDatabaseProvider).goalDao,
);

final contactDaoProvider = Provider<ContactDao>(
  (ref) => ref.watch(appDatabaseProvider).contactDao,
);

final aiChatMessageDaoProvider = Provider<AIChatMessageDao>(
  (ref) => ref.watch(appDatabaseProvider).aIChatMessageDao,
);

final subscriptionDetectionDaoProvider = Provider<SubscriptionDetectionDao>(
  (ref) => ref.watch(appDatabaseProvider).subscriptionDetectionDao,
);
