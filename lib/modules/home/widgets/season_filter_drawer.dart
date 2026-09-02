import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/modules/home/providers/home_feed_providers.dart';
import 'package:mangayomi/services/anilist_discovery.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

/// The seasons AniList knows about, with the months they cover spelled out so
/// the row says what it means without the reader having to know the mapping.
const _seasons = <(String, String)>[
  ('WINTER', 'Winter (January - March)'),
  ('SPRING', 'Spring (April - June)'),
  ('SUMMER', 'Summer (July - September)'),
  ('FALL', 'Fall / Autumn (October - December)'),
];

/// Side panel behind the home screen's hamburger: pick the season the
/// "Top This Season" row shows.
///
/// Nothing is applied while you tap. The choice is held locally and written to
/// the provider on Apply, so a half-made selection never sets off a fetch.
class SeasonFilterDrawer extends ConsumerStatefulWidget {
  const SeasonFilterDrawer({super.key});

  @override
  ConsumerState<SeasonFilterDrawer> createState() => _SeasonFilterDrawerState();
}

class _SeasonFilterDrawerState extends ConsumerState<SeasonFilterDrawer> {
  late (String, int) _draft = ref.read(selectedSeasonProvider);

  /// A decade back and one year on, which covers what AniList has seasonal
  /// data worth showing for.
  List<int> get _years {
    final thisYear = DateTime.now().year;
    return [for (var y = thisYear + 1; y >= thisYear - 10; y--) y];
  }

  @override
  Widget build(BuildContext context) {
    final (currentSeasonName, _) = currentSeason();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
              'Season',
              style: TextStyle(fontSize: 13, color: context.secondaryColor),
            ),
            const SizedBox(height: 4),
            for (final (value, label) in _seasons)
              RadioListTile<String>(
                value: value,
                groupValue: _draft.$1,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  value == currentSeasonName ? '$label  ·  current' : label,
                ),
                onChanged: (v) =>
                    setState(() => _draft = (v ?? _draft.$1, _draft.$2)),
              ),
            const SizedBox(height: 12),
            Text(
              'Year',
              style: TextStyle(fontSize: 13, color: context.secondaryColor),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _draft.$2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                for (final y in _years)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) =>
                  setState(() => _draft = (_draft.$1, v ?? _draft.$2)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      ref.read(selectedSeasonProvider.notifier).set(_draft);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(selectedSeasonProvider.notifier).reset();
                      setState(
                        () => _draft = ref.read(selectedSeasonProvider),
                      );
                      Navigator.of(context).pop();
                    },
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
