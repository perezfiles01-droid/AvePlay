import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/history/providers/isar_providers.dart';
import 'package:mangayomi/modules/home/providers/home_feed_providers.dart';
import 'package:mangayomi/modules/home/widgets/season_filter_drawer.dart';
import 'package:mangayomi/modules/library/providers/isar_providers.dart';
import 'package:mangayomi/modules/library/widgets/library_entry_utils.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/repositories/history_repository.dart';
import 'package:mangayomi/services/anilist_discovery.dart';
import 'package:mangayomi/services/discovery/service_availability.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/cached_network.dart';
import 'package:mangayomi/utils/extensions/chapter_extensions.dart';

/// Poster width for the rails. Phones get a fixed size rather than the
/// library's grid-size setting: a rail is not a grid, and the whole point of
/// the row is that the next poster peeks in from the edge.
const double _cardWidth = 118;

/// Posters are 2:3, plus room for the title line underneath.
const double _cardHeight = _cardWidth * 1.5 + 38;

/// Where "Resume" goes: the episode in history if there is one, else the first.
///
/// Mirrors the TV home's rule so both surfaces resume at the same place.
Chapter? _resumeChapter(Manga manga) {
  final history = historyRepository.getAllByMangaId(manga.id!);
  if (history.isNotEmpty) {
    history.first.chapter.loadSync();
    final ch = history.first.chapter.value;
    if (ch != null) return ch;
  }
  return manga.chapters.isNotEmpty ? manga.chapters.first : null;
}

/// Title case for an AniList MediaSeason name, for the seasonal row's heading.
String _seasonLabel(String season, int year) =>
    '${season[0]}${season.substring(1).toLowerCase()} $year';

/// The phone home.
///
/// Two kinds of row sit here and they fail independently, which is the whole
/// shape of this screen. The local rows (Continue Watching, Recently Added)
/// come from the library and work offline; the AniList rows (Trending, New
/// This Week, Top This Season) come from the network and work on a brand new
/// install with nothing in the library at all.
///
/// So the page is never gated on the library being non-empty: an empty library
/// hides its own rows and the AniList rows carry the screen. Gating the whole
/// body on it is what made a fresh install show nothing but "Empty library".
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Forgets every recorded outage, so a deliberate refetch reaches the
  /// network.
  ///
  /// A refusal puts a service in a ten minute cooldown and every call during it
  /// fails locally without a request. That is right for a screen rebuilding
  /// itself and wrong for a person asking again: without this, both Retry and
  /// pull-to-refresh were guaranteed to fail for the rest of the cooldown.
  void _askAgain() {
    for (final service in DiscoveryService.values) {
      ServiceAvailability.clear(service);
    }
  }

  /// One row, asked again from scratch.
  void _retry(FutureProvider<List<DiscoveryMedia>> provider) {
    _askAgain();
    ref.invalidate(provider);
  }

  Future<void> _refresh() async {
    _askAgain();
    ref.invalidate(trendingAnimeProvider);
    ref.invalidate(recentlyAiredAnimeProvider);
    ref.invalidate(seasonAnimeProvider);
    // Awaiting the three keeps the spinner up until they land. A failure is
    // already drawn by the row that failed, so it must not throw out of here.
    for (final future in [
      ref.read(trendingAnimeProvider.future),
      ref.read(recentlyAiredAnimeProvider.future),
      ref.read(seasonAnimeProvider.future),
    ]) {
      try {
        await future;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        ref
            .watch(
              getAllMangaStreamProvider(
                categoryId: null,
                itemType: ItemType.anime,
              ),
            )
            .asData
            ?.value ??
        const <Manga>[];

    // Continue Watching = anime you have actually played, most recent first.
    final historyIds =
        (ref
                    .watch(getAllHistoryStreamProvider(itemType: ItemType.anime))
                    .asData
                    ?.value ??
                const <History>[])
            .map((h) => h.mangaId)
            .whereType<int>()
            .toSet();

    final continueList =
        entries.where((m) => historyIds.contains(m.id)).toList()
          ..sort((a, b) => (b.lastRead ?? 0).compareTo(a.lastRead ?? 0));

    final recent = [...entries]
      ..sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));

    // The hero is the thing you were last watching, and only that. Nothing
    // watched yet means no hero at all: a banner for something you have never
    // opened has nothing to continue.
    final hero = continueList.firstOrNull;

    final trending = ref.watch(trendingAnimeProvider);
    final (season, year) = ref.watch(selectedSeasonProvider);

    // The bar floats over the hero, whose backdrop is dark in both themes, so
    // its icons are forced light while a hero is behind them. Left to the
    // theme they would be near-black on a light theme and disappear into the
    // artwork. With no hero there is nothing behind them and the theme's own
    // colour is right.
    final hasHero = hero != null;

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: hasHero ? Colors.white : null,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Season filter',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: context.l10n.search,
            onPressed: () =>
                context.push('/globalSearch', extra: (null, ItemType.anime)),
          ),
        ],
      ),
      drawer: const SeasonFilterDrawer(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            if (hero != null)
              SliverToBoxAdapter(child: _ContinueHero(manga: hero))
            else
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            if (continueList.isNotEmpty)
              SliverToBoxAdapter(
                child: _LocalRail(
                  title: 'Continue Watching',
                  items: continueList,
                ),
              ),
            SliverToBoxAdapter(
              child: _RemoteRail(
                title: 'Top Trending',
                value: trending,
                onRetry: () => _retry(trendingAnimeProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _RemoteRail(
                title: 'New This Week',
                value: ref.watch(recentlyAiredAnimeProvider),
                onRetry: () => _retry(recentlyAiredAnimeProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _RemoteRail(
                title: 'Top ${_seasonLabel(season, year)}',
                value: ref.watch(seasonAnimeProvider),
                onRetry: () => _retry(seasonAnimeProvider),
              ),
            ),
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: _LocalRail(
                  title: 'Recently Added',
                  items: recent.take(30).toList(),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// Shared chrome for a row: the heading, then whatever the row puts under it.
class _RailFrame extends StatelessWidget {
  const _RailFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        child,
      ],
    );
  }
}

/// One titled horizontal row of library entries.
class _LocalRail extends StatelessWidget {
  const _LocalRail({required this.title, required this.items});

  final String title;
  final List<Manga> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _RailFrame(
      title: title,
      child: SizedBox(
        height: _cardHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => _LocalCard(manga: items[i]),
        ),
      ),
    );
  }
}

/// One titled horizontal row of AniList entries, with its own loading and
/// error states so a failed fetch costs its row and not the page.
class _RemoteRail extends StatelessWidget {
  const _RemoteRail({
    required this.title,
    required this.value,
    required this.onRetry,
  });

  final String title;
  final AsyncValue<List<DiscoveryMedia>> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _RailFrame(
      title: title,
      child: SizedBox(
        height: _cardHeight,
        child: value.when(
          loading: () => ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, _) => const _CardPlaceholder(),
          ),
          error: (error, _) => _RailError(error: error, onRetry: onRetry),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Nothing to show right now.',
                      style: TextStyle(color: context.secondaryColor),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _RemoteCard(media: items[i]),
                ),
        ),
      ),
    );
  }
}

/// A row that could not be fetched. Says so and offers another go, rather
/// than leaving a gap that reads as "there is nothing".
///
/// It prints the reason the service itself gave. This used to be a fixed line
/// naming AniList, which was wrong twice over: it named AniList even when the
/// Kitsu fallback was what failed, and it threw away the sentence the service
/// sent explaining itself — the difference between "Couldn't reach AniList"
/// and "AniList has temporarily disabled their API".
class _RailError extends StatelessWidget {
  const _RailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  String get _message => switch (error) {
    DiscoveryUnavailable(:final service, :final reason) =>
      '${service.label} $reason.',
    _ => 'Could not load this row.',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Flexible(
            child: Text(
              _message,
              style: TextStyle(color: context.secondaryColor),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Just the poster area, filled flat. Sized by its parent, so it can stand in
/// for a cover inside an already-sized box without changing that box's height.
class _PosterBlock extends StatelessWidget {
  const _PosterBlock();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

/// A whole card - poster plus title line - shown while a remote row loads.
class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      width: _cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _cardWidth,
            height: _cardWidth * 1.5,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 6),
          Container(width: _cardWidth * 0.8, height: 10, color: fill),
        ],
      ),
    );
  }
}

/// A cover from AniList. Uses the app's own resizing cover provider rather
/// than a plain network image, so a rail of posters cannot fill the image
/// cache with full-resolution bitmaps, and it degrades to the placeholder
/// block when there is no URL or the fetch fails.
class _RemoteImage extends StatelessWidget {
  const _RemoteImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _PosterBlock();
    return Image(
      image: coverProvider(url!),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PosterBlock(),
    );
  }
}

/// A library entry in a rail: cover, title, and a progress bar once some of
/// the series has been watched.
class _LocalCard extends ConsumerWidget {
  const _LocalCard({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = manga.chapters.length;
    final watched = manga.chapters.where((c) => c.isRead ?? false).length;
    final progress = (total > 0 && watched > 0 && watched < total)
        ? watched / total
        : 0.0;

    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onTapEntry(
          isLongPressed: false,
          ref: ref,
          context: context,
          entry: manga,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  SizedBox(
                    width: _cardWidth,
                    height: _cardWidth * 1.5,
                    child: Image(
                      image: resolveCoverImage(manga, ref),
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.black45,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              manga.name ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// An AniList entry in a rail.
///
/// AniList is a catalogue, not a source: there is no episode behind this card
/// to open. Tapping runs the title through every installed anime source, which
/// is the only thing that can turn it into something playable.
class _RemoteCard extends StatelessWidget {
  const _RemoteCard({required this.media});

  final DiscoveryMedia media;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => searchInSources(context, media),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: _cardWidth,
                height: _cardWidth * 1.5,
                child: _RemoteImage(url: media.coverImage),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              media.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hands an AniList title to global search, which queries every installed
/// anime source at once and lists what each one found.
void searchInSources(BuildContext context, DiscoveryMedia media) {
  final term = media.searchTitle.isNotEmpty ? media.searchTitle : media.title;
  context.push('/globalSearch', extra: (term, ItemType.anime));
}


/// Formats a saved playback position for the hero's line under the title.
String _fmtPosition(int ms) {
  final d = Duration(milliseconds: ms);
  final m = (d.inMinutes % 60).toString().padLeft(d.inHours > 0 ? 2 : 1, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

/// The banner for the thing you were last watching: the cover filling the
/// width behind a scrim, the title, the synopsis, and one button back into
/// the episode you stopped on.
///
/// The synopsis comes off the library entry rather than from AniList. An entry
/// you have watched has been opened, and opening it is what stores the
/// description, so it is already on the device: no request to make, no title
/// to match, and it still reads with the network off.
class _ContinueHero extends ConsumerWidget {
  const _ContinueHero({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = resolveCoverImage(manga, ref);
    final resume = _resumeChapter(manga);
    final positionMs = int.tryParse(resume?.lastPageRead ?? '') ?? 0;

    // Episode name, then how far into it you were. Both are dropped when
    // absent rather than left as an empty gap or a bare "0:00".
    final meta = [
      if ((resume?.name ?? '').isNotEmpty) resume!.name!,
      if (positionMs > 0) _fmtPosition(positionMs),
    ].join('  ·  ');

    final synopsis = (manga.description ?? '').trim();

    return SizedBox(
      height: 360,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The cover fills the banner and is blurred behind the text, the way
          // a key art still would be. It fades out at its own bottom edge
          // rather than blending toward a background colour it would have to
          // guess at, so it works in both themes.
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.62, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Image(image: image, fit: BoxFit.cover),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x59000000), Color(0xD9000000)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 96,
                    height: 144,
                    child: Image(image: image, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        manga.name ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (synopsis.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        // Cut with an ellipsis rather than scrolled: a scroll
                        // area inside a banner competes with the page's own
                        // scroll, and the detail page carries the full text.
                        Text(
                          synopsis,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: resume == null
                            ? null
                            : () => resume.pushToReaderView(context),
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Continue Watching'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
