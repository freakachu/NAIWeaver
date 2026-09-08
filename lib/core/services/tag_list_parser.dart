import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/tag_category.dart';
import 'tag_service.dart' show DanbooruTag;

/// Pure-Dart reader for user-supplied tag lists.
///
/// Two phases, both isolate-friendly (no Flutter imports, plain data in and
/// out):
///
/// 1. [sniff] looks at the file and works out its shape — CSV vs JSON vs
///    plain text, delimiter, header row, which column holds what, which
///    category numbering it uses, and a post-count histogram so the UI can
///    show "N of M tags" for a threshold before importing anything.
/// 2. [parse] turns the file into `DanbooruTag`s under a set of
///    [TagImportOptions] the user may have adjusted (column mapping, site
///    profile, minimum count, category filter, underscore handling).
///
/// Supported inputs:
/// - a1111 tag-autocomplete CSV, no header: `name,category,count,"aliases"`
/// - header CSV in any column order (`tag,category,count,alias`;
///   e621 db_export `id,name,category,post_count`; …), any of `,` `;` `\t` `|`
/// - JSON: array of objects, array of strings, or `{tag: count}` map
/// - plain text, one tag per line
/// - any of the above gzip-compressed (`.csv.gz` from e621's db_export)
class TagListParser {
  TagListParser._();

  /// Post-count ladder used for the histogram / minimum-count picker.
  static const List<int> countLadder = [0, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000, 10000];

  static const int sampleRowLimit = 20;
  static const int categoryValueLimit = 64;

  static const Set<String> _nameHeaders = {'tag', 'name', 'tag_name', 'tagname', 'tags'};
  static const Set<String> _categoryHeaders = {
    'category', 'type', 'category_id', 'type_name', 'typename', 'cat', 'kind'
  };
  static const Set<String> _countHeaders = {'count', 'post_count', 'postcount', 'posts', 'n'};
  static const Set<String> _aliasHeaders = {'alias', 'aliases', 'alias_tags', 'other_names', 'antecedents'};
  static const Set<String> _ignoredHeaders = {'id', 'is_favorite', 'example_paths', 'created_at', 'updated_at'};

  // ── Bytes → text ─────────────────────────────────────────────────────

  /// Decodes raw file bytes to text: gunzips when the gzip magic is present,
  /// tolerates malformed UTF-8, strips a BOM.
  static String decodeBytes(Uint8List bytes) {
    var data = bytes;
    if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
      data = Uint8List.fromList(GZipDecoder().decodeBytes(data));
    }
    var text = utf8.decode(data, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    return text;
  }

  // ── Sniff ────────────────────────────────────────────────────────────

  static TagListSniff sniff(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.isEmpty) {
      return TagListSniff.empty();
    }
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      final json = _tryJson(trimmed);
      if (json != null) return _sniffJson(json);
    }
    return _sniffDelimited(content);
  }

  static dynamic _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static TagListSniff _sniffJson(dynamic json) {
    // Our own exported list bundle (`{"source": {...}, "tags": [...]}`) —
    // the tag array inside is an ordinary array of objects.
    if (json is Map && json['tags'] is List) {
      return _sniffJson(json['tags']);
    }
    // Array of strings → plain tag names.
    if (json is List && json.isNotEmpty && json.every((e) => e is String)) {
      final rows = json.cast<String>().map((s) => [s]).toList();
      return _finish(
        format: TagListFormat.jsonStrings,
        columns: const [TagColumn('0', 'tag')],
        mapping: const TagColumnMapping(name: '0'),
        rows: rows,
        hasHeader: false,
      );
    }
    // Array of objects → columns are the union of keys seen in the first rows.
    if (json is List && json.isNotEmpty && json.every((e) => e is Map)) {
      final keys = <String>[];
      for (final e in json.take(50)) {
        for (final k in (e as Map).keys) {
          final ks = k.toString();
          if (!keys.contains(ks)) keys.add(ks);
        }
      }
      final columns = keys.map((k) => TagColumn(k, k)).toList();
      final rows = json.map((e) => keys.map((k) => _cellToString((e as Map)[k])).toList()).toList();
      return _finish(
        format: TagListFormat.jsonObjects,
        columns: columns,
        mapping: _guessMappingFromHeaders(keys),
        rows: rows,
        hasHeader: false,
      );
    }
    // Map → either {tag: count} or {tag: {...}}.
    if (json is Map && json.isNotEmpty) {
      final values = json.values;
      if (values.every((v) => v is num || v == null)) {
        final rows = json.entries.map((e) => [e.key.toString(), _cellToString(e.value)]).toList();
        return _finish(
          format: TagListFormat.jsonMap,
          columns: const [TagColumn('0', 'tag'), TagColumn('1', 'count')],
          mapping: const TagColumnMapping(name: '0', count: '1'),
          rows: rows,
          hasHeader: false,
        );
      }
      if (values.every((v) => v is Map)) {
        final keys = <String>['_key'];
        for (final v in values.take(50)) {
          for (final k in (v as Map).keys) {
            final ks = k.toString();
            if (!keys.contains(ks)) keys.add(ks);
          }
        }
        final rows = json.entries
            .map((e) => keys
                .map((k) => k == '_key' ? e.key.toString() : _cellToString((e.value as Map)[k]))
                .toList())
            .toList();
        final guessed = _guessMappingFromHeaders(keys);
        return _finish(
          format: TagListFormat.jsonObjects,
          columns: keys.map((k) => TagColumn(k, k == '_key' ? 'tag (key)' : k)).toList(),
          mapping: guessed.name == null ? guessed.copyWith(name: () => '_key') : guessed,
          rows: rows,
          hasHeader: false,
        );
      }
    }
    return TagListSniff.empty();
  }

  static String _cellToString(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.map((e) => e.toString()).join(',');
    return v.toString();
  }

  static TagListSniff _sniffDelimited(String content) {
    final lines = const LineSplitter().convert(content).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return TagListSniff.empty();

    final delimiter = _guessDelimiter(lines.take(SniffLimits.delimiterProbeLines).toList());
    if (delimiter == null) {
      // No structure at all → one tag per line.
      final rows = lines.map((l) => [l.trim()]).toList();
      return _finish(
        format: TagListFormat.plainText,
        columns: const [TagColumn('0', 'tag')],
        mapping: const TagColumnMapping(name: '0'),
        rows: rows,
        hasHeader: false,
      );
    }

    final rows = <List<String>>[];
    for (final line in lines) {
      rows.add(parseCsvLine(line, delimiter));
    }
    final first = rows.first;
    final hasHeader = first.any((c) => _isHeaderWord(c));
    final headers = hasHeader ? first.map((c) => c.trim()).toList() : null;
    final dataRows = hasHeader ? rows.sublist(1) : rows;
    if (dataRows.isEmpty) return TagListSniff.empty();

    final width = dataRows.take(50).fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final columns = List.generate(width, (i) {
      final label = (headers != null && i < headers.length && headers[i].isNotEmpty)
          ? headers[i]
          : 'Column ${i + 1}';
      return TagColumn('$i', label);
    });

    TagColumnMapping mapping;
    if (headers != null) {
      final byName = _guessMappingFromHeaders(headers);
      mapping = TagColumnMapping(
        name: _indexOfHeader(headers, byName.name),
        category: _indexOfHeader(headers, byName.category),
        count: _indexOfHeader(headers, byName.count),
        aliases: _indexOfHeader(headers, byName.aliases),
      );
      if (mapping.name == null) mapping = _guessMappingPositional(dataRows, width);
    } else {
      mapping = _guessMappingPositional(dataRows, width);
    }

    return _finish(
      format: TagListFormat.csv,
      columns: columns,
      mapping: mapping,
      rows: dataRows,
      hasHeader: hasHeader,
      delimiter: delimiter,
    );
  }

  static String? _indexOfHeader(List<String> headers, String? header) {
    if (header == null) return null;
    final i = headers.indexOf(header);
    return i < 0 ? null : '$i';
  }

  static bool _isHeaderWord(String cell) {
    final v = cell.trim().toLowerCase();
    return _nameHeaders.contains(v) ||
        _categoryHeaders.contains(v) ||
        _countHeaders.contains(v) ||
        _aliasHeaders.contains(v) ||
        _ignoredHeaders.contains(v);
  }

  /// Maps header names (or JSON keys) to roles by vocabulary.
  static TagColumnMapping _guessMappingFromHeaders(List<String> headers) {
    String? name, category, count, aliases;
    for (final h in headers) {
      final v = h.trim().toLowerCase();
      if (name == null && _nameHeaders.contains(v)) {
        name = h;
      } else if (category == null && _categoryHeaders.contains(v)) {
        category = h;
      } else if (count == null && _countHeaders.contains(v)) {
        count = h;
      } else if (aliases == null && _aliasHeaders.contains(v)) {
        aliases = h;
      }
    }
    return TagColumnMapping(name: name, category: category, count: count, aliases: aliases);
  }

  /// Header-less layout guess. The a1111 layout is `name,category,count,aliases`;
  /// two columns are `name,count` when the second is numeric, else `name,category`.
  static TagColumnMapping _guessMappingPositional(List<List<String>> rows, int width) {
    if (width <= 1) return const TagColumnMapping(name: '0');
    bool numericCol(int i) {
      var seen = 0, numeric = 0;
      for (final r in rows.take(30)) {
        if (i >= r.length || r[i].trim().isEmpty) continue;
        seen++;
        if (int.tryParse(r[i].trim()) != null) numeric++;
      }
      return seen > 0 && numeric == seen;
    }

    if (width == 2) {
      return numericCol(1)
          ? const TagColumnMapping(name: '0', count: '1')
          : const TagColumnMapping(name: '0', category: '1');
    }
    // 3+ columns
    final c1 = numericCol(1), c2 = numericCol(2);
    if (c1 && c2) {
      return TagColumnMapping(name: '0', category: '1', count: '2', aliases: width > 3 ? '3' : null);
    }
    if (!c1 && c2) {
      // textual category then count
      return TagColumnMapping(name: '0', category: '1', count: '2', aliases: width > 3 ? '3' : null);
    }
    if (c1 && !c2) {
      return TagColumnMapping(name: '0', count: '1', aliases: '2');
    }
    return TagColumnMapping(name: '0', aliases: width > 3 ? '3' : null);
  }

  static String? _guessDelimiter(List<String> lines) {
    const candidates = [',', '\t', ';', '|'];
    final scores = <String, int>{for (final c in candidates) c: 0};
    for (final line in lines) {
      var inQuotes = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes && scores.containsKey(ch)) {
          scores[ch] = scores[ch]! + 1;
        }
      }
    }
    String? best;
    var bestScore = 0;
    for (final e in scores.entries) {
      if (e.value > bestScore) {
        best = e.key;
        bestScore = e.value;
      }
    }
    // Require the delimiter on most probed lines, else it's just prose.
    if (best == null || bestScore < (lines.length * 0.6).ceil()) return null;
    return best;
  }

  /// RFC 4180-style field splitter: quoted fields may contain the delimiter
  /// and `""` escapes a quote. Leading/trailing whitespace is trimmed.
  static List<String> parseCsvLine(String line, String delimiter) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        fields.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString().trim());
    return fields;
  }

  static TagListSniff _finish({
    required TagListFormat format,
    required List<TagColumn> columns,
    required TagColumnMapping mapping,
    required List<List<String>> rows,
    required bool hasHeader,
    String delimiter = ',',
  }) {
    final categoryValues = <String>{};
    final histogram = <int, int>{for (final t in countLadder) t: 0};
    final catIdx = _colIndex(columns, mapping.category);
    final countIdx = _colIndex(columns, mapping.count);
    for (final r in rows) {
      if (catIdx != null && catIdx < r.length && categoryValues.length < categoryValueLimit) {
        final v = r[catIdx].trim().toLowerCase();
        if (v.isNotEmpty) categoryValues.add(v);
      }
      final c = (countIdx != null && countIdx < r.length) ? (int.tryParse(r[countIdx].trim()) ?? 0) : 0;
      for (final t in countLadder) {
        if (c >= t) histogram[t] = histogram[t]! + 1;
      }
    }
    return TagListSniff(
      format: format,
      delimiter: delimiter,
      hasHeader: hasHeader,
      columns: columns,
      mapping: mapping,
      rows: rows,
      categoryValues: categoryValues.toList()..sort(),
      guessedProfile: TagSiteProfile.guess(categoryValues),
      countHistogram: histogram,
    );
  }

  static int? _colIndex(List<TagColumn> columns, String? key) {
    if (key == null) return null;
    final i = columns.indexWhere((c) => c.key == key);
    return i < 0 ? null : i;
  }

  // ── Parse ────────────────────────────────────────────────────────────

  static TagImportResult parse(TagListSniff sniff, TagImportOptions options) {
    final nameIdx = _colIndex(sniff.columns, options.mapping.name);
    final catIdx = _colIndex(sniff.columns, options.mapping.category);
    final countIdx = _colIndex(sniff.columns, options.mapping.count);
    final aliasIdx = _colIndex(sniff.columns, options.mapping.aliases);

    final byName = <String, DanbooruTag>{};
    final order = <String>[];
    var below = 0, byCategory = 0, invalid = 0, dup = 0, empty = 0;

    for (final row in sniff.rows) {
      if (nameIdx == null || nameIdx >= row.length) {
        empty++;
        continue;
      }
      final rawName = row[nameIdx].trim();
      if (rawName.isEmpty) {
        empty++;
        continue;
      }
      final name = normalizeTagName(rawName, underscoresToSpaces: options.underscoresToSpaces);
      if (name.isEmpty) {
        empty++;
        continue;
      }

      final count = (countIdx != null && countIdx < row.length) ? (int.tryParse(row[countIdx].trim()) ?? 0) : 0;
      if (count < options.minCount) {
        below++;
        continue;
      }

      var category = options.defaultCategory;
      if (catIdx != null && catIdx < row.length) {
        final resolved = options.resolveCategory(row[catIdx]);
        if (resolved == TagCategories.invalid) {
          invalid++;
          continue;
        }
        if (resolved == null) {
          // "skip" in a custom map
          byCategory++;
          continue;
        }
        category = resolved;
      }
      if (options.includeCategories != null && !options.includeCategories!.contains(category)) {
        byCategory++;
        continue;
      }

      final aliases = <String>[];
      if (options.includeAliases && aliasIdx != null && aliasIdx < row.length) {
        for (final a in row[aliasIdx].split(',')) {
          final n = normalizeTagName(a, underscoresToSpaces: options.underscoresToSpaces);
          if (n.isEmpty || n.toLowerCase() == name.toLowerCase() || aliases.contains(n)) continue;
          aliases.add(n);
        }
      }

      final key = name.toLowerCase();
      final existing = byName[key];
      if (existing != null) {
        dup++;
        final merged = <String>[...existing.aliases];
        for (final a in aliases) {
          if (!merged.contains(a)) merged.add(a);
        }
        byName[key] = existing.copyWith(
          count: existing.count >= count ? existing.count : count,
          aliases: merged,
        );
        continue;
      }
      byName[key] = DanbooruTag(
        tag: name,
        count: count,
        typeName: category,
        aliases: aliases,
        sourceId: options.sourceId,
      );
      order.add(key);
    }

    final tags = order.map((k) => byName[k]!).toList();
    return TagImportResult(
      tags: tags,
      totalRows: sniff.rows.length,
      skippedBelowMin: below,
      skippedByCategory: byCategory,
      skippedInvalid: invalid,
      skippedDuplicate: dup,
      skippedEmpty: empty,
    );
  }

  /// Trims, drops wrapping quotes, collapses whitespace, and (optionally)
  /// turns booru underscores into the spaces NovelAI prompts use. Emoticon
  /// tags (`^_^`, `>_<`, `0_0`) keep their underscores: anything of three
  /// characters or fewer is left alone, matching the bundled list.
  static String normalizeTagName(String raw, {required bool underscoresToSpaces}) {
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1).trim();
    if (s.isEmpty) return s;
    if (underscoresToSpaces && s.length > 3 && s.contains('_')) {
      s = s.replaceAll('_', ' ');
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class SniffLimits {
  SniffLimits._();
  static const int delimiterProbeLines = 25;
}

enum TagListFormat { csv, jsonObjects, jsonStrings, jsonMap, plainText, unknown }

/// A selectable column: [key] is what the mapping stores (a CSV index as a
/// string, or a JSON key); [label] is what the UI shows.
class TagColumn {
  final String key;
  final String label;
  const TagColumn(this.key, this.label);
}

class TagColumnMapping {
  final String? name;
  final String? category;
  final String? count;
  final String? aliases;

  const TagColumnMapping({this.name, this.category, this.count, this.aliases});

  TagColumnMapping copyWith({
    String? Function()? name,
    String? Function()? category,
    String? Function()? count,
    String? Function()? aliases,
  }) {
    return TagColumnMapping(
      name: name != null ? name() : this.name,
      category: category != null ? category() : this.category,
      count: count != null ? count() : this.count,
      aliases: aliases != null ? aliases() : this.aliases,
    );
  }
}

class TagListSniff {
  final TagListFormat format;
  final String delimiter;
  final bool hasHeader;
  final List<TagColumn> columns;
  final TagColumnMapping mapping;

  /// Every data row (post-header), as strings per column. Held in full so
  /// [TagListParser.parse] never re-reads the file when options change.
  final List<List<String>> rows;

  /// Distinct raw category values (lower-cased), capped, for the custom map UI.
  final List<String> categoryValues;
  final TagSiteProfile guessedProfile;

  /// threshold → number of rows with count ≥ threshold, over [TagListParser.countLadder].
  final Map<int, int> countHistogram;

  const TagListSniff({
    required this.format,
    required this.delimiter,
    required this.hasHeader,
    required this.columns,
    required this.mapping,
    required this.rows,
    required this.categoryValues,
    required this.guessedProfile,
    required this.countHistogram,
  });

  factory TagListSniff.empty() => const TagListSniff(
        format: TagListFormat.unknown,
        delimiter: ',',
        hasHeader: false,
        columns: [],
        mapping: TagColumnMapping(),
        rows: [],
        categoryValues: [],
        guessedProfile: TagSiteProfile.danbooru,
        countHistogram: {},
      );

  bool get isEmpty => rows.isEmpty;
  List<List<String>> get sampleRows => rows.take(TagListParser.sampleRowLimit).toList();

  /// Same shape, different rows — used to run [TagListParser.parse] over just
  /// the sample for a live preview.
  TagListSniff withRows(List<List<String>> newRows) => TagListSniff(
        format: format,
        delimiter: delimiter,
        hasHeader: hasHeader,
        columns: columns,
        mapping: mapping,
        rows: newRows,
        categoryValues: categoryValues,
        guessedProfile: guessedProfile,
        countHistogram: countHistogram,
      );

  /// Whether a count column is mapped (drives whether the threshold UI is shown).
  bool get hasCounts => mapping.count != null;
  bool get hasCategories => mapping.category != null;

  /// Whether any raw category value is numeric — i.e. a site profile matters.
  bool get hasNumericCategories => categoryValues.any((v) => int.tryParse(v) != null);
}

class TagImportOptions {
  final String sourceId;
  final TagColumnMapping mapping;
  final TagSiteProfile profile;

  /// Raw (lower-cased) category value → app category, or null to skip that
  /// value. Consulted before [profile] so a custom map can override a code.
  final Map<String, String?> customCategoryMap;
  final String defaultCategory;
  final int minCount;

  /// null = keep every category.
  final Set<String>? includeCategories;
  final bool includeAliases;
  final bool underscoresToSpaces;

  const TagImportOptions({
    required this.sourceId,
    required this.mapping,
    this.profile = TagSiteProfile.danbooru,
    this.customCategoryMap = const {},
    this.defaultCategory = TagCategories.general,
    this.minCount = 0,
    this.includeCategories,
    this.includeAliases = true,
    this.underscoresToSpaces = true,
  });

  /// Resolves one raw category cell. Returns [TagCategories.invalid] for
  /// booru-invalid rows, null when a custom map says "skip", and
  /// [defaultCategory] when the value is unrecognised.
  String? resolveCategory(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return defaultCategory;
    if (customCategoryMap.containsKey(v)) return customCategoryMap[v];
    final n = int.tryParse(v);
    if (n != null) {
      return profile.codes[n] ?? defaultCategory;
    }
    return TagCategories.fromLabel(v) ?? defaultCategory;
  }
}

class TagImportResult {
  final List<DanbooruTag> tags;
  final int totalRows;
  final int skippedBelowMin;
  final int skippedByCategory;
  final int skippedInvalid;
  final int skippedDuplicate;
  final int skippedEmpty;

  const TagImportResult({
    required this.tags,
    required this.totalRows,
    required this.skippedBelowMin,
    required this.skippedByCategory,
    required this.skippedInvalid,
    required this.skippedDuplicate,
    required this.skippedEmpty,
  });

  int get imported => tags.length;
}
