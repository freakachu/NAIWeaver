import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'tag_source_service.dart';

class DanbooruTag {
  final String tag;
  final int count;
  final String typeName;
  final bool isFavorite;
  final List<String> examplePaths;
  final List<String> aliases;
  final String? matchedAlias;

  /// Id of the imported tag list this tag came from, or null for the bundled
  /// Danbooru list (and for synthetic suggestion entries). Never serialised
  /// into the bundled file — a source's own file implies it.
  final String? sourceId;

  /// For `typeName == 'saved_character'`: the pre-expanded tag string inserted
  /// at the cursor when this suggestion is picked. The default `expansion`
  /// honours the outfit's saved state (concealment + `nsfw` if dishevelled);
  /// [flatExpansion] is the alternative that uses the raw outfit tags with no
  /// state routing. The suggestion overlay's per-insertion "honor state"
  /// toggle picks between the two.
  final String? expansion;
  final String? flatExpansion;

  /// For `typeName == 'saved_character'`: comma-separated negative tags to
  /// inject into a negative-prompt target when this suggestion is picked. The
  /// callback that handles selection decides where they go (global negative
  /// prompt vs. a character's UC field) — see the per-context handlers.
  final String? negativeExpansion;

  DanbooruTag({
    required this.tag,
    required this.count,
    this.typeName = 'general',
    this.isFavorite = false,
    this.examplePaths = const [],
    this.aliases = const [],
    this.matchedAlias,
    this.sourceId,
    this.expansion,
    this.flatExpansion,
    this.negativeExpansion,
  });

  DanbooruTag copyWith({
    String? tag,
    int? count,
    String? typeName,
    bool? isFavorite,
    List<String>? examplePaths,
    List<String>? aliases,
    String? Function()? matchedAlias,
    String? Function()? sourceId,
    String? Function()? expansion,
    String? Function()? flatExpansion,
    String? Function()? negativeExpansion,
  }) {
    return DanbooruTag(
      tag: tag ?? this.tag,
      count: count ?? this.count,
      typeName: typeName ?? this.typeName,
      isFavorite: isFavorite ?? this.isFavorite,
      examplePaths: examplePaths ?? this.examplePaths,
      aliases: aliases ?? this.aliases,
      matchedAlias: matchedAlias != null ? matchedAlias() : this.matchedAlias,
      sourceId: sourceId != null ? sourceId() : this.sourceId,
      expansion: expansion != null ? expansion() : this.expansion,
      flatExpansion: flatExpansion != null ? flatExpansion() : this.flatExpansion,
      negativeExpansion: negativeExpansion != null ? negativeExpansion() : this.negativeExpansion,
    );
  }

  factory DanbooruTag.fromJson(Map<String, dynamic> json) {
    return DanbooruTag(
      tag: json['tag'] as String,
      count: (json['count'] as num?)?.toInt() ?? 0,
      typeName: json['type_name'] as String? ?? 'general',
      isFavorite: json['is_favorite'] as bool? ?? false,
      examplePaths: (json['example_paths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'count': count,
      'type_name': typeName,
      'is_favorite': isFavorite,
      'example_paths': examplePaths,
      'aliases': aliases,
    };
  }
}

/// Tag lookup for autocomplete and the Tag Library.
///
/// Two layers:
/// - the **bundled** Danbooru list at [filePath] (user edits — favourites,
///   custom tags, example images — are written back into that file), and
/// - zero or more **imported sources** held by [sourceService], merged in at
///   load time and whenever a source changes.
///
/// `_tags` is the merged view every query runs against. On a name collision
/// the bundled record wins (it carries the user's favourites/examples); the
/// imported record only contributes extra aliases and a higher count.
class TagService {
  final String filePath;
  final TagSourceService? sourceService;

  List<DanbooruTag> _bundled = [];
  List<DanbooruTag> _tags = [];
  bool _isLoaded = false;
  Set<String>? _tagSet;
  Map<String, int>? _aliasToTagIndex;

  // Name index: merged-list indices ordered by lower-cased name, plus the
  // parallel list of those names, so a prefix query is a binary search
  // instead of a scan over every tag.
  List<int> _nameOrder = const [];
  List<String> _lowerNames = const [];

  Set<String> get tagSet {
    _tagSet ??= _tags.map((t) => t.tag.toLowerCase()).toSet();
    return _tagSet!;
  }

  bool hasTag(String tag) => tagSet.contains(tag.toLowerCase().trim());

  /// Returns true if any codeUnit in [s] is > 127 (non-ASCII, e.g. CJK).
  static bool containsNonAscii(String s) {
    for (int i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) > 127) return true;
    }
    return false;
  }

  TagService({required this.filePath, this.sourceService});

  bool get isLoaded => _isLoaded;

  /// The merged view: bundled tags plus every enabled imported source.
  List<DanbooruTag> get tags => _tags;

  /// Bundled tags only (what [saveTags] writes).
  List<DanbooruTag> get bundledTags => _bundled;

  /// Short label for a source id (suggestion-chip badge), or null.
  String? sourceBadge(String? sourceId) {
    if (sourceId == null) return null;
    return sourceService?.byId(sourceId)?.badge;
  }

  Future<void> loadTags() async {
    try {
      String content;
      if (kIsWeb) {
        content = await rootBundle.loadString('Tags/high-frequency-tags-list.json');
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint("Tag file not found: $filePath");
          return;
        }
        content = await file.readAsString();
      }

      // Using compute for heavy JSON parsing to keep UI responsive
      _bundled = await compute(_parseTags, content);
      _mergeNaiV5Tags();

      if (sourceService != null && !sourceService!.isLoaded) {
        await sourceService!.load();
      }

      _rebuild();
      _isLoaded = true;
      debugPrint("Loaded ${_bundled.length} bundled tags, ${_tags.length} merged.");
    } catch (e) {
      debugPrint("Error loading tags: $e");
    }
  }

  /// Re-merges imported sources into the lookup view. Call after any change
  /// to [sourceService] (import, enable/disable, reorder, delete).
  void refreshSources() {
    if (!_isLoaded) return;
    _rebuild();
  }

  void _rebuild() {
    final merged = <DanbooruTag>[];
    final index = <String, int>{};

    for (final t in _bundled) {
      final k = t.tag.toLowerCase();
      if (index.containsKey(k)) continue;
      index[k] = merged.length;
      merged.add(t);
    }

    final sources = sourceService;
    if (sources != null) {
      for (final src in sources.enabledSources) {
        for (final t in sources.tagsOf(src.id)) {
          final k = t.tag.toLowerCase();
          final existingIdx = index[k];
          if (existingIdx != null) {
            // Collision: keep the higher-priority record, absorb extras.
            final ex = merged[existingIdx];
            final extra = t.aliases.where((a) => !ex.aliases.contains(a)).toList();
            if (extra.isNotEmpty || t.count > ex.count) {
              merged[existingIdx] = ex.copyWith(
                aliases: extra.isEmpty ? null : [...ex.aliases, ...extra],
                count: t.count > ex.count ? t.count : null,
              );
            }
            continue;
          }
          final st = sources.stateFor(k);
          index[k] = merged.length;
          merged.add(st == null
              ? t
              : t.copyWith(isFavorite: st.favorite, examplePaths: st.examples));
        }
      }
    }

    // Sort tags by count descending for suggestion ranking
    merged.sort((a, b) => b.count.compareTo(a.count));
    _tags = merged;
    _tagSet = null;
    _buildAliasIndex();
    _buildNameIndex();
  }

  void _buildAliasIndex() {
    final index = <String, int>{};
    final tags = tagSet; // ensure tagSet is built
    for (int i = 0; i < _tags.length; i++) {
      for (final alias in _tags[i].aliases) {
        final lowerAlias = alias.toLowerCase();
        // English tag names always take priority over aliases
        if (!tags.contains(lowerAlias)) {
          index.putIfAbsent(lowerAlias, () => i);
        }
      }
    }
    _aliasToTagIndex = index;
  }

  void _buildNameIndex() {
    final order = List<int>.generate(_tags.length, (i) => i);
    final names = _tags.map((t) => t.tag.toLowerCase()).toList(growable: false);
    order.sort((a, b) => names[a].compareTo(names[b]));
    _nameOrder = order;
    _lowerNames = order.map((i) => names[i]).toList(growable: false);
  }

  /// Indices (into [_tags]) of every tag whose lower-cased name starts with
  /// [lowerQuery], via binary search on the name index.
  Iterable<int> _prefixIndices(String lowerQuery) sync* {
    var lo = 0, hi = _lowerNames.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_lowerNames[mid].compareTo(lowerQuery) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _lowerNames.length && _lowerNames[i].startsWith(lowerQuery); i++) {
      yield _nameOrder[i];
    }
  }

  /// Tags NovelAI introduced with Diffusion V5 (journal post, 2026-08-21).
  /// They are not in the Danbooru-derived tag list, so they are merged in
  /// here to make them autocomplete. Counts are nominal — just enough to
  /// surface above the long tail.
  static const List<String> naiV5Tags = [
    'depthness',
    'attractive male',
    'low complexity',
    'medium complexity',
    'high complexity',
    'ultra complexity',
    'has alpha',
    'alpha transparency',
    'transparent background',
    'meta:novel era',
    'meta:golden era',
    'visual novel art',
    'visual novel bg',
    'visual novel cg',
    'visual novel chibi',
    'visual novel sprite',
  ];

  void _mergeNaiV5Tags() {
    final existing = _bundled.map((t) => t.tag.toLowerCase()).toSet();
    for (final tag in naiV5Tags) {
      if (existing.contains(tag)) continue;
      _bundled.add(DanbooruTag(tag: tag, count: 500, typeName: 'general'));
    }
  }

  static List<DanbooruTag> _parseTags(String jsonString) {
    final List<dynamic> decoded = jsonDecode(jsonString);
    return decoded.map((item) => DanbooruTag.fromJson(item)).toList();
  }

  static int _compareTag(DanbooruTag a, DanbooruTag b) {
    if (a.isFavorite && !b.isFavorite) return -1;
    if (!a.isFavorite && b.isFavorite) return 1;
    return b.count.compareTo(a.count);
  }

  List<DanbooruTag> getSuggestions(String query, {int limit = 20}) {
    final minLength = containsNonAscii(query) ? 1 : 3;
    if (!_isLoaded || query.length < minLength) return [];
    return _search(query.toLowerCase(), limit: limit, category: null);
  }

  List<DanbooruTag> getTagsByCategory(String query, String category, {int limit = 20}) {
    if (!_isLoaded) return [];

    final lowerCategory = category.toLowerCase();
    final lowerQuery = query.toLowerCase();

    // Empty query → return all favorites in this category, sorted by count
    if (lowerQuery.isEmpty) {
      return _tags
          .where((tag) => tag.isFavorite && tag.typeName.toLowerCase() == lowerCategory)
          .toList();
    }
    return _search(lowerQuery, limit: limit, category: lowerCategory);
  }

  /// Three tiers — prefix matches, then substring matches, then alias
  /// matches — each sorted favourites-first then by count. Later tiers are
  /// only computed when the earlier ones have not already filled [limit],
  /// which keeps the common case to one binary search plus a short walk.
  List<DanbooruTag> _search(String lowerQuery, {required int limit, required String? category}) {
    final seenTags = <String>{};
    bool inCategory(DanbooruTag t) => category == null || t.typeName.toLowerCase() == category;

    final prefixMatches = <DanbooruTag>[];
    for (final i in _prefixIndices(lowerQuery)) {
      final tag = _tags[i];
      if (!inCategory(tag)) continue;
      prefixMatches.add(tag);
      seenTags.add(tag.tag.toLowerCase());
    }
    prefixMatches.sort(_compareTag);
    if (prefixMatches.length >= limit) return prefixMatches.take(limit).toList();

    final wordMatches = <DanbooruTag>[];
    for (final tag in _tags) {
      if (!inCategory(tag)) continue;
      final lowerTag = tag.tag.toLowerCase();
      if (seenTags.contains(lowerTag)) continue;
      if (lowerTag.contains(lowerQuery)) {
        wordMatches.add(tag);
        seenTags.add(lowerTag);
      }
    }
    wordMatches.sort(_compareTag);
    if (prefixMatches.length + wordMatches.length >= limit) {
      return [...prefixMatches, ...wordMatches].take(limit).toList();
    }

    final aliasMatches = <DanbooruTag>[];
    if (_aliasToTagIndex != null) {
      for (final entry in _aliasToTagIndex!.entries) {
        final alias = entry.key;
        if (!alias.contains(lowerQuery)) continue;
        final tag = _tags[entry.value];
        if (!inCategory(tag)) continue;
        final lowerTag = tag.tag.toLowerCase();
        if (seenTags.contains(lowerTag)) continue;
        // Find the original-cased alias for display
        final originalAlias = tag.aliases.firstWhere(
          (a) => a.toLowerCase() == alias,
          orElse: () => alias,
        );
        aliasMatches.add(tag.copyWith(matchedAlias: () => originalAlias));
        seenTags.add(lowerTag);
      }
    }
    aliasMatches.sort(_compareTag);

    return [...prefixMatches, ...wordMatches, ...aliasMatches].take(limit).toList();
  }

  /// Resolves alias text in a prompt to English Danbooru tag names.
  ///
  /// Splits on `,` and `|`, preserves delimiters and whitespace,
  /// strips weight brackets before lookup, re-wraps after.
  String resolveAliases(String prompt) {
    if (!_isLoaded || _aliasToTagIndex == null || prompt.isEmpty) return prompt;

    final buffer = StringBuffer();
    final segmentPattern = RegExp(r'[,|]');
    int start = 0;

    while (start < prompt.length) {
      final match = segmentPattern.matchAsPrefix(prompt, start) ??
          _findNextDelimiter(prompt, start, segmentPattern);

      final int segEnd;
      final String? delimiter;
      if (match != null && match.start == start) {
        // Current position is a delimiter
        buffer.write(prompt[start]);
        start++;
        continue;
      }

      // Find next delimiter
      final nextDelim = segmentPattern.firstMatch(prompt.substring(start));
      if (nextDelim != null) {
        segEnd = start + nextDelim.start;
        delimiter = prompt[segEnd];
      } else {
        segEnd = prompt.length;
        delimiter = null;
      }

      final segment = prompt.substring(start, segEnd);
      buffer.write(_resolveSegment(segment));
      if (delimiter != null) buffer.write(delimiter);
      start = segEnd + (delimiter != null ? 1 : 0);
    }

    return buffer.toString();
  }

  Match? _findNextDelimiter(String prompt, int start, RegExp pattern) {
    final sub = prompt.substring(start);
    return pattern.firstMatch(sub);
  }

  String _resolveSegment(String segment) {
    // Preserve leading/trailing whitespace
    final leading = segment.length - segment.trimLeft().length;
    final trailing = segment.length - segment.trimRight().length;
    final leadingWs = segment.substring(0, leading);
    final trailingWs = trailing > 0 ? segment.substring(segment.length - trailing) : '';
    final trimmed = segment.trim();
    if (trimmed.isEmpty) return segment;

    // Strip weight brackets from both ends
    String core = trimmed;
    String prefixBrackets = '';
    String suffixBrackets = '';
    while (core.isNotEmpty && (core[0] == '{' || core[0] == '[')) {
      prefixBrackets += core[0];
      core = core.substring(1);
    }
    while (core.isNotEmpty && (core[core.length - 1] == '}' || core[core.length - 1] == ']')) {
      suffixBrackets = core[core.length - 1] + suffixBrackets;
      core = core.substring(0, core.length - 1);
    }
    core = core.trim();
    if (core.isEmpty) return segment;

    final lowerCore = core.toLowerCase();

    // If it's already a known English tag, pass through
    if (tagSet.contains(lowerCore)) return segment;

    // If it's a known alias, replace with English tag
    final tagIndex = _aliasToTagIndex![lowerCore];
    if (tagIndex != null) {
      final englishTag = _tags[tagIndex].tag;
      return '$leadingWs$prefixBrackets$englishTag$suffixBrackets$trailingWs';
    }

    return segment;
  }

  List<DanbooruTag> getFavorites({String? category}) {
    if (!_isLoaded) return [];

    return _tags.where((tag) {
      final isFav = tag.isFavorite;
      if (category == null) return isFav;
      return isFav && tag.typeName.toLowerCase() == category.toLowerCase();
    }).toList();
  }

  // ── Mutations ────────────────────────────────────────────────────────
  //
  // Bundled tags are edited in `_bundled` and written back to the bundled
  // file; imported tags keep favourites/examples in the source service's
  // user-state sidecar. Either way the merged view is rebuilt afterwards.

  int _bundledIndexOf(String tagName) {
    final lower = tagName.toLowerCase();
    return _bundled.indexWhere((t) => t.tag.toLowerCase() == lower);
  }

  DanbooruTag? _mergedByName(String tagName) {
    final lower = tagName.toLowerCase();
    for (final i in _prefixIndices(lower)) {
      if (_tags[i].tag.toLowerCase() == lower) return _tags[i];
    }
    return null;
  }

  Future<void> toggleFavorite(DanbooruTag tag) async {
    final bi = _bundledIndexOf(tag.tag);
    if (bi != -1) {
      _bundled[bi] = _bundled[bi].copyWith(isFavorite: !_bundled[bi].isFavorite);
      _rebuild();
      await saveTags();
      return;
    }
    final sources = sourceService;
    if (sources == null) return;
    final current = _mergedByName(tag.tag)?.isFavorite ?? tag.isFavorite;
    await sources.setFavorite(tag.tag, !current);
    _rebuild();
  }

  Future<void> addTag(DanbooruTag tag) async {
    _bundled.add(tag.copyWith(sourceId: () => null));
    _rebuild();
    await saveTags();
  }

  Future<void> deleteTag(DanbooruTag tag) async {
    final bi = _bundledIndexOf(tag.tag);
    if (bi != -1) {
      _bundled.removeAt(bi);
      _rebuild();
      await saveTags();
      return;
    }
    final sourceId = tag.sourceId ?? _mergedByName(tag.tag)?.sourceId;
    if (sourceId != null && sourceService != null) {
      await sourceService!.removeTag(sourceId, tag.tag);
      _rebuild();
    }
  }

  Future<void> addExampleToTag(String tagName, String path) async {
    final bi = _bundledIndexOf(tagName);
    if (bi != -1) {
      final updatedPaths = List<String>.from(_bundled[bi].examplePaths)..add(path);
      _bundled[bi] = _bundled[bi].copyWith(examplePaths: updatedPaths);
      _rebuild();
      await saveTags();
      return;
    }
    if (sourceService != null && _mergedByName(tagName) != null) {
      await sourceService!.addExample(tagName, path);
      _rebuild();
    }
  }

  Future<void> removeExampleFromTag(String tagName, String path) async {
    final bi = _bundledIndexOf(tagName);
    if (bi != -1) {
      final updatedPaths = List<String>.from(_bundled[bi].examplePaths)..remove(path);
      _bundled[bi] = _bundled[bi].copyWith(examplePaths: updatedPaths);
      _rebuild();
      await saveTags();
      return;
    }
    if (sourceService != null) {
      await sourceService!.removeExample(tagName, path);
      _rebuild();
    }
  }

  Future<void> clearAllExamples() async {
    for (int i = 0; i < _bundled.length; i++) {
      if (_bundled[i].examplePaths.isNotEmpty) {
        _bundled[i] = _bundled[i].copyWith(examplePaths: []);
      }
    }
    await sourceService?.clearAllExamples();
    _rebuild();
    await saveTags();
  }

  Future<void> saveTags() async {
    // The tag list (~MB) is too large for SharedPreferences and the web build
    // has no filesystem to write to. Tags ship as a bundled asset on web; user
    // edits (favorites, example paths) are session-only there until we add an
    // IndexedDB-backed store.
    if (kIsWeb) return;
    try {
      final file = File(filePath);
      final jsonString = await compute(_serializeTags, _bundled);
      await file.writeAsString(jsonString);
      debugPrint("Saved ${_bundled.length} tags to $filePath");
    } catch (e) {
      debugPrint("Error saving tags: $e");
    }
  }

  static String _serializeTags(List<DanbooruTag> tags) {
    return jsonEncode(tags.map((t) => t.toJson()).toList());
  }
}
