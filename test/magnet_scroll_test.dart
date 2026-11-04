import 'package:bloom/features/home/ui/magnet_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _stopAt = 500;

void main() {
  late ScrollController scroll;
  late MagnetStop stop;
  final list = find.byType(CustomScrollView);

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    stop = MagnetStop()..at = _stopAt;
    scroll = ScrollController();
    addTearDown(scroll.dispose);
    scroll.addListener(() => stop.settle(scroll.offset));
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          controller: scroll,
          physics: MagnetScrollPhysics(
            stop,
            parent: const BouncingScrollPhysics(
              parent: RangeMaintainingScrollPhysics(),
            ),
          ),
          slivers: const [
            SliverToBoxAdapter(child: SizedBox(height: _stopAt)),
            SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );
  }

  Future<void> drag(WidgetTester tester, double by) async {
    await tester.timedDrag(list, Offset(0, by), const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  Future<void> flick(WidgetTester tester, double by, double speed) async {
    await tester.fling(list, Offset(0, by), speed);
    await tester.pumpAndSettle();
  }

  testWidgets('a short drag springs back to the first screen', (tester) async {
    await pumpList(tester);
    await drag(tester, -80);
    expect(scroll.offset, 0);
    expect(stop.onFirst, isTrue);
  });

  testWidgets('a long drag snaps to the second screen', (tester) async {
    await pumpList(tester);
    await drag(tester, -250);
    expect(scroll.offset, _stopAt);
    expect(stop.onFirst, isFalse);
  });

  testWidgets('a strong flick snaps across, a weak one does not', (
    tester,
  ) async {
    await pumpList(tester);
    await flick(tester, -60, 300);
    expect(scroll.offset, 0);
    await flick(tester, -60, 2000);
    expect(scroll.offset, _stopAt);
  });

  testWidgets('a flick down the shelves stops at their top', (tester) async {
    await pumpList(tester);
    scroll.jumpTo(_stopAt + 300);
    await tester.pump();
    await flick(tester, 200, 6000);
    expect(scroll.offset, _stopAt);
  });

  testWidgets('from the top of the shelves it takes the same effort back', (
    tester,
  ) async {
    await pumpList(tester);
    scroll.jumpTo(_stopAt);
    await tester.pump();
    await drag(tester, 80);
    expect(scroll.offset, _stopAt);
    await drag(tester, 250);
    expect(scroll.offset, 0);
  });

  testWidgets('the shelves scroll freely past their top', (tester) async {
    await pumpList(tester);
    scroll.jumpTo(_stopAt);
    await tester.pump();
    await drag(tester, -80);
    expect(scroll.offset, greaterThan(_stopAt));
  });
}
