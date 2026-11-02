/// Welcome and first run flags test.
library;

import 'package:bloom/app/welcome.dart';
import 'package:bloom/core/db/db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isFirstRun returns true on clean database', () {
    final db = BloomDb.memory();
    expect(isFirstRun(db), isTrue);
  });

  test('markWelcomeSeen marks welcome as completed', () {
    final db = BloomDb.memory();
    expect(isFirstRun(db), isTrue);

    markWelcomeSeen(db);
    expect(isFirstRun(db), isFalse);
    expect(takeFirstRun(db), isFalse);
  });
}
