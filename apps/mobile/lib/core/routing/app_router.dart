import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_coach/presentation/ai_coach_screen.dart';
import '../../features/ai_coach/presentation/coach_chat_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/billing/presentation/paywall_screen.dart';
import '../../features/billing/presentation/subscription_screen.dart';
import '../../features/budgets/presentation/add_budget_screen.dart';
import '../../features/budgets/presentation/budget_detail_screen.dart';
import '../../features/budgets/presentation/budgets_list_screen.dart';
import '../../features/budget_generator/presentation/budget_generator_screen.dart';
import '../../features/categories/presentation/category_manage_screen.dart';
import '../../data/local/app_database.dart';
import '../../features/debts/presentation/add_debt_screen.dart';
import '../../features/debts/presentation/debt_detail_screen.dart';
import '../../features/debts/presentation/debts_list_screen.dart';
import '../../features/goals/presentation/add_goal_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/goals/presentation/goals_list_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/insights/presentation/health_score_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/recap/presentation/recap_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/recurring/presentation/add_recurring_screen.dart';
import '../../features/recurring/presentation/recurring_detail_screen.dart';
import '../../features/recurring/presentation/recurring_list_screen.dart';
import '../../features/reports/presentation/category_report_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/security/presentation/security_settings_screen.dart';
import '../../features/settings/presentation/about_screen.dart';
import '../../features/settings/presentation/backup_screen.dart';
import '../../features/settings/presentation/profile_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/subscriptions/presentation/subscriptions_screen.dart';
import '../../features/setup/presentation/setup_screen.dart';
import '../../features/shared/main_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/transactions/presentation/add_transaction_sheet.dart';
import '../../features/transactions/presentation/receipt_scanner_screen.dart';
import '../../features/transactions/presentation/transaction_detail_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';
import '../../features/wallets/presentation/add_wallet_screen.dart';
import '../../features/wallets/presentation/wallet_detail_screen.dart';
import '../../features/wallets/presentation/wallets_manage_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/setup_state_provider.dart';

/// Routes that require the user to be signed in.
const _authenticatedPathPrefixes = <String>[
  '/home',
  '/transactions',
  '/recap',
  '/reports',
  '/ai-coach',
  '/transaction',
  '/wallet',
  '/budget',
  '/budgets',
  '/recurring',
  '/debt',
  '/debts',
  '/goal',
  '/goals',
  '/category',
  '/ai',
  '/settings',
  '/paywall',
  '/setup',
];

/// Routes that should bounce to /home if the user is already signed in.
const _unauthenticatedPathPrefixes = <String>[
  '/onboarding',
  '/auth',
];

bool _matchesAny(String location, List<String> prefixes) {
  for (final p in prefixes) {
    if (location == p || location.startsWith('$p/')) return true;
  }
  return false;
}

/// Application route table. Mirrors PRD §4.1. Every route now resolves to a
/// real screen; the former `PlaceholderScreen` stand-ins have all shipped.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      // While auth state is still resolving, leave the user on the splash.
      if (auth.isLoading) {
        return state.matchedLocation == '/' ? null : '/';
      }
      final user = auth.value;
      final loc = state.matchedLocation;

      if (user == null && _matchesAny(loc, _authenticatedPathPrefixes)) {
        return '/auth/sign-in';
      }
      // Signed-in users on /auth/* or /onboarding go to the right
      // destination based on setup completion — never via /home as a hop.
      if (user != null) {
        final status = ref.read(setupStatusProvider);
        // Setup status for this uid isn't settled yet (first sign-in on
        // this device — `syncLifecycleProvider` is reading Firestore).
        // Park on the splash: guessing "incomplete" here is what used to
        // throw returning users back into the onboarding wizard.
        if (status == SetupStatus.unknown) {
          return loc == '/' ? null : '/';
        }
        final setupDone = status == SetupStatus.complete;
        final onSetup = loc == '/setup' || loc.startsWith('/setup/');

        if (_matchesAny(loc, _unauthenticatedPathPrefixes)) {
          return setupDone ? '/home' : '/setup';
        }
        if (!setupDone &&
            _matchesAny(loc, _authenticatedPathPrefixes) &&
            !onSetup) {
          return '/setup';
        }
        if (setupDone && onSetup) {
          return '/home';
        }
      }
      return null;
    },
    refreshListenable: _AuthRefreshNotifier(ref),
    routes: [
    GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),

    GoRoute(path: '/auth/sign-in', builder: (_, _) => const SignInScreen()),
    GoRoute(path: '/auth/sign-up', builder: (_, _) => const SignUpScreen()),
    GoRoute(
      path: '/auth/forgot-password',
      builder: (_, _) => const ForgotPasswordScreen(),
    ),

    GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),

    // ---- Main shell with bottom tabs (PRD §4.2) -------------------------
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              builder: (_, _) => const TransactionsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ai-coach',
              builder: (_, _) => const AICoachScreen(),
            ),
          ],
        ),
      ],
    ),

    // ---- Transactions ---------------------------------------------------
    // /transaction/add is a thin route wrapper that opens the modal sheet
    // on mount and pops itself when the modal closes. The primary entry
    // point is the central FAB on MainShell.
    GoRoute(
      path: '/transaction/add',
      builder: (_, _) => const _AddTransactionRouteWrapper(),
    ),
    GoRoute(
      path: '/transaction/scan',
      builder: (_, _) => const ReceiptScannerScreen(),
    ),
    GoRoute(
      path: '/transaction/:id',
      builder: (_, state) =>
          TransactionDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Wallets --------------------------------------------------------
    GoRoute(path: '/wallet/add', builder: (_, _) => const AddWalletScreen()),
    // Must stay ahead of '/wallet/:id' — GoRouter matches in declaration
    // order, so a later literal would be swallowed by the param route.
    GoRoute(
      path: '/wallet/manage',
      builder: (_, _) => const WalletsManageScreen(),
    ),
    GoRoute(
      path: '/wallet/:id',
      builder: (_, state) =>
          WalletDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Budgets --------------------------------------------------------
    GoRoute(path: '/budgets', builder: (_, _) => const BudgetsListScreen()),
    GoRoute(
      // Standalone AI budget generator (post-setup). NOT under `/setup/*` —
      // that prefix is the onboarding flow, which the redirect bounces
      // completed-setup users out of (→ would push /home, duplicating the
      // shell page key and crashing the Navigator).
      path: '/budgets/generate',
      builder: (_, _) => const BudgetGeneratorScreen(),
    ),
    GoRoute(
      path: '/budget/add',
      builder: (_, state) =>
          AddBudgetScreen(existing: state.extra as Budget?),
    ),
    GoRoute(
      path: '/budget/:id',
      builder: (_, state) =>
          BudgetDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Recurring ------------------------------------------------------
    GoRoute(
      path: '/recurring',
      builder: (_, _) => const RecurringListScreen(),
    ),
    GoRoute(
      path: '/recurring/add',
      builder: (_, state) =>
          AddRecurringScreen(existing: state.extra as RecurringRule?),
    ),
    GoRoute(
      path: '/recurring/:id',
      builder: (_, state) =>
          RecurringDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Debts ----------------------------------------------------------
    GoRoute(path: '/debts', builder: (_, _) => const DebtsListScreen()),
    GoRoute(
      path: '/debt/add',
      builder: (_, state) => AddDebtScreen(existing: state.extra as Debt?),
    ),
    GoRoute(
      path: '/debt/:id',
      builder: (_, state) => DebtDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Goals ----------------------------------------------------------
    GoRoute(path: '/goals', builder: (_, _) => const GoalsListScreen()),
    GoRoute(
      path: '/goal/add',
      builder: (_, state) => AddGoalScreen(existing: state.extra as Goal?),
    ),
    GoRoute(
      path: '/goal/:id',
      builder: (_, state) => GoalDetailScreen(id: state.pathParameters['id']!),
    ),

    // ---- Categories -----------------------------------------------------
    GoRoute(
      path: '/category/manage',
      builder: (_, _) => const CategoryManageScreen(),
    ),

    // ---- Reports drill-down ---------------------------------------------
    GoRoute(
      path: '/reports/category/:catId',
      builder: (_, state) =>
          CategoryReportScreen(categoryId: state.pathParameters['catId']!),
    ),

    // ---- AI deep routes -------------------------------------------------
    GoRoute(
      path: '/ai/chat',
      builder: (_, _) => const CoachChatScreen(),
    ),
    GoRoute(
      path: '/ai/insights',
      builder: (_, _) => const AIInsightsScreen(),
    ),
    GoRoute(
      path: '/ai/health-score',
      builder: (_, _) => const HealthScoreScreen(),
    ),

    // ---- Settings -------------------------------------------------------
    GoRoute(path: '/recap', builder: (_, _) => const RecapScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(
      path: '/settings/subscriptions',
      builder: (_, _) => const SubscriptionsScreen(),
    ),
    GoRoute(
      path: '/settings/profile',
      builder: (_, _) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/settings/security',
      builder: (_, _) => const SecuritySettingsScreen(),
    ),
    GoRoute(
      path: '/settings/notifications',
      builder: (_, _) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/backup',
      builder: (_, _) => const BackupScreen(),
    ),
    GoRoute(
      path: '/settings/about',
      builder: (_, _) => const AboutScreen(),
    ),
    GoRoute(
      path: '/settings/subscription',
      builder: (_, _) => const SubscriptionScreen(),
    ),

    // ---- Paywall --------------------------------------------------------
    GoRoute(
      path: '/paywall',
      builder: (_, _) => const PaywallScreen(),
    ),
    ],
  );
});

/// Tiny route-as-screen that schedules the Add Transaction sheet on
/// next frame, then pops itself when the sheet closes. Lets `/transaction/add`
/// behave as a deep-link to the modal without duplicating the sheet UI.
class _AddTransactionRouteWrapper extends StatefulWidget {
  const _AddTransactionRouteWrapper();
  @override
  State<_AddTransactionRouteWrapper> createState() =>
      _AddTransactionRouteWrapperState();
}

class _AddTransactionRouteWrapperState
    extends State<_AddTransactionRouteWrapper> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_opened || !mounted) return;
      _opened = true;
      await showAddTransactionSheet(context);
      if (!mounted) return;
      context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox.shrink());
  }
}

/// Adapter so [GoRouter.refreshListenable] re-evaluates `redirect`
/// whenever auth state OR the setup-completion flag changes.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _authSub = ref.listen<AsyncValue<dynamic>>(
      authStateProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
    _setupSub = ref.listen<SetupStatus>(
      setupStatusProvider,
      (_, _) => notifyListeners(),
      fireImmediately: false,
    );
    ref.onDispose(() {
      _authSub.close();
      _setupSub.close();
    });
  }
  late final ProviderSubscription<AsyncValue<dynamic>> _authSub;
  late final ProviderSubscription<SetupStatus> _setupSub;
}
