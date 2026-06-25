// Regression test for the area-save crash: the area-name dialog disposed its
// TextEditingController in showDialog().whenComplete(), i.e. the instant the
// dialog popped, while the TextField was still mounted during the close
// animation -> "ChangeNotifier used after dispose" (framework.dart line 6268,
// _dependents.isEmpty). AreaNameDialog now owns the controller/focus node,
// unfocuses before closing, and disposes them in dispose().

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

Widget _host(void Function(BuildContext) onOpen) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('returns trimmed name and survives the close animation', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      _host((context) async {
        result = await showDialog<String>(
          context: context,
          builder: (_) => const AreaNameDialog(),
        );
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Maple Ridge  ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));

    // pumpAndSettle runs the dialog's exit animation, exactly when the old
    // whenComplete(dispose) used the controller after disposing it.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, 'Maple Ridge');
  });

  testWidgets('returns null on cancel without using a disposed controller', (
    tester,
  ) async {
    String? result = 'sentinel';

    await tester.pumpWidget(
      _host((context) async {
        result = await showDialog<String>(
          context: context,
          builder: (_) => const AreaNameDialog(),
        );
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Discarded');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, isNull);
  });
}
