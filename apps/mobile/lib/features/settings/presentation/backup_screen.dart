import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/firestore_hydrator.dart';
import '../../../data/sync/sync_lifecycle_provider.dart';

/// PRD §11.7: Backup & restore screen.
///
/// Tiles:
///  • Sync now — re-runs the Firestore→Drift hydrate + kicks the write-through
///    engine for the current user.
///  • Export data as JSON — reads every synced Drift table scoped to the
///    current user, encodes them, and shares via `share_plus`.
///  • Reset all data (destructive) — typed-DELETE confirmation, then wipes
///    every Drift row owned by the user.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _syncing = false;
  bool _exporting = false;
  bool _resetting = false;

  Future<void> _syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _syncing = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final firestore = ref.read(firestoreProvider);
      // Pull-direction hydrate (same as sign-in).
      final hydrator = FirestoreHydrator(firestore, db);
      await hydrator.hydrate(user.uid);
      // Restart write-through engine so any pending rows flush immediately.
      ref.read(firestoreSyncServiceProvider).startForUser(user.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Synced successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _exportJson() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _exporting = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final uid = user.uid;

      // Gather rows from all 9 synced tables filtered by userId.
      final wallets = await db.walletDao.watchAll().first;
      final categories = await db.categoryDao.watchAll().first;
      final txns = await db.transactionDao.watchAll().first;
      final budgets = await db.budgetDao.watchAll().first;
      final rules = await db.recurringRuleDao.watchAll().first;
      final debts = await db.debtDao.watchAll().first;
      final goals = await db.goalDao.watchAll().first;
      final contacts = await db.contactDao.watchAll().first;

      // DebtPayments: no standalone watchAll — gather by each debt.
      final List<DebtPayment> allPayments = [];
      for (final d in debts.where((d) => d.userId == uid)) {
        final payments = await db.debtDao.watchPaymentsForDebt(d.id).first;
        allPayments.addAll(payments);
      }

      final payload = <String, List<Map<String, dynamic>>>{
        'wallets': wallets
            .where((w) => w.userId == uid)
            .map((w) => w.toJson())
            .toList(),
        'categories': categories
            .where((c) => c.userId == uid)
            .map((c) => c.toJson())
            .toList(),
        'transactions': txns
            .where((t) => t.userId == uid)
            .map((t) => t.toJson())
            .toList(),
        'budgets': budgets
            .where((b) => b.userId == uid)
            .map((b) => b.toJson())
            .toList(),
        'recurringRules': rules
            .where((r) => r.userId == uid)
            .map((r) => r.toJson())
            .toList(),
        'debts': debts
            .where((d) => d.userId == uid)
            .map((d) => d.toJson())
            .toList(),
        'debtPayments': allPayments
            .where((p) => p.userId == uid)
            .map((p) => p.toJson())
            .toList(),
        'goals': goals
            .where((g) => g.userId == uid)
            .map((g) => g.toJson())
            .toList(),
        'contacts': contacts
            .where((c) => c.userId == uid)
            .map((c) => c.toJson())
            .toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(payload);
      final now = DateTime.now();
      final filename =
          'moneymind_export_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';

      if (kIsWeb) {
        // Web: hand over a real .json file. share_plus uses the browser's
        // share sheet where available and otherwise downloads the file.
        await Share.shareXFiles(
          [
            XFile.fromData(
              utf8.encode(json),
              mimeType: 'application/json',
              name: filename,
            ),
          ],
          subject: filename,
        );
      } else {
        // share_plus 10.x: Share.share(text, subject:)
        await Share.share(json, subject: filename);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _resetData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Typed-DELETE confirmation dialog.
    final confirmed = await _showDeleteConfirmDialog(context);
    if (confirmed != true) return;

    setState(() => _resetting = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final uid = user.uid;

      // Wipe all rows owned by this user across all 9 synced tables.
      await db.transaction(() async {
        // Contacts
        await (db.delete(db.contacts)
              ..where((c) => c.userId.equals(uid)))
            .go();
        // Goals
        await (db.delete(db.goals)
              ..where((g) => g.userId.equals(uid)))
            .go();
        // DebtPayments carries its own `userId`, so delete by owner in one
        // statement. Cascading via the surviving debt rows instead (as this
        // did) misses payments whose parent debt was already deleted —
        // `DebtDao.deleteById` drops only the debt row and there's no
        // ON DELETE CASCADE, so those orphans outlived a "reset all data".
        await (db.delete(db.debtPayments)
              ..where((p) => p.userId.equals(uid)))
            .go();
        // Debts
        await (db.delete(db.debts)
              ..where((d) => d.userId.equals(uid)))
            .go();
        // Recurring rules
        await (db.delete(db.recurringRules)
              ..where((r) => r.userId.equals(uid)))
            .go();
        // Budgets
        await (db.delete(db.budgets)
              ..where((b) => b.userId.equals(uid)))
            .go();
        // Transactions
        await (db.delete(db.transactions)
              ..where((t) => t.userId.equals(uid)))
            .go();
        // Categories
        await (db.delete(db.categories)
              ..where((c) => c.userId.equals(uid)))
            .go();
        // Wallets
        await (db.delete(db.wallets)
              ..where((w) => w.userId.equals(uid)))
            .go();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All local data cleared.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) {
            return AlertDialog(
              title: const Text('Reset all data?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This permanently removes all wallets, transactions, '
                    'budgets and every other local record. '
                    'Type DELETE to confirm.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setInner(() {}),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: AppBorderRadius.base,
                      ),
                      hintText: 'DELETE',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: ctrl.text == 'DELETE'
                      ? () => Navigator.of(ctx).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.sm),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: const Text('Fetch latest data from the cloud'),
            trailing: _syncing
                ? SizedBox(
                    width: AppSpacing.md,
                    height: AppSpacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _syncing ? null : _syncNow,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export data as JSON'),
            subtitle: const Text('Share a backup of all your records'),
            trailing: _exporting
                ? SizedBox(
                    width: AppSpacing.md,
                    height: AppSpacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _exporting ? null : _exportJson,
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Reset all data',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: Text(
              'Permanently removes all local records',
              style: TextStyle(
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
            ),
            trailing: _resetting
                ? SizedBox(
                    width: AppSpacing.md,
                    height: AppSpacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.error,
                    ),
                  )
                : Icon(Icons.chevron_right, color: theme.colorScheme.error),
            onTap: _resetting ? null : _resetData,
          ),
        ],
      ),
    );
  }
}
