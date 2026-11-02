// Bottom bar order read from raw settings.

import 'package:bloom/core/store/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const earlierDefault = ['home', 'search', 'library', 'settings'];

  test('a fresh install has library before search', () {
    expect(readNavOrder({}), [
      NavTab.home,
      NavTab.library,
      NavTab.search,
      NavTab.settings,
    ]);
  });

  test('the earlier default under the earlier key moves to the new one', () {
    expect(readNavOrder({'navOrder': earlierDefault}), kDefaultNavOrder);
  });

  test('an order picked by hand under the earlier key stays', () {
    expect(
      readNavOrder({
        'navOrder': ['settings', 'search', 'library', 'home'],
      }),
      [NavTab.settings, NavTab.search, NavTab.library, NavTab.home],
    );
  });

  test('the same order under the current key is a choice and stays', () {
    expect(readNavOrder({'navTabs': earlierDefault}), [
      NavTab.home,
      NavTab.search,
      NavTab.library,
      NavTab.settings,
    ]);
  });

  test('a broken list is repaired', () {
    expect(
      readNavOrder({
        'navTabs': ['library', 'nope', 'library', 3],
      }),
      [NavTab.library, NavTab.home, NavTab.search, NavTab.settings],
    );
  });
}
