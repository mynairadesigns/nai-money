import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../data/remote/fx_service.dart';

/// Surfaces the source→destination FX rate when a transfer crosses
/// currencies. Auto-fetches via [FxService] on mount and whenever the
/// currency pair changes; lets the user override manually if the live
/// fetch fails (PRD §6.2 "live or manual").
///
/// Reports the latest rate to [onRateChanged] — `null` while loading
/// or when the user clears the manual field.
class FxRateField extends ConsumerStatefulWidget {
  const FxRateField({
    required this.from,
    required this.to,
    required this.sourceAmount,
    required this.onRateChanged,
    super.key,
  });

  final String from;
  final String to;
  final double sourceAmount;
  final ValueChanged<double?> onRateChanged;

  @override
  ConsumerState<FxRateField> createState() => _FxRateFieldState();
}

class _FxRateFieldState extends ConsumerState<FxRateField> {
  final _manualCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  double? _rate;
  DateTime? _asOf;
  String? _lastPair;

  @override
  void initState() {
    super.initState();
    // Defer to post-frame so the parent finishes building before any
    // `onRateChanged` callback can trigger its setState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFetch();
    });
  }

  @override
  void didUpdateWidget(covariant FxRateField old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetch();
      });
    }
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeFetch() async {
    final pair = '${widget.from}-${widget.to}';
    if (pair == _lastPair) return;
    _lastPair = pair;
    setState(() {
      _loading = true;
      _error = null;
      _rate = null;
      _asOf = null;
      _manualCtrl.clear();
    });
    widget.onRateChanged(null);

    try {
      final fx = await ref.read(fxServiceProvider).fetch(
            from: widget.from,
            to: widget.to,
          );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rate = fx.rate;
        _asOf = fx.asOf;
        _manualCtrl.text = fx.rate.toStringAsFixed(6);
      });
      widget.onRateChanged(fx.rate);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not fetch live rate — enter it manually.';
      });
    }
  }

  void _onManualChanged(String raw) {
    final parsed = double.tryParse(raw.trim());
    setState(() => _rate = parsed);
    widget.onRateChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destAmount =
        _rate == null ? null : widget.sourceAmount * _rate!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: AppBorderRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.currency_exchange,
                color: theme.colorScheme.onSecondaryContainer,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${widget.from} → ${widget.to}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Refresh rate',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _lastPair = null; // force re-fetch
                    _maybeFetch();
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _manualCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Rendered only for cross-currency transfers, and the parent
            // sheet is a Form — so a blank/zero rate now blocks the save
            // inline instead of via a post-submit SnackBar.
            validator: (v) => Validators.amount(v, label: 'Rate'),
            decoration: InputDecoration(
              labelText: 'Rate (1 ${widget.from} = ? ${widget.to})',
              isDense: true,
              border: const OutlineInputBorder(),
              helperText: _error ??
                  (_asOf == null
                      ? null
                      : 'Live, as of ${_formatAsOf(_asOf!)}'),
              helperStyle: _error != null
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            onChanged: _onManualChanged,
          ),
          if (destAmount != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${widget.sourceAmount.toStringAsFixed(2)} ${widget.from}  ≈  '
              '${destAmount.toStringAsFixed(2)} ${widget.to}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatAsOf(DateTime d) {
    final local = d.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}
