/// The title marquee: when it rolls, which way and how fast.
///
/// I check behavior, not the picture: fitting text stays one static line with
/// an ellipsis, long text splits in two and moves left by exactly "text + gap",
/// and the cycle's duration comes from the speed with a 4 s floor. I take the
/// line's width from the widget itself (tests have their own font) and check
/// how the numbers relate.
library;

import 'package:bloom/shared/ui/marquee_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 20);

/// The gap between copies, matching the widget's default.
const double _gap = 64;

Future<void> _pump(WidgetTester tester, String text, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: MarqueeText(text, style: _style),
          ),
        ),
      ),
    ),
  );
}

/// Both copies' offsets from the wrapper's left edge.
List<double> _offsets(WidgetTester tester) {
  final wrap = tester.renderObject<RenderBox>(find.byType(ClipRect));
  return tester
      .renderObjectList<RenderBox>(find.byType(Text))
      .map((box) => box.localToGlobal(Offset.zero, ancestor: wrap).dx)
      .toList();
}

void main() {
  testWidgets("a short title doesn't split or roll", (tester) async {
    await _pump(tester, 'Трек', 400);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Трек'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
    // The animation requests no idle frames: no timer at all.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a long title moves left by "text + gap"', (tester) async {
    const text = 'ААААААААААААААААААААААААААААААААААААААААА';
    await _pump(tester, text, 200);
    await tester.pump();

    // Two copies of one line: the second covers the end of the cycle one step
    // to the right of the first, so it lands in its place and no rewind shows.
    expect(find.text(text), findsNWidgets(2));
    final start = _offsets(tester);
    expect(start.first, 0);
    final step = start[1] - start.first;

    // 55 px/s, then rounded to whole seconds.
    final seconds = (step / 55).round();
    expect(seconds, greaterThan(4));

    // The tolerance is a couple of percent of the step: the cycle starts a
    // frame after the first layout, and on a long line that frame is worth a
    // few pixels.
    await tester.pump(Duration(seconds: seconds ~/ 2));
    expect(_offsets(tester).first, closeTo(-step / 2, step * 0.02));

    // Otherwise the test ends with an endless animation running.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a barely overflowing title rolls no faster than 4 s', (
    tester,
  ) async {
    const text = 'ААААА';
    await _pump(tester, text, 60);
    await tester.pump();

    final start = _offsets(tester);
    final step = start[1] - start.first;
    // The line outgrew the wrapper but would cover the step faster than 4 s at
    // 55 px/s, so the cycle hit the floor and moves slower than calculated.
    expect(step - _gap, greaterThan(60 + 4));
    expect((step / 55).round(), lessThan(4));

    // Half a step in 2 s is exactly a four-second cycle. Without the floor it
    // would have gone noticeably further in the same 2 s.
    await tester.pump(const Duration(seconds: 2));
    expect(_offsets(tester).first, closeTo(-step / 2, step * 0.02));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
