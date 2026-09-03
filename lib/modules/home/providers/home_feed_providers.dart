import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/services/anilist_discovery.dart';
import 'package:mangayomi/services/discovery/kitsu_discovery.dart';

/// The AniList-backed rows on the home screen.
///
/// Written by hand rather than generated: the rest of the app's providers come
/// from riverpod_generator, but these need no family plumbing and adding them
/// to the generated set would mean regenerating sources for three futures.
///
/// None of them are autoDispose. Leaving the home and coming back is the
/// common move, and AniList rate-limits at 90 requests a minute, so an answer
/// is kept for the life of the app rather than refetched on every visit; pull
/// to refresh invalidates them explicitly.

/// Asks [primary], and falls back to [fallback] when it will not answer.
///
/// Every row used to call AniList and nothing else, so an AniList outage left
/// the whole home screen showing three error lines and no content.
///
/// It falls back on ANY failure of the primary, not only a recorded refusal: a
/// malformed body and a GraphQL error throw a plain Exception, and those
/// emptied the row exactly as thoroughly as a 403 did.
///
/// An empty answer is not a failure. A service that genuinely has nothing for
/// this row is telling the truth, and covering that with another service's data
/// would show last season under a heading naming this one.
///
/// When the fallback fails too, the primary's error is what propagates: it is
/// the service the row is nominally showing, and its reason is the more useful
/// one to put on screen.
Future<List<DiscoveryMedia>> withDiscoveryFallback(
  Future<List<DiscoveryMedia>> Function() primary,
  Future<List<DiscoveryMedia>> Function() fallback,
) async {
  try {
    return await primary();
  } catch (primaryError) {
    try {
      return await fallback();
    } catch (_) {
      throw primaryError;
    }
  }
}

/// What is trending right now.
final trendingAnimeProvider = FutureProvider<List<DiscoveryMedia>>(
  (ref) => withDiscoveryFallback(fetchTrendingAnime, kitsuTrendingAnime),
);

/// Anime that had an episode air in the last week, newest first.
///
/// Kitsu has no airing schedule, so its stand-in is what is currently running.
/// The row labels whichever service answered.
final recentlyAiredAnimeProvider = FutureProvider<List<DiscoveryMedia>>(
  (ref) => withDiscoveryFallback(
    fetchRecentlyAiredAnime,
    kitsuCurrentlyAiringAnime,
  ),
);

/// The season the seasonal row is showing, as (MediaSeason name, year).
///
/// Held in memory only, so it starts at the season we are actually in on every
/// launch. Persisting it belongs on the Settings collection, which is Isar
/// generated code: adding a field there means regenerating the schema, which
/// is a separate change.
class SelectedSeason extends Notifier<(String, int)> {
  @override
  (String, int) build() => currentSeason();

  void set((String, int) value) => state = value;

  /// Back to the season we are actually in.
  void reset() => state = currentSeason();
}

final selectedSeasonProvider = NotifierProvider<SelectedSeason, (String, int)>(
  SelectedSeason.new,
);

/// The most popular anime of the selected season.
final seasonAnimeProvider = FutureProvider<List<DiscoveryMedia>>((ref) {
  final (season, year) = ref.watch(selectedSeasonProvider);
  return withDiscoveryFallback(
    () => fetchSeasonAnime(season: season, year: year),
    () => kitsuSeasonAnime(season: season, year: year),
  );
});
