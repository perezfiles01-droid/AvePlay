import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:mangayomi/modules/home/providers/home_feed_providers.dart';
import 'package:mangayomi/services/anilist_discovery.dart';
import 'package:mangayomi/services/discovery/service_availability.dart';

/// The home rows must survive AniList refusing.
///
/// Before this, all three rows called AniList directly and rendered an error
/// when it would not answer, so an AniList outage emptied the home screen.
DiscoveryMedia _media(int id, DiscoveryService source) =>
    DiscoveryMedia(id: id, source: source, romaji: 'title $id', type: 'ANIME');

void main() {
  group('withDiscoveryFallback', () {
    test('uses the primary service when it answers', () async {
      final rows = await withDiscoveryFallback(
        () async => [_media(1, DiscoveryService.anilist)],
        () async => [_media(2, DiscoveryService.kitsu)],
      );
      expect(rows.single.id, 1);
    });

    test('falls back when the primary refuses', () async {
      final rows = await withDiscoveryFallback(
        () async => throw DiscoveryUnavailable(
          DiscoveryService.anilist,
          'temporarily disabled',
        ),
        () async => [_media(2, DiscoveryService.kitsu)],
      );
      expect(rows.single.source, DiscoveryService.kitsu);
    });

    /// Not every AniList failure is a DiscoveryUnavailable: a malformed body
    /// or a GraphQL error throws a plain Exception, and those emptied the row
    /// just as thoroughly.
    test('falls back on any primary failure, not only a refusal', () async {
      final rows = await withDiscoveryFallback(
        () async => throw Exception('AniList returned something that is not JSON'),
        () async => [_media(3, DiscoveryService.kitsu)],
      );
      expect(rows.single.id, 3);
    });

    /// An empty answer is a real answer and must not be masked by a second
    /// service's data, or a row could show last season while claiming to show
    /// this one.
    test('an empty primary answer is kept, not overridden', () async {
      final rows = await withDiscoveryFallback(
        () async => const <DiscoveryMedia>[],
        () async => [_media(4, DiscoveryService.kitsu)],
      );
      expect(rows, isEmpty);
    });

    test('the primary error survives when the fallback fails too', () async {
      expect(
        () => withDiscoveryFallback(
          () async => throw DiscoveryUnavailable(
            DiscoveryService.anilist,
            'temporarily disabled',
          ),
          () async => throw DiscoveryUnavailable(
            DiscoveryService.kitsu,
            'answered HTTP 503',
          ),
        ),
        throwsA(isA<DiscoveryUnavailable>()),
      );
    });
  });

  /// Enumerated from the file rather than listed here, so a row added later is
  /// held to this too — a new row written by copying an old one is exactly
  /// where a direct AniList call comes back.
  test('every home feed provider goes through the fallback', () {
    final source = File(
      'lib/modules/home/providers/home_feed_providers.dart',
    ).readAsStringSync();

    final providers = RegExp(
      r'final (\w+Provider) = FutureProvider<List<DiscoveryMedia>>',
    ).allMatches(source).map((m) => m.group(1)!).toList();

    expect(providers, isNotEmpty, reason: 'no feed providers found to check');

    for (final name in providers) {
      // From this declaration to the next top-level one. Slicing to the first
      // `);` instead looked right and was not: a provider that reads another
      // provider first closes that call before it reaches its own body, so the
      // seasonal row - which does exactly that - read as having no fallback
      // while its code was correct.
      final start = source.indexOf('final $name');
      final next = source.indexOf('\nfinal ', start + 1);
      final body = next == -1 ? source.substring(start) : source.substring(start, next);

      expect(
        body,
        contains('withDiscoveryFallback'),
        reason: '$name calls a discovery service directly, with no fallback',
      );
    }
  });
}
