import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/history.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/history/providers/isar_providers.dart';
import 'package:mangayomi/modules/library/providers/isar_providers.dart';
import 'package:mangayomi/modules/library/widgets/library_entry_utils.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/repositories/history_repository.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:mangayomi/utils/extensions/chapter_extensions.dart';

/// Poster width for the rails. Phones get a fixed size rather than the
/// library's grid-size setting: a rail is not a grid, and the whole point of
/// the row is that the next poster peeks in from the edge.
const double _cardWidth = 118;

/// Posters are 2:3, plus room for the title line underneath.
const double _cardHeight = _cardWidth * 1.5 + 38;

/// Where "Play" goes: the episode in history if there is one, else the first.
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

/// The phone home: a hero for the thing you would resume, then horizontal
/// rails.
///
/// Everything here reads the local library, so it renders with no network and
/// no sources installed. The trending / seasonal rails that need AniList are
/// added on top of this in a later change.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
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

    // The hero is what you would resume; with nothing watched yet, the newest
    // thing in the library is the best stand-in.
    final hero = continueList.isNotEmpty
        ? continueList.first
        : (recent.isNotEmpty ? recent.first : null);

    return Scaffold(
      body: entries.isEmpty
          ? _EmptyLibrary(message: l10n.empty_library)
          : CustomScrollView(
              slivers: [
                if (hero != null)
                  SliverToBoxAdapter(child: _HomeHero(manga: hero)),
                if (continueList.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _HomeRail(
                      title: 'Continue Watching',
                      items: continueList,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _HomeRail(
                    title: 'Recently Added',
                    items: recent.take(30).toList(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }
}

/// Shown before anything is in the library, so the home is never a blank page.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 56,
              color: context.secondaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top banner: a blurred cover as the backdrop, the title over it, and a
/// Play button that resumes.
class _HomeHero extends ConsumerWidget {
  const _HomeHero({required this.manga});

  final Manga manga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final image = resolveCoverImage(manga, ref);
    final resume = _resumeChapter(manga);
    final unread = manga.chapters.where((c) => !(c.isRead ?? true)).length;

    final metaBits = <String>[
      if ((resume?.name ?? '').isNotEmpty) resume!.name!,
      if (unread > 0) '$unread new',
    ];

    return SizedBox(
      height: 320,
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
                  child: Image(image: image, fit: BoxFit.cover),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (metaBits.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          metaBits.join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: resume == null
                            ? null
                            : () => resume.pushToReaderView(context),
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: Text(l10n.resume),
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

/// One titled horizontal row of posters.
class _HomeRail extends StatelessWidget {
  const _HomeRail({required this.title, required this.items});

  final String title;
  final List<Manga> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
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
        SizedBox(
          height: _cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _RailCard(manga: items[i]),
          ),
        ),
      ],
    );
  }
}

/// A single poster in a rail: cover, title, and a progress bar once some of
/// the series has been watched.
class _RailCard extends ConsumerWidget {
  const _RailCard({required this.manga});

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
