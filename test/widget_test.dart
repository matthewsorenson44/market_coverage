// Lightweight widget smoke tests for leaf widgets that don't depend on
// Supabase or location services. Full-app/integration tests belong in
// integration_test/ once a mockable data layer exists.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

void main() {
  testWidgets('leadScoreBadge renders the score value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: leadScoreBadge(85))),
    );

    expect(find.text('85'), findsOneWidget);
  });

  testWidgets('leadStageBadge renders the stage label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: leadStageBadge('Interested'))),
    );

    expect(find.text('Interested'), findsOneWidget);
  });

  testWidgets('LoginScreen toggles between sign in and sign up', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Need an account? Sign up'), findsOneWidget);

    await tester.tap(find.text('Need an account? Sign up'));
    await tester.pump();

    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Have an account? Sign in'), findsOneWidget);
  });
}
