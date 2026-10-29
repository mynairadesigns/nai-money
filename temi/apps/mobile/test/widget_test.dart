import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:temi_finance/core/providers/auth_provider.dart';
import 'package:temi_finance/core/providers/onboarding_state_provider.dart';
import 'package:temi_finance/core/widgets/brand_logo.dart';
import 'package:temi_finance/main.dart';

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
        child: const TemiApp(),
      ),
    );

    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Temi Finance'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();

    expect(find.text('Track every dollar'), findsOneWidget);
  });
}
