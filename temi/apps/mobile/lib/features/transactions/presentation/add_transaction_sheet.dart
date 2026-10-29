import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/local/app_database.dart';
import '../../../data/remote/storage_service.dart';
import '../../categories/data/category_catalog.dart';
import '../../categories/providers/categories_list_provider.dart';
import '../../wallets/providers/wallets_list_provider.dart';
import '../../wallets/widgets/wallet_card.dart';
import '../../billing/data/free_tier_exception.dart';
import '../../billing/widgets/upsell_sheet.dart';
import '../data/transaction_form_state.dart';
import '../providers/transactions_controller.dart';
import '../widgets/ai_category_suggestion_chip.dart';
import '../widgets/fx_rate_field.dart';

/// Opens the Add Transaction modal. Returns `true` on save, `null` on
/// dismiss. Used by the central FAB on MainShell and the Home + wallet
/// detail screens.
///
/// [prefill] (P4.2) initializes the form from a receipt-scan result —
/// merchant→note, total→amount, date, suggested category, AI source
/// stamp, and the temp Storage URL.
Future<bool?> showAddTransactionSheet(
  BuildContext context, {
  Transaction? existing,
  ReceiptPrefill? prefill,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) => _AddTransactionSheet(existing: existing, prefill: prefill),
  );
}

class _AddTransactionSheet extends ConsumerStatefulWidget {
  const _AddTransactionSheet({required this.existing, this.prefill});
  final Transaction? existing;
  final ReceiptPrefill? prefill;

  @override
  ConsumerState<_AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<_AddTransactionSheet> {
  late final TransactionFormData _form;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;

  /// Transfer destination wallet (only used when `_form.type == 'transfer'`).
  String? _destWalletId;

  /// Latest FX rate from [FxRateField], or 1.0 if same-currency / not
  /// yet fetched.
  double? _fxRate;

  final _formKey = GlobalKey<FormState>();

  /// Set true once a save succeeds. Gates the dispose-time temp-receipt
  /// cleanup: on save the controller promotes + deletes the temp itself, so
  /// we only delete on a dismiss-without-save (P4.2.1).
  bool _saved = false;

  /// Temp receipt Storage path carried in from the scanner, plus a captured
  /// [StorageService] so dispose can clean it up without touching `ref`.
  String? _tempReceiptPath;
  StorageService? _storage;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.prefill;
    _tempReceiptPath = p?.tempReceiptUrl;
    if (_tempReceiptPath != null) {
      _storage = ref.read(storageServiceProvider);
    }
    _form = TransactionFormData(
      id: e?.id,
      type: e?.type ?? 'expense',
      amount: e?.amount ?? p?.total ?? 0,
      walletId: e?.walletId,
      categoryId: e?.categoryId ?? p?.suggestedCategoryId,
      date: e?.date ?? p?.date ?? DateTime.now(),
      note: e?.note ?? p?.merchant,
      aiCategorySuggested: p != null ? true : false,
      aiConfidence: p?.confidence,
      aiSource: p != null ? 'receipt_scan' : null,
      attachmentLocalPath: p?.tempReceiptUrl,
    );
    _amountCtrl = TextEditingController(
      text: _form.amount == 0 ? '' : _form.amount.toString(),
    );
    _noteCtrl = TextEditingController(text: _form.note ?? '');
    // Re-evaluate the AI suggestion chip on input changes.
    _amountCtrl.addListener(_onInputChanged);
    _noteCtrl.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Dismissed without saving but a receipt was scanned → the temp upload
    // would otherwise be orphaned in Storage. Best-effort delete (P4.2.1).
    if (!_saved) {
      final temp = _tempReceiptPath;
      if (temp != null) _storage?.deleteTempReceipt(temp);
    }
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Inline field errors first. Without this the amount fell through
    // `tryParse(...) ?? 0` and an unparseable entry saved a silent zero.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountCtrl.text.trim());
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final ctrl = ref.read(transactionsControllerProvider.notifier);

    if (_form.type == 'transfer') {
      if (_form.walletId == null || _destWalletId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick source + destination wallets')),
        );
        return;
      }
      final wallets =
          ref.read(visibleWalletsProvider).value ?? const <Wallet>[];
      final source = wallets.where((w) => w.id == _form.walletId).firstOrNull;
      final dest = wallets.where((w) => w.id == _destWalletId).firstOrNull;
      if (source == null || dest == null) return;
      final rate = source.currency == dest.currency ? 1.0 : (_fxRate ?? 0);
      if (rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter or fetch an FX rate first')),
        );
        return;
      }
      await ctrl.createTransfer(
        sourceWalletId: _form.walletId!,
        destWalletId: _destWalletId!,
        sourceAmount: amount,
        fxRate: rate,
        date: _form.date,
        note: note,
      );
    } else {
      _form
        ..amount = amount
        ..note = note;
      if (!_form.isReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill amount, wallet, and category')),
        );
        return;
      }
      if (widget.existing == null) {
        await ctrl.create(_form);
      } else {
        await ctrl.edit(_form);
      }
    }

    if (!mounted) return;
    final result = ref.read(transactionsControllerProvider);
    if (result.hasError) return;
    // Saved: the controller now owns the temp receipt (promotes it to the
    // permanent path + deletes the temp), so suppress the dispose cleanup.
    _saved = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final wallets = ref.watch(visibleWalletsProvider).value ?? const <Wallet>[];
    final allCategories =
        ref.watch(categoriesListProvider).value ?? const <Category>[];
    final commitState = ref.watch(transactionsControllerProvider);
    final selectedWallet =
        wallets.where((w) => w.id == _form.walletId).firstOrNull;
    final selectedCategory =
        allCategories.where((c) => c.id == _form.categoryId).firstOrNull;

    ref.listen<AsyncValue<void>>(transactionsControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        final err = next.error;
        if (err is FreeTierExceeded) {
          showUpsellSheet(context, err.reason);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save transaction.')),
        );
      }
    });

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Form(
          key: _formKey,
          child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              widget.existing == null ? 'New transaction' : 'Edit transaction',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
                ButtonSegment(value: 'transfer', label: Text('Transfer')),
              ],
              selected: {_form.type},
              onSelectionChanged: (s) {
                setState(() {
                  _form.type = s.first;
                  // Income shouldn't reuse an expense category and vice versa.
                  final cat = allCategories
                      .where((c) => c.id == _form.categoryId)
                      .firstOrNull;
                  if (cat != null && cat.type != _form.type) {
                    _form.categoryId = null;
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            _AmountField(
              controller: _amountCtrl,
              currency: selectedWallet?.currency ?? '',
            ),
            const SizedBox(height: AppSpacing.lg),
            _PickerTile(
              label: _form.type == 'transfer' ? 'From wallet' : 'Wallet',
              hint: 'Choose a wallet',
              valueWidget: selectedWallet == null
                  ? null
                  : Text(
                      '${selectedWallet.name} (${selectedWallet.currency})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              icon: Icons.account_balance_wallet_outlined,
              onTap: () async {
                final picked = await _showWalletPicker(context, wallets);
                if (picked != null && mounted) {
                  setState(() {
                    _form.walletId = picked;
                    // Don't let source == dest after picking source.
                    if (_destWalletId == picked) _destWalletId = null;
                  });
                }
              },
            ),
            if (_form.type == 'transfer') ...[
              const SizedBox(height: AppSpacing.md),
              _PickerTile(
                label: 'To wallet',
                hint: 'Choose a destination wallet',
                valueWidget: () {
                  final dest =
                      wallets.where((w) => w.id == _destWalletId).firstOrNull;
                  return dest == null
                      ? null
                      : Text(
                          '${dest.name} (${dest.currency})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                }(),
                icon: Icons.south_outlined,
                onTap: () async {
                  final filtered = wallets
                      .where((w) => w.id != _form.walletId)
                      .toList();
                  final picked = await _showWalletPicker(context, filtered);
                  if (picked != null && mounted) {
                    setState(() => _destWalletId = picked);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (selectedWallet != null && _destWalletId != null)
                Builder(
                  builder: (_) {
                    final dest = wallets
                        .where((w) => w.id == _destWalletId)
                        .firstOrNull;
                    if (dest == null) return const SizedBox.shrink();
                    // Same-currency transfers don't need the FX widget;
                    // `_submit` substitutes rate = 1 in that branch.
                    if (selectedWallet.currency == dest.currency) {
                      return const SizedBox.shrink();
                    }
                    final amount =
                        double.tryParse(_amountCtrl.text.trim()) ?? 0;
                    return FxRateField(
                      from: selectedWallet.currency,
                      to: dest.currency,
                      sourceAmount: amount,
                      onRateChanged: (r) => setState(() => _fxRate = r),
                    );
                  },
                ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              _PickerTile(
                label: 'Category',
                hint: 'Choose a category',
                valueWidget: selectedCategory == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            iconForCategory(selectedCategory.iconName),
                            size: 18,
                            color: Color(
                              int.parse('FF${selectedCategory.color}', radix: 16),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              selectedCategory.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                icon: Icons.category_outlined,
                onTap: () async {
                  final picks = allCategories
                      .where((c) => c.type == _form.type)
                      .toList();
                  final picked = await _showCategoryPicker(context, picks);
                  if (picked != null && mounted) {
                    setState(() => _form.categoryId = picked);
                  }
                },
              ),
              if (selectedWallet != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AICategorySuggestionChip(
                  type: _form.type,
                  amount: double.tryParse(_amountCtrl.text.trim()) ?? 0,
                  note: _noteCtrl.text,
                  currency: selectedWallet.currency,
                  onAccept: (suggestion) {
                    setState(() {
                      _form
                        ..categoryId = suggestion.suggestedCategoryId
                        ..aiCategorySuggested = true
                        ..aiConfidence = suggestion.confidence
                        ..aiSource = 'manual_suggest';
                    });
                  },
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            _PickerTile(
              label: 'Date',
              hint: 'Pick a date',
              valueWidget: Text(_formatDate(_form.date)),
              icon: Icons.calendar_today_outlined,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _form.date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() => _form.date = picked);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 2,
              maxLength: Validators.noteMaxLength,
              validator: (v) => Validators.optionalText(v, label: 'Note'),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: commitState.isLoading ? null : _submit,
              child: commitState.isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(widget.existing == null ? 'Add transaction' : 'Save'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.currency});
  final TextEditingController controller;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Theme.of(context).textTheme.headlineMedium,
      textAlign: TextAlign.center,
      validator: Validators.amount,
      decoration: InputDecoration(
        prefixText: currency.isEmpty ? '' : '$currency  ',
        hintText: '0',
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.hint,
    required this.valueWidget,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String hint;
  final Widget? valueWidget;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.md,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        ),
        child: valueWidget ??
            Text(
              hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

Future<String?> _showWalletPicker(
  BuildContext context,
  List<Wallet> wallets,
) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) {
      if (wallets.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: Text('Add a wallet first')),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.lg),
        shrinkWrap: true,
        itemCount: wallets.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (ctx, i) {
          final w = wallets[i];
          return WalletCard(
            wallet: w,
            variant: WalletCardVariant.compact,
            onTap: () => Navigator.of(ctx).pop(w.id),
          );
        },
      );
    },
  );
}

Future<String?> _showCategoryPicker(
  BuildContext context,
  List<Category> categories,
) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useRootNavigator: true,
    builder: (_) {
      if (categories.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: Text('No categories of this type — create one first'),
          ),
        );
      }
      return ListView.separated(
        // No outer padding — let each ListTile own its full-width tap
        // target so the InkWell ripple reaches the screen edges. Vertical
        // padding only, for breathing room above the first / below the last.
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        shrinkWrap: true,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const Divider(height: 0),
        itemBuilder: (ctx, i) {
          final c = categories[i];
          final color = Color(int.parse('FF${c.color}', radix: 16));
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppBorderRadius.full,
              ),
              child: Icon(iconForCategory(c.iconName),
                  color: Colors.white, size: 20),
            ),
            title: Text(c.name),
            onTap: () => Navigator.of(ctx).pop(c.id),
          );
        },
      );
    },
  );
}
