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

  Future<void> _refresh() async {
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

    final localHero = continueList.isNotEmpty
        ? continueList.first
        : (recent.isNotEmpty ? recent.first : null);

    // Nothing watched and nothing in the library: the hero falls back to the
    // top trending title, so a fresh install still opens on something.
    final trending = ref.watch(trendingAnimeProvider);
    final remoteHero = localHero == null
        ? trending.asData?.value.firstOrNull
        : null;

    final (season, year) = ref.watch(selectedSeasonProvider);

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
            if (localHero != null)
              SliverToBoxAdapter(child: _LocalHero(manga: localHero))
            else if (remoteHero != null)
              SliverToBoxAdapter(child: _RemoteHero(media: remoteHero))
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
                onRetry: () => ref.invalidate(trendingAnimeProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _RemoteRail(
                title: 'New This Week',
                value: ref.watch(recentlyAiredAnimeProvider),
                onRetry: () => ref.invalidate(recentlyAiredAnimeProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _RemoteRail(
                title: 'Top ${_seasonLabel(season, year)}',
                value: ref.watch(seasonAnimeProvider),
                onRetry: () => ref.invalidate(seasonAnimeProvider),
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
          error: (_, _) => _RailError(onRetry: onRetry),
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
class _RailError extends StatelessWidget {
  const _RailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Flexible(
            child: Text(
              "Couldn't reach AniList.",
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

/// The top banner for a library entry: blurred cover behind, poster and title
/// in front, and a Resume button that picks up where you left off.
class _LocalHero extends ConsumerWidget {
  const _LocalHero({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final image = resolveCoverImage(manga, ref);
    final resume = _resumeChapter(manga);
    final unread = manga.chapters.where((c) => !(c.isRead ?? true)).length;

    return _HeroFrame(
      backdrop: Image(image: image, fit: BoxFit.cover),
      poster: Image(image: image, fit: BoxFit.cover),
      title: manga.name ?? '',
      subtitle: [
        if ((resume?.name ?? '').isNotEmpty) resume!.name!,
        if (unread > 0) '$unread new',
      ].join('  ·  '),
      action: FilledButton.icon(
        onPressed: resume == null
            ? null
            : () => resume.pushToReaderView(context),
        icon: const Icon(Icons.play_arrow, size: 20),
        label: Text(l10n.resume),
      ),
    );
  }
}

/// The top banner on an install with nothing in the library yet: the top
/// trending title, with a button into the sources that might carry it.
class _RemoteHero extends StatelessWidget {
  const _RemoteHero({required this.media});

  final DiscoveryMedia media;

  @override
  Widget build(BuildContext context) {
    final backdropUrl = media.bannerImage ?? media.coverImage;
    return _HeroFrame(
      backdrop: _RemoteImage(url: backdropUrl),
      poster: _RemoteImage(url: media.coverImage),
      title: media.title,
      subtitle: [
        'Trending now',
        if (media.averageScore != null) '${media.averageScore}%',
      ].join('  ·  '),
      action: FilledButton.icon(
        onPressed: () => searchInSources(context, media),
        icon: const Icon(Icons.search, size: 20),
        label: const Text('Find in sources'),
      ),
    );
  }
}

/// The shared hero layout, so the library hero and the trending hero cannot
/// drift apart.
class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.backdrop,
    required this.poster,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final Widget backdrop;
  final Widget poster;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 330,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The backdrop fades out at its own bottom edge rather than blending
          // toward a background colour it would have to guess at, so it works
          // in both themes.
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
                  child: backdrop,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0xCC000000)],
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
                  child: SizedBox(width: 96, height: 144, child: poster),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      action,
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
