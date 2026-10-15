import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/validators.dart';
import '../data/setup_catalog.dart';
import '../providers/setup_controller.dart';

/// PRD §6.1 — post-signup wizard. Four steps:
///   1. Choose default currency
///   2. Enter monthly income (optional)
///   3. Pick 4–6 starting categories
///   4. Offer AI Budget Generator (deferred to P4 — for now we just
///      finish and route to /home, with the option stubbed)
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _totalPages = 4;

  /// Monthly income is optional, so an untouched field is valid.
  bool _incomeValid = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  bool _canAdvance(SetupFormState form) {
    switch (_page) {
      case 0:
        return form.currency.isNotEmpty;
      case 1:
        // Monthly income is optional, but if something *is* typed it has
        // to parse — otherwise it's silently dropped.
        return _incomeValid;
      case 2:
        return form.hasMinCategories;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _finish() async {
    await ref.read(setupControllerProvider.notifier).commit();
    final result = ref.read(setupControllerProvider);
    if (!mounted) return;
    if (result.hasError) return; // SnackBar surfaces error via ref.listen
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = ref.watch(setupFormProvider);
    final commitState = ref.watch(setupControllerProvider);

    ref.listen<AsyncValue<void>>(setupControllerProvider, (_, next) {
      if (next.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save setup. Try again.')),
        );
      }
    });

    final canAdvance = _canAdvance(form) && !commitState.isLoading;
    final isLast = _page == _totalPages - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StepHeader(current: _page, total: _totalPages),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _CurrencyStep(
                    selected: form.currency,
                    onPick: (code) => setState(() => form.currency = code),
                  ),
                  _MonthlyIncomeStep(
                    initialValue: form.monthlyIncome,
                    currencySymbol: _symbolFor(form.currency),
                    onChanged: (v) => form.monthlyIncome = v,
                    onValidityChanged: (ok) {
                      if (ok != _incomeValid) {
                        setState(() => _incomeValid = ok);
                      }
                    },
                  ),
                  _CategoriesStep(
                    selected: form.selectedCategoryKeys,
                    onToggle: (key) => setState(() {
                      if (form.selectedCategoryKeys.contains(key)) {
                        form.selectedCategoryKeys.remove(key);
                      } else if (!form.hasMaxCategories) {
                        form.selectedCategoryKeys.add(key);
                      }
                    }),
                  ),
                  const _AIBudgetStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  if (_page > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: commitState.isLoading
                            ? null
                            : () => _goTo(_page - 1),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: canAdvance
                          ? (isLast ? _finish : () => _goTo(_page + 1))
                          : null,
                      child: commitState.isLoading
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : Text(isLast ? 'Finish setup' : 'Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _symbolFor(String code) =>
      kCurrencyCatalog.firstWhere(
        (c) => c.code == code,
        orElse: () => kCurrencyCatalog.first,
      ).symbol;
}

// ----- step indicator -------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${current + 1} of $total',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: List.generate(total, (i) {
              final filled = i <= current;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 6,
                    decoration: BoxDecoration(
                      color: filled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: AppBorderRadius.full,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ----- step 1: currency -----------------------------------------------

class _CurrencyStep extends StatelessWidget {
  const _CurrencyStep({required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (v) {
        if (v != null) onPick(v);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          Text(
            'Choose your default currency',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Each wallet can have its own currency later — this is the one used for summaries on Home and Reports.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final c in kCurrencyCatalog)
            RadioListTile<String>(
              value: c.code,
              controlAffinity: ListTileControlAffinity.trailing,
              title: Text('${c.code} · ${c.name}'),
              subtitle: Text(c.symbol),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

// ----- step 2: monthly income -----------------------------------------

class _MonthlyIncomeStep extends StatefulWidget {
  const _MonthlyIncomeStep({
    required this.initialValue,
    required this.currencySymbol,
    required this.onChanged,
    required this.onValidityChanged,
  });
  final double? initialValue;
  final String currencySymbol;
  final ValueChanged<double?> onChanged;

  /// Lets the wizard disable "Next" while the (optional) field holds text
  /// that isn't a usable number.
  final ValueChanged<bool> onValidityChanged;

  @override
  State<_MonthlyIncomeStep> createState() => _MonthlyIncomeStepState();
}

class _MonthlyIncomeStepState extends State<_MonthlyIncomeStep> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initialValue == null ? '' : widget.initialValue.toString(),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Text('Monthly income', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Optional — used to seed budgets and personalize AI suggestions. You can change this anytime in Settings.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // The field is optional, but garbage typed into it used to be
          // swallowed by `tryParse` and stored as null with no feedback.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) =>
              Validators.optionalAmount(v, label: 'Monthly income'),
          decoration: InputDecoration(
            labelText: 'Monthly income (optional)',
            prefixText: '${widget.currencySymbol} ',
          ),
          onChanged: (raw) {
            final trimmed = raw.trim();
            final invalid = trimmed.isNotEmpty &&
                Validators.optionalAmount(trimmed) != null;
            widget.onChanged(invalid ? null : double.tryParse(trimmed));
            widget.onValidityChanged(!invalid);
          },
        ),
      ],
    );
  }
}

// ----- step 3: categories ---------------------------------------------

class _CategoriesStep extends StatelessWidget {
  const _CategoriesStep({required this.selected, required this.onToggle});
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atMax = selected.length >= kMaxCategoryPicks;
    final atMin = selected.length >= kMinCategoryPicks;

    final expenses =
        kStarterCategories.where((c) => c.type == 'expense').toList();
    final incomes =
        kStarterCategories.where((c) => c.type == 'income').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        Text('Pick your categories', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Choose $kMinCategoryPicks–$kMaxCategoryPicks to start. You can add more later in Settings → Categories.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: atMin
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppBorderRadius.full,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                atMin ? Icons.check_circle : Icons.info_outline,
                size: 16,
                color: atMin
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${selected.length} of $kMaxCategoryPicks selected',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: atMin
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _CategorySectionHeader(label: 'Expenses'),
        const SizedBox(height: AppSpacing.sm),
        _CategoryGrid(
          items: expenses,
          selected: selected,
          atMax: atMax,
          onToggle: onToggle,
        ),
        const SizedBox(height: AppSpacing.lg),
        _CategorySectionHeader(label: 'Income'),
        const SizedBox(height: AppSpacing.sm),
        _CategoryGrid(
          items: incomes,
          selected: selected,
          atMax: atMax,
          onToggle: onToggle,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  const _CategorySectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.items,
    required this.selected,
    required this.atMax,
    required this.onToggle,
  });

  final List<StarterCategory> items;
  final Set<String> selected;
  final bool atMax;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final c in items)
              SizedBox(
                width: cardWidth,
                child: _CategoryCard(
                  category: c,
                  selected: selected.contains(c.key),
                  disabled: atMax && !selected.contains(c.key),
                  onTap: () => onToggle(c.key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final StarterCategory category;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryColor = Color(int.parse('FF${category.colorHex}', radix: 16));
    final icon = setupIconLookup[category.iconName] ?? Icons.label_outline;

    final Color bg;
    final Color borderColor;
    final double borderWidth;
    if (selected) {
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
      borderColor = theme.colorScheme.primary;
      borderWidth = 1.5;
    } else {
      bg = theme.colorScheme.surface;
      borderColor = theme.colorScheme.outlineVariant;
      borderWidth = 1;
    }

    return Opacity(
      opacity: disabled ? 0.4 : 1.0,
      child: Material(
        color: bg,
        borderRadius: AppBorderRadius.lg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: borderWidth),
              borderRadius: AppBorderRadius.lg,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: categoryColor,
                        borderRadius: AppBorderRadius.full,
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      category.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (selected)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----- step 4: AI budget offer ----------------------------------------

class _AIBudgetStep extends StatelessWidget {
  const _AIBudgetStep();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You\'re all set', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap Finish to start tracking. Once you have a few transactions, Homa Coach can propose a personalized monthly budget for you.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: AppBorderRadius.lg,
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'AI Budget Generator unlocks in the AI Coach tab after you log your first transactions.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
