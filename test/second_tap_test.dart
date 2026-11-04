import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/shared/ui/atoms.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester) async {
    final fired = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SecondTap(
          onConfirm: () => fired.add(1),
          builder: (armed, tap) => GestureDetector(
            onTap: tap,
            child: Text(armed ? 'armed' : 'idle'),
          ),
        ),
      ),
    );
    return fired;
  }

  testWidgets('the first tap arms, the second fires and disarms', (
    tester,
  ) async {
    final fired = await pump(tester);

    await tester.tap(find.text('idle'));
    await tester.pump();
    expect(find.text('armed'), findsOneWidget);
    expect(fired, isEmpty);

    await tester.tap(find.text('armed'));
    await tester.pump();
    expect(find.text('idle'), findsOneWidget);
    expect(fired, hasLength(1));
  });

  testWidgets('left alone it cools off and asks again', (tester) async {
    final fired = await pump(tester);

    await tester.tap(find.text('idle'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('idle'), findsOneWidget);

    await tester.tap(find.text('idle'));
    await tester.pump();
    expect(find.text('armed'), findsOneWidget);
    expect(fired, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
}
