import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/onboarding_state_provider.dart';
import '../../../core/theme/shapes.dart';
import '../../../core/theme/spacing.dart';

/// PRD §6.1: 3-page onboarding carousel.
/// Pages match the PRD copy; illustrations land with the design pass.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Track every dollar',
      body: 'See your wallets, transactions, and balances in one place.',
    ),
    _OnboardingPage(
      icon: Icons.auto_awesome_outlined,
      title: 'AI does the heavy lifting',
      body: 'Scan receipts and chat with Homa Coach about your money.',
    ),
    _OnboardingPage(
      icon: Icons.flag_outlined,
      title: 'Reach your goals faster',
      body: 'Set goals and let Homa Finance build a personalized savings plan.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page == _pages.length - 1) {
      await ref.read(hasSeenOnboardingProvider.notifier).markSeen();
      if (!mounted) return;
      context.go('/auth/sign-in');
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextButton(
                  onPressed: () async {
                    await ref
                        .read(hasSeenOnboardingProvider.notifier)
                        .markSeen();
                    if (!context.mounted) return;
                    context.go('/auth/sign-in');
                  },
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i].build(context),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final selected = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: AppBorderRadius.full,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Get started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppBorderRadius.xl,
            ),
            child: Icon(
              icon,
              size: 64,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
