import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:drift/drift.dart' show Value;

import '../local/app_database.dart';

/// Drift row → Firestore document payload (`users/{uid}/wallets/{walletId}`).
///
/// Per PRD §5.2, the Firestore mirror omits the local-only columns
/// (`userId`, since it's implicit in the parent doc path; `syncStatus`,
/// since it's a local-only state machine). `createdAt` and `updatedAt`
/// are written as Firestore `Timestamp` so the next slice's pull-direction
/// reconciler can compare them with `serverTimestamp` values.
Map<String, dynamic> walletToFirestore(Wallet w) => {
      'id': w.id,
      'name': w.name,
      'type': w.type,
      'currency': w.currency,
      'balance': w.balance,
      'iconName': w.iconName,
      'color': w.color,
      'isHidden': w.isHidden,
      'isArchived': w.isArchived,
      'sortOrder': w.sortOrder,
      'createdAt': Timestamp.fromDate(w.createdAt),
      'updatedAt': Timestamp.fromDate(w.updatedAt),
    };

Map<String, dynamic> categoryToFirestore(Category c) => {
      'id': c.id,
      'name': c.name,
      'type': c.type,
      'iconName': c.iconName,
      'color': c.color,
      'parentId': c.parentId,
      'isDefault': c.isDefault,
      'sortOrder': c.sortOrder,
      'createdAt': Timestamp.fromDate(c.createdAt),
      'updatedAt': Timestamp.fromDate(c.updatedAt),
    };

Map<String, dynamic> transactionToFirestore(Transaction t) => {
      'id': t.id,
      'walletId': t.walletId,
      'categoryId': t.categoryId,
      'type': t.type,
      'amount': t.amount,
      'currency': t.currency,
      'originalAmount': t.originalAmount,
      'originalCurrency': t.originalCurrency,
      'fxRate': t.fxRate,
      'date': Timestamp.fromDate(t.date),
      'note': t.note,
      'contactId': t.contactId,
      'attachmentUrl': t.attachmentUrl,
      // attachmentLocalPath is a local-only cache path — never mirror it.
      'tags': t.tags,
      'transferToWalletId': t.transferToWalletId,
      'isRecurring': t.isRecurring,
      'recurringRuleId': t.recurringRuleId,
      'aiCategorySuggested': t.aiCategorySuggested,
      'aiConfidence': t.aiConfidence,
      'aiSource': t.aiSource,
      'createdAt': Timestamp.fromDate(t.createdAt),
      'updatedAt': Timestamp.fromDate(t.updatedAt),
    };

Map<String, dynamic> budgetToFirestore(Budget b) => {
      'id': b.id,
      'categoryId': b.categoryId,
      'walletId': b.walletId,
      'period': b.period,
      'startDate': Timestamp.fromDate(b.startDate),
      'endDate': b.endDate == null ? null : Timestamp.fromDate(b.endDate!),
      'amount': b.amount,
      'currency': b.currency,
      'rollover': b.rollover,
      'thresholdPercent': b.thresholdPercent,
      'createdAt': Timestamp.fromDate(b.createdAt),
      'updatedAt': Timestamp.fromDate(b.updatedAt),
    };

Map<String, dynamic> recurringRuleToFirestore(RecurringRule r) => {
      'id': r.id,
      'transactionTemplate': r.transactionTemplate,
      'frequency': r.frequency,
      'interval': r.interval,
      'startDate': Timestamp.fromDate(r.startDate),
      'endDate': r.endDate == null ? null : Timestamp.fromDate(r.endDate!),
      'nextDueDate': Timestamp.fromDate(r.nextDueDate),
      'mode': r.mode,
      'isPaused': r.isPaused,
      'createdAt': Timestamp.fromDate(r.createdAt),
      'updatedAt': Timestamp.fromDate(r.updatedAt),
    };

Map<String, dynamic> debtToFirestore(Debt d) => {
      'id': d.id,
      'type': d.type,
      'contactName': d.contactName,
      'contactId': d.contactId,
      'originalAmount': d.originalAmount,
      'remainingAmount': d.remainingAmount,
      'currency': d.currency,
      'dueDate': d.dueDate == null ? null : Timestamp.fromDate(d.dueDate!),
      'status': d.status,
      'notes': d.notes,
      'createdAt': Timestamp.fromDate(d.createdAt),
      'settledAt':
          d.settledAt == null ? null : Timestamp.fromDate(d.settledAt!),
      'updatedAt': Timestamp.fromDate(d.updatedAt),
    };

Map<String, dynamic> debtPaymentToFirestore(DebtPayment p) => {
      'id': p.id,
      'debtId': p.debtId,
      'amount': p.amount,
      'paidAt': Timestamp.fromDate(p.paidAt),
      'note': p.note,
      'updatedAt': Timestamp.fromDate(p.updatedAt),
    };

Map<String, dynamic> goalToFirestore(Goal g) => {
      'id': g.id,
      'name': g.name,
      'targetAmount': g.targetAmount,
      'currentAmount': g.currentAmount,
      'currency': g.currency,
      'deadline': g.deadline == null ? null : Timestamp.fromDate(g.deadline!),
      'walletId': g.walletId,
      'iconName': g.iconName,
      'color': g.color,
      'aiPlan': g.aiPlan,
      'createdAt': Timestamp.fromDate(g.createdAt),
      'completedAt':
          g.completedAt == null ? null : Timestamp.fromDate(g.completedAt!),
      'updatedAt': Timestamp.fromDate(g.updatedAt),
    };

Map<String, dynamic> contactToFirestore(Contact c) => {
      'id': c.id,
      'name': c.name,
      'phone': c.phone,
      'email': c.email,
      'createdAt': Timestamp.fromDate(c.createdAt),
      'updatedAt': Timestamp.fromDate(c.updatedAt),
    };

// ---------------------------------------------------------------------------
// Reverse mappers — Firestore Map → Drift Companion. Used by the
// FirestoreHydrator (P2.7) on sign-in to materialise remote rows. Every
// reverse mapper stamps `syncStatus: 'synced'` since the row already
// exists in Firestore — flipping it to 'pending' would re-push it.
// `userId` is supplied by the caller (it's implicit in the parent doc
// path so isn't stored in the Firestore doc).
// ---------------------------------------------------------------------------

DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;

DateTime _tsReq(dynamic v, {DateTime? fallback}) =>
    _ts(v) ?? (fallback ?? DateTime.now());

WalletsCompanion walletFromFirestore(Map<String, dynamic> d, String uid) =>
    WalletsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      name: Value(d['name'] as String? ?? ''),
      type: Value(d['type'] as String? ?? 'cash'),
      currency: Value(d['currency'] as String? ?? 'NGN'),
      balance: Value((d['balance'] as num?)?.toDouble() ?? 0),
      iconName: Value(d['iconName'] as String? ?? 'payments'),
      color: Value(d['color'] as String? ?? '8a4f37'),
      isHidden: Value(d['isHidden'] as bool? ?? false),
      isArchived: Value(d['isArchived'] as bool? ?? false),
      sortOrder: Value(d['sortOrder'] as int? ?? 0),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

CategoriesCompanion categoryFromFirestore(
        Map<String, dynamic> d, String uid) =>
    CategoriesCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      name: Value(d['name'] as String? ?? ''),
      type: Value(d['type'] as String? ?? 'expense'),
      iconName: Value(d['iconName'] as String? ?? 'label'),
      color: Value(d['color'] as String? ?? '8a4f37'),
      parentId: Value(d['parentId'] as String?),
      isDefault: Value(d['isDefault'] as bool? ?? false),
      sortOrder: Value(d['sortOrder'] as int? ?? 0),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

TransactionsCompanion transactionFromFirestore(
        Map<String, dynamic> d, String uid) =>
    TransactionsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      walletId: Value(d['walletId'] as String? ?? ''),
      categoryId: Value(d['categoryId'] as String? ?? ''),
      type: Value(d['type'] as String? ?? 'expense'),
      amount: Value((d['amount'] as num?)?.toDouble() ?? 0),
      currency: Value(d['currency'] as String? ?? 'NGN'),
      originalAmount: Value((d['originalAmount'] as num?)?.toDouble()),
      originalCurrency: Value(d['originalCurrency'] as String?),
      fxRate: Value((d['fxRate'] as num?)?.toDouble()),
      date: Value(_tsReq(d['date'])),
      note: Value(d['note'] as String?),
      contactId: Value(d['contactId'] as String?),
      attachmentUrl: Value(d['attachmentUrl'] as String?),
      // attachmentLocalPath stays unset — local cache only
      tags: Value(d['tags'] as String?),
      transferToWalletId: Value(d['transferToWalletId'] as String?),
      isRecurring: Value(d['isRecurring'] as bool? ?? false),
      recurringRuleId: Value(d['recurringRuleId'] as String?),
      aiCategorySuggested: Value(d['aiCategorySuggested'] as bool? ?? false),
      aiConfidence: Value((d['aiConfidence'] as num?)?.toDouble()),
      aiSource: Value(d['aiSource'] as String?),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

BudgetsCompanion budgetFromFirestore(Map<String, dynamic> d, String uid) =>
    BudgetsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      categoryId: Value(d['categoryId'] as String?),
      walletId: Value(d['walletId'] as String?),
      period: Value(d['period'] as String? ?? 'monthly'),
      startDate: Value(_tsReq(d['startDate'])),
      endDate: Value(_ts(d['endDate'])),
      amount: Value((d['amount'] as num?)?.toDouble() ?? 0),
      currency: Value(d['currency'] as String? ?? 'NGN'),
      rollover: Value(d['rollover'] as bool? ?? false),
      thresholdPercent: Value(d['thresholdPercent'] as int? ?? 80),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

RecurringRulesCompanion recurringRuleFromFirestore(
        Map<String, dynamic> d, String uid) =>
    RecurringRulesCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      transactionTemplate: Value(d['transactionTemplate'] as String? ?? '{}'),
      frequency: Value(d['frequency'] as String? ?? 'monthly'),
      interval: Value(d['interval'] as int? ?? 1),
      startDate: Value(_tsReq(d['startDate'])),
      endDate: Value(_ts(d['endDate'])),
      nextDueDate: Value(_tsReq(d['nextDueDate'])),
      mode: Value(d['mode'] as String? ?? 'auto'),
      isPaused: Value(d['isPaused'] as bool? ?? false),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

DebtsCompanion debtFromFirestore(Map<String, dynamic> d, String uid) =>
    DebtsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      type: Value(d['type'] as String? ?? 'lent'),
      contactName: Value(d['contactName'] as String? ?? ''),
      contactId: Value(d['contactId'] as String?),
      originalAmount: Value((d['originalAmount'] as num?)?.toDouble() ?? 0),
      remainingAmount: Value((d['remainingAmount'] as num?)?.toDouble() ?? 0),
      currency: Value(d['currency'] as String? ?? 'NGN'),
      dueDate: Value(_ts(d['dueDate'])),
      status: Value(d['status'] as String? ?? 'open'),
      notes: Value(d['notes'] as String?),
      createdAt: Value(_tsReq(d['createdAt'])),
      settledAt: Value(_ts(d['settledAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

DebtPaymentsCompanion debtPaymentFromFirestore(
        Map<String, dynamic> d, String uid) =>
    DebtPaymentsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      debtId: Value(d['debtId'] as String? ?? ''),
      amount: Value((d['amount'] as num?)?.toDouble() ?? 0),
      paidAt: Value(_tsReq(d['paidAt'])),
      note: Value(d['note'] as String?),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

GoalsCompanion goalFromFirestore(Map<String, dynamic> d, String uid) =>
    GoalsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      name: Value(d['name'] as String? ?? ''),
      targetAmount: Value((d['targetAmount'] as num?)?.toDouble() ?? 0),
      currentAmount: Value((d['currentAmount'] as num?)?.toDouble() ?? 0),
      currency: Value(d['currency'] as String? ?? 'NGN'),
      deadline: Value(_ts(d['deadline'])),
      walletId: Value(d['walletId'] as String?),
      iconName: Value(d['iconName'] as String? ?? 'label'),
      color: Value(d['color'] as String? ?? '8a4f37'),
      aiPlan: Value(d['aiPlan'] as String?),
      createdAt: Value(_tsReq(d['createdAt'])),
      completedAt: Value(_ts(d['completedAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );

ContactsCompanion contactFromFirestore(
        Map<String, dynamic> d, String uid) =>
    ContactsCompanion(
      id: Value(d['id'] as String),
      userId: Value(uid),
      name: Value(d['name'] as String? ?? ''),
      phone: Value(d['phone'] as String?),
      email: Value(d['email'] as String?),
      createdAt: Value(_tsReq(d['createdAt'])),
      updatedAt: Value(_tsReq(d['updatedAt'])),
      syncStatus: const Value('synced'),
    );
