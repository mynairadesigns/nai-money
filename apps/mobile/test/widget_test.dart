import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homa_finance/core/providers/auth_provider.dart';
import 'package:homa_finance/core/providers/onboarding_state_provider.dart';
import 'package:homa_finance/core/widgets/brand_logo.dart';
import 'package:homa_finance/main.dart';

void main() {
  testWidgets('Splash → onboarding when signed out and never onboarded',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const HomaFinanceApp(),
      ),
    );

    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Homa Finance'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.text('Track every dollar'), findsOneWidget);
  });
}
