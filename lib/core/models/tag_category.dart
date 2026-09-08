import 'dart:ui' show Color;

/// The tag-category vocabulary shared by the bundled Danbooru list, imported
/// tag lists, and every place that colours a tag chip.
///
/// Categories are plain strings (they always were — `DanbooruTag.typeName`),
/// so this class is the single home for the known values, their colours, and
/// the textual synonyms an imported file might use. Numeric booru category
/// codes are mapped through [TagSiteProfile], because the same integer means
/// different things on different sites.
class TagCategories {
  TagCategories._();

  static const String general = 'general';
  static const String artist = 'artist';
  static const String copyright = 'copyright';
  static const String character = 'character';
  static const String species = 'species';
  static const String meta = 'meta';
  static const String lore = 'lore';
  static const String contributor = 'contributor';

  /// Sentinel for rows a booru marks as invalid; the importer drops them.
  static const String invalid = 'invalid';

  /// Every real (user-selectable, importable) category, in display order.
  static const List<String> all = [
    general,
    artist,
    character,
    copyright,
    species,
    meta,
    lore,
    contributor,
  ];

  /// Pseudo-categories used only for routing suggestion chips; never stored.
  static const String wildcard = 'wildcard';
  static const String wildcardFavorite = 'wildcard_favorite';
  static const String savedCharacter = 'saved_character';
  static const String categoryShortcut = 'category_shortcut';

  static bool isReal(String typeName) => all.contains(typeName.toLowerCase());

  /// Chip / row colour for a category (real or pseudo). Unknown → white.
  static Color colorFor(String typeName) {
    switch (typeName.toLowerCase()) {
      case copyright:
        return const Color(0xFFD880FF);
      case character:
        return const Color(0xFF00AD00);
      case artist:
        return const Color(0xFFFF5858);
      case meta:
        return const Color(0xFFFF9229);
      case species:
        return const Color(0xFF64B5F6);
      case lore:
        return const Color(0xFFA1887F);
      case contributor:
        return const Color(0xFFB0BEC5);
      case wildcard:
        return const Color(0xFF00BCD4);
      case wildcardFavorite:
        return const Color(0xFFFFD740);
      case savedCharacter:
        return const Color(0xFF7AD7A0);
      case categoryShortcut:
        return const Color(0xFFFF5858);
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  /// Single-letter key used by the `/f<letter>` favourites shortcut.
  static String? shortcutLetter(String typeName) {
    switch (typeName) {
      case general:
        return 'g';
      case artist:
        return 'a';
      case character:
        return 'c';
      case copyright:
        return 'r';
      case meta:
        return 'm';
      case species:
        return 's';
      case lore:
        return 'l';
    }
    return null;
  }

  static String? fromShortcutLetter(String letter) {
    switch (letter) {
      case 'g':
        return general;
      case 'a':
        return artist;
      case 'c':
        return character;
      case 'r':
        return copyright;
      case 'm':
        return meta;
      case 's':
        return species;
      case 'l':
        return lore;
    }
    return null;
  }

  /// Resolves a textual category label as found in tag files (`general`,
  /// `Artist`, `copy`, `char`, `type_name` values, …). Returns null when the
  /// label is not recognised, so callers can fall back to a numeric profile.
  static String? fromLabel(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    switch (v) {
      case general:
      case 'gen':
      case 'tag':
      case 'tags':
        return general;
      case artist:
      case 'artists':
      case 'art':
        return artist;
      case copyright:
      case 'copyrights':
      case 'copy':
      case 'series':
        return copyright;
      case character:
      case 'characters':
      case 'char':
      case 'chara':
        return character;
      case species:
      case 'specie':
        return species;
      case meta:
      case 'metadata':
        return meta;
      case lore:
        return lore;
      case contributor:
      case 'contributors':
        return contributor;
      case invalid:
      case 'deprecated':
        return invalid;
    }
    return null;
  }
}

/// How an imported file numbers its categories.
///
/// The a1111 tag-autocomplete CSV format carries a numeric category column,
/// but the meaning of each number depends on which site the list came from:
/// `5` is *meta* on Danbooru and *species* on e621. Merged Danbooru+e621
/// lists offset the e621 block to 7–15 so both can coexist in one file.
enum TagSiteProfile {
  danbooru,
  e621,
  e621Merged,
  custom;

  /// Numeric code → category for this profile. Empty for [custom].
  Map<int, String> get codes {
    switch (this) {
      case TagSiteProfile.danbooru:
        return const {
          0: TagCategories.general,
          1: TagCategories.artist,
          2: TagCategories.invalid,
          3: TagCategories.copyright,
          4: TagCategories.character,
          5: TagCategories.meta,
        };
      case TagSiteProfile.e621:
        return const {
          -1: TagCategories.invalid,
          0: TagCategories.general,
          1: TagCategories.artist,
          2: TagCategories.contributor,
          3: TagCategories.copyright,
          4: TagCategories.character,
          5: TagCategories.species,
          6: TagCategories.invalid,
          7: TagCategories.meta,
          8: TagCategories.lore,
        };
      case TagSiteProfile.e621Merged:
        // Danbooru block stays 0–5; e621 block is shifted by 7.
        return const {
          0: TagCategories.general,
          1: TagCategories.artist,
          2: TagCategories.invalid,
          3: TagCategories.copyright,
          4: TagCategories.character,
          5: TagCategories.meta,
          7: TagCategories.general,
          8: TagCategories.artist,
          9: TagCategories.contributor,
          10: TagCategories.copyright,
          11: TagCategories.character,
          12: TagCategories.species,
          13: TagCategories.invalid,
          14: TagCategories.meta,
          15: TagCategories.lore,
        };
      case TagSiteProfile.custom:
        return const {};
    }
  }

  /// Picks the profile most likely to fit the raw category values found in a
  /// file. Numbers 9+ only occur in merged lists; 6–8 only on e621; anything
  /// else is indistinguishable from Danbooru and defaults to it (the UI shows
  /// the choice so the user can flip it).
  static TagSiteProfile guess(Iterable<String> rawValues) {
    var maxCode = -1;
    var sawE621Only = false;
    for (final raw in rawValues) {
      final n = int.tryParse(raw.trim());
      if (n == null) continue;
      if (n > maxCode) maxCode = n;
      if (n >= 6 && n <= 8) sawE621Only = true;
    }
    if (maxCode >= 9) return TagSiteProfile.e621Merged;
    if (sawE621Only) return TagSiteProfile.e621;
    return TagSiteProfile.danbooru;
  }

  static TagSiteProfile fromName(String? name) {
    for (final p in TagSiteProfile.values) {
      if (p.name == name) return p;
    }
    return TagSiteProfile.danbooru;
  }
}
