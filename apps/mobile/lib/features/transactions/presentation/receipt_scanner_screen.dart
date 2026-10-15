import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/ai_service.dart';
import '../../../data/remote/storage_service.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../data/transaction_form_state.dart' show ReceiptPrefill;
import '../widgets/receipt_picker_sheet.dart';
import 'add_transaction_sheet.dart';

/// PRD §11.4 receipt-scanner flow.
///
/// State machine:
///   `idle → picking → uploading → scanning → done`
///
/// The user enters via MainShell's Add menu → "Scan receipt". On mount
/// we open the picker sheet (camera / library), upload the chosen image
/// to a temp Storage path, call the `scanReceipt` Function, then pop
/// ourselves and open the Add Transaction sheet pre-filled with the
/// parsed merchant/amount/date/category. On any failure we SnackBar and
/// pop back.
class ReceiptScannerScreen extends ConsumerStatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  ConsumerState<ReceiptScannerScreen> createState() =>
      _ReceiptScannerScreenState();
}

enum _ScannerStage { idle, picking, uploading, scanning, done }

class _ReceiptScannerScreenState extends ConsumerState<ReceiptScannerScreen> {
  _ScannerStage _stage = _ScannerStage.idle;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started || !mounted) return;
      _started = true;
      _run();
    });
  }

  Future<void> _run() async {
    setState(() => _stage = _ScannerStage.picking);
    final XFile? picked = await showReceiptPicker(context);
    if (!mounted) return;
    if (picked == null) {
      context.pop();
      return;
    }

    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid == null) {
      _failAndPop('You need to be signed in to scan receipts.');
      return;
    }

    // -------- Upload --------
    setState(() => _stage = _ScannerStage.uploading);
    final String tempStoragePath;
    final String downloadUrl;
    try {
      final storage = ref.read(storageServiceProvider);
      final res = await storage.uploadReceiptTemp(
        uid: uid,
        file: File(picked.path),
      );
      downloadUrl = res.downloadUrl;
      tempStoragePath = res.storagePath;
    } catch (_) {
      _failAndPop('Could not upload the receipt. Check your connection.');
      return;
    }
    if (!mounted) return;

    // -------- Scan --------
    setState(() => _stage = _ScannerStage.scanning);

    // Pick the default currency from the user's first wallet (PRD §6.4.1
    // — the form lets the user override before saving anyway).
    final wallets =
        ref.read(visibleWalletsProvider).value ?? const <Wallet>[];
    final defaultCurrency =
        wallets.isNotEmpty ? wallets.first.currency : 'USD';

    final expenseCategories = [
      for (final c in (ref.read(categoriesListProvider).value ??
              const <Category>[])
          .where((c) => c.type == 'expense'))
        (id: c.id, name: c.name),
    ];

    final ReceiptScanResult result;
    try {
      result = await ref.read(aiServiceProvider).scanReceipt(
            imageUrl: downloadUrl,
            defaultCurrency: defaultCurrency,
            expenseCategories: expenseCategories,
          );
    } catch (e) {
      // Best-effort temp cleanup so we don't leak orphaned uploads on
      // every failed scan.
      ref.read(storageServiceProvider).deleteTempReceipt(tempStoragePath);
      _failAndPop(_friendlyAiError(e));
      return;
    }
    if (!mounted) return;

    // -------- Hand off to the Add Transaction sheet --------
    setState(() => _stage = _ScannerStage.done);

    // The temp upload (`receipts/temp/...`) is carried into the form via
    // `tempReceiptUrl`. On save, TransactionsController promotes it to the
    // permanent path `receipts/{txId}.jpg` and deletes the temp; on a
    // dismiss-without-save the sheet deletes the temp (P4.2.1).
    final prefill = ReceiptPrefill(
      merchant: result.merchant,
      total: result.total,
      currency: result.currency,
      date: result.date,
      suggestedCategoryId: result.suggestedCategoryId,
      confidence: result.confidence,
      tempReceiptUrl: tempStoragePath,
    );

    // Pop the scanner first so the Add Transaction sheet appears over
    // whatever screen the user originally launched from.
    context.pop();
    // ignore: use_build_context_synchronously
    await showAddTransactionSheet(context, prefill: prefill);
  }

  void _failAndPop(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }

  String _friendlyAiError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('quota') || msg.contains('limit')) {
      return 'You\'ve used your AI actions for this month.';
    }
    if (msg.contains('network') || msg.contains('unavailable')) {
      return 'Couldn\'t reach the AI service. Try again in a moment.';
    }
    return 'Couldn\'t read this receipt. Try a clearer photo.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan receipt'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_stage) {
      case _ScannerStage.idle:
      case _ScannerStage.picking:
        // The picker sheet covers this — keep the body empty so we
        // don't show a flash of stale UI behind the modal.
        return const SizedBox.shrink();
      case _ScannerStage.uploading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text('Uploading...', style: theme.textTheme.bodyLarge),
            ],
          ),
        );
      case _ScannerStage.scanning:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: 96),
              const SizedBox(height: AppSpacing.xl),
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Reading your receipt...',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This usually takes a few seconds.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      case _ScannerStage.done:
        return const SizedBox.shrink();
    }
  }
}
