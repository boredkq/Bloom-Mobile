/// Switching the shell's tabs: a dissolve instead of a one-frame change.
///
/// I check the three things the custom branch container exists for: at rest
/// exactly one branch shows, during a transition both do (one fading out, one
/// in), and an inactive branch catches no taps.
library;

import 'package:bloom/app/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

/// A branch's opacity: `null` means it's off stage (`Offstage`).
double? _opacity(WidgetTester tester, String label) {
  final branch = find.ancestor(
    of: find.text(label, skipOffstage: false),
    matching: find.byType(Offstage),
  );
  if (tester.widget<Offstage>(branch.first).offstage) return null;
  return tester
      .widget<Opacity>(
        find
            .ancestor(
              of: find.text(label, skipOffstage: false),
              matching: find.byType(Opacity),
            )
            .first,
      )
      .opacity;
}

/// A shell with two branches and a switch button instead of the tab bar.
Future<void> _pump(WidgetTester tester) async {
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            Expanded(
              child: BranchCrossfade(
                index: index,
                children: const [Text('Главная'), Text('Библиотека')],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => index = 1 - index),
              child: const Text('таб'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('на покое видна одна вкладка, вторая убрана со сцены', (
    tester,
  ) async {
    await _pump(tester);

    expect(_opacity(tester, 'Главная'), 1);
    expect(_opacity(tester, 'Библиотека'), isNull);
  });

  testWidgets('во время перехода видны обе: одна гаснет, вторая проявляется', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('таб'));
    await tester.pump();
    // An eighth of the transition: the leaving one hasn't burned out (it fades
    // over the first quarter), the arriving one hasn't appeared (its interval
    // is 3/4).
    await tester.pump(kTabTransition ~/ 8);

    final leaving = _opacity(tester, 'Главная');
    final entering = _opacity(tester, 'Библиотека');
    expect(leaving, isNotNull);
    expect(leaving, greaterThan(0));
    expect(leaving, lessThan(1));
    expect(entering, isNotNull);
    expect(entering, greaterThan(0));
    expect(entering, lessThan(1));

    await tester.pumpAndSettle();
    expect(_opacity(tester, 'Главная'), isNull);
    expect(_opacity(tester, 'Библиотека'), 1);
  });

  testWidgets('уходящая вкладка не ловит тапы уже с первого кадра', (
    tester,
  ) async {
    var tapped = false;
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        // The language is pinned: otherwise text checks would depend on the
        // machine's locale.
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              Expanded(
                child: BranchCrossfade(
                  index: index,
                  children: [
                    GestureDetector(
                      onTap: () => tapped = true,
                      child: const SizedBox.expand(child: Text('Главная')),
                    ),
                    const Text('Библиотека'),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => index = 1),
                child: const Text('таб'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('таб'));
    await tester.pump();
    await tester.tap(find.text('Главная'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tapped, isFalse);
  });
}
