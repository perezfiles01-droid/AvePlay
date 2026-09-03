import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app opens straight into itself.
///
/// The first-run screen stood between the reader and the app on every fresh
/// install, and dismissing it was the only way through.
void main() {
  test('nothing gates startup on a first-run screen', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('OnboardingScreen')));
    expect(main.toLowerCase(), isNot(contains('onboardingcompletedstate')));
  });

  test('the first-run screen is gone from the tree', () {
    expect(Directory('lib/modules/onboarding').existsSync(), isFalse);
  });

  /// Settings must not offer to replay a screen that no longer exists.
  test('no setting offers to show it again', () {
    final general = File(
      'lib/modules/more/settings/general/general_screen.dart',
    ).readAsStringSync();
    expect(general.toLowerCase(), isNot(contains('onboarding')));
  });
}
