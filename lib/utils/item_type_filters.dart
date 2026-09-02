import 'package:mangayomi/models/manga.dart';

List<ItemType> hiddenItemTypes(List<String> hideItems) {
  return [
    if (!hideItems.contains("/AnimeLibrary")) ItemType.anime,
  ];
}
