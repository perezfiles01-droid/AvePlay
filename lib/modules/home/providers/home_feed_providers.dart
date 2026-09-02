import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/services/anilist_discovery.dart';

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

/// What is trending right now.
final trendingAnimeProvider = FutureProvider<List<DiscoveryMedia>>(
  (ref) => fetchTrendingAnime(),
);

/// Anime that had an episode air in the last week, newest first.
final recentlyAiredAnimeProvider = FutureProvider<List<DiscoveryMedia>>(
  (ref) => fetchRecentlyAiredAnime(),
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
  return fetchSeasonAnime(season: season, year: year);
});
