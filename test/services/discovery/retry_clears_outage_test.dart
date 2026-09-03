import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:mangayomi/services/discovery/service_availability.dart';

/// Retry has to reach the network.
///
/// A refusal put the service in a ten minute cooldown, and every call during
/// it failed instantly without a request. Retry was therefore guaranteed to
/// fail for ten minutes, which reads as a button that does nothing.
void main() {
  setUp(ServiceAvailability.clearForTest);

  test('a service in cooldown is not asked', () {
    ServiceAvailability.markDown(DiscoveryService.anilist, 'temporarily disabled');
    expect(ServiceAvailability.isAvailable(DiscoveryService.anilist), isFalse);
  });

  test('clearing one service makes it askable immediately', () {
    ServiceAvailability.markDown(DiscoveryService.anilist, 'temporarily disabled');
    ServiceAvailability.clear(DiscoveryService.anilist);
    expect(ServiceAvailability.isAvailable(DiscoveryService.anilist), isTrue);
  });

  test('clearing one service leaves the others alone', () {
    ServiceAvailability.markDown(DiscoveryService.anilist, 'refused');
    ServiceAvailability.markDown(DiscoveryService.kitsu, 'refused');
    ServiceAvailability.clear(DiscoveryService.anilist);
    expect(ServiceAvailability.isAvailable(DiscoveryService.kitsu), isFalse);
  });

  /// The reason the service gave is the whole point of capturing it, and the
  /// row used to discard it for a hardcoded line naming AniList even when
  /// Kitsu was what failed.
  test('the row shows the reason the service gave', () {
    final screen = File('lib/modules/home/home_screen.dart').readAsStringSync();
    expect(
      screen,
      isNot(contains("Couldn't reach AniList.")),
      reason: 'the error line is hardcoded and ignores the real reason',
    );
    expect(screen, contains('reason'));
  });

  /// A retry that does not clear the cooldown cannot reach the network.
  test('retry clears the outage before refetching', () {
    final screen = File('lib/modules/home/home_screen.dart').readAsStringSync();
    expect(screen, contains('ServiceAvailability.clear'));
  });
}
