import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/tag_source.dart';
import 'kv_store.dart';
import 'tag_service.dart' show DanbooruTag;

/// Per-tag user state for tags that live in an imported source (favourite
/// flag, example images). Bundled tags keep this in-record in the bundled
/// file; imported tags keep it here so re-importing an updated list never
/// loses it.
class TagUserState {
  final bool favorite;
  final List<String> examples;

  const TagUserState({this.favorite = false, this.examples = const []});

  bool get isEmpty => !favorite && examples.isEmpty;

  TagUserState copyWith({bool? favorite, List<String>? examples}) =>
      TagUserState(favorite: favorite ?? this.favorite, examples: examples ?? this.examples);

  Map<String, dynamic> toJson() => {'favorite': favorite, 'examples': examples};

  factory TagUserState.fromJson(Map<String, dynamic> json) => TagUserState(
        favorite: json['favorite'] as bool? ?? false,
        examples: (json['examples'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      );
}

/// A source plus its tags — the on-disk file shape and the `.vpack` entry.
class TagSourceBundle {
  final TagSource source;
  final List<DanbooruTag> tags;

  const TagSourceBundle({required this.source, required this.tags});

  Map<String, dynamic> toJson() => {
        'source': source.toJson(),
        'tags': tags.map(_tagToJson).toList(),
      };

  factory TagSourceBundle.fromJson(Map<String, dynamic> json) {
    final source = TagSource.fromJson(json['source'] as Map<String, dynamic>);
    final tags = (json['tags'] as List<dynamic>? ?? const [])
        .map((e) => DanbooruTag.fromJson(e as Map<String, dynamic>).copyWith(sourceId: () => source.id))
        .toList();
    return TagSourceBundle(source: source.copyWith(tagCount: tags.length), tags: tags);
  }

  static Map<String, dynamic> _tagToJson(DanbooruTag t) => {
        'tag': t.tag,
        'count': t.count,
        'type_name': t.typeName,
        if (t.aliases.isNotEmpty) 'aliases': t.aliases,
      };

  static String encode(TagSourceBundle b) => jsonEncode(b.toJson());
  static TagSourceBundle decode(String s) => TagSourceBundle.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// Storage for imported tag lists.
///
/// Layout under [sourcesDir] (web: the same records in SharedPreferences via
/// [KvStore]):
/// - `tag_sources.json` — ordered manifest of [TagSource]s; order = priority
/// - `<id>.json` — one [TagSourceBundle] per source
/// - `user_tag_state.json` — favourites / examples for imported tags
///
/// This class never touches the bundled Danbooru list. `TagService` merges
/// the enabled sources into its lookup view and asks this class to persist
/// user state for tags that are not bundled.
class TagSourceService {
  final String sourcesDir;

  List<TagSource> _sources = [];
  final Map<String, List<DanbooruTag>> _tags = {};
  Map<String, TagUserState> _userState = {};
  bool _loaded = false;

  static const String _prefsManifest = 'tag_sources_manifest';
  static const String _prefsUserState = 'tag_sources_user_state';
  static String _prefsSource(String id) => 'tag_source_$id';

  TagSourceService({required this.sourcesDir});

  String get _manifestPath => p.join(sourcesDir, 'tag_sources.json');
  String get _userStatePath => p.join(sourcesDir, 'user_tag_state.json');
  String _sourcePath(String id) => p.join(sourcesDir, '$id.json');

  bool get isLoaded => _loaded;
  List<TagSource> get sources => List.unmodifiable(_sources);
  List<TagSource> get enabledSources => _sources.where((s) => s.enabled).toList();
  TagSource? byId(String id) => _sources.where((s) => s.id == id).firstOrNull;
  TagSource? byName(String name) =>
      _sources.where((s) => s.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull;
  List<DanbooruTag> tagsOf(String id) => _tags[id] ?? const [];
  int get totalEnabledTags => enabledSources.fold(0, (n, s) => n + tagsOf(s.id).length);

  // ── Load / save ──────────────────────────────────────────────────────

  Future<void> load() async {
    _sources = [];
    _tags.clear();
    try {
      final raw = await KvStore.readString(path: _manifestPath, prefsKey: _prefsManifest);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        _sources = list.map((e) => TagSource.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Error loading tag source manifest: $e');
    }

    final missing = <String>[];
    for (final src in _sources) {
      try {
        final raw = await KvStore.readString(path: _sourcePath(src.id), prefsKey: _prefsSource(src.id));
        if (raw == null) {
          missing.add(src.id);
          continue;
        }
        final bundle = await compute(TagSourceBundle.decode, raw);
        _tags[src.id] = bundle.tags;
      } catch (e) {
        debugPrint('Error loading tag source ${src.id}: $e');
        missing.add(src.id);
      }
    }
    if (missing.isNotEmpty) {
      // A manifest entry whose file vanished is just noise — drop it.
      _sources.removeWhere((s) => missing.contains(s.id));
      await _saveManifest();
    }

    try {
      final raw = await KvStore.readString(path: _userStatePath, prefsKey: _prefsUserState);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _userState = map.map((k, v) => MapEntry(k, TagUserState.fromJson(v as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Error loading tag user state: $e');
    }
    _loaded = true;
  }

  Future<void> _saveManifest() async {
    try {
      await KvStore.writeString(
        path: _manifestPath,
        prefsKey: _prefsManifest,
        value: jsonEncode(_sources.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving tag source manifest: $e');
    }
  }

  Future<void> _saveSource(String id) async {
    final src = byId(id);
    if (src == null) return;
    try {
      final encoded = await compute(TagSourceBundle.encode, TagSourceBundle(source: src, tags: tagsOf(id)));
      await KvStore.writeString(path: _sourcePath(id), prefsKey: _prefsSource(id), value: encoded);
    } catch (e) {
      debugPrint('Error saving tag source $id: $e');
    }
  }

  Future<void> _saveUserState() async {
    try {
      final map = <String, dynamic>{};
      for (final e in _userState.entries) {
        if (!e.value.isEmpty) map[e.key] = e.value.toJson();
      }
      await KvStore.writeString(path: _userStatePath, prefsKey: _prefsUserState, value: jsonEncode(map));
    } catch (e) {
      debugPrint('Error saving tag user state: $e');
    }
  }

  // ── Source management ────────────────────────────────────────────────

  /// Adds a new source, or replaces the tags (and metadata) of an existing
  /// one with the same id. New sources go to the end of the priority order.
  Future<void> put(TagSource source, List<DanbooruTag> tags) async {
    final stamped = tags.map((t) => t.sourceId == source.id ? t : t.copyWith(sourceId: () => source.id)).toList();
    final record = source.copyWith(tagCount: stamped.length);
    final i = _sources.indexWhere((s) => s.id == record.id);
    if (i >= 0) {
      _sources[i] = record;
    } else {
      _sources.add(record);
    }
    _tags[record.id] = stamped;
    await _saveSource(record.id);
    await _saveManifest();
  }

  Future<void> remove(String id) async {
    _sources.removeWhere((s) => s.id == id);
    _tags.remove(id);
    try {
      await KvStore.remove(path: _sourcePath(id), prefsKey: _prefsSource(id));
    } catch (e) {
      debugPrint('Error deleting tag source $id: $e');
    }
    await _saveManifest();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i < 0) return;
    _sources[i] = _sources[i].copyWith(enabled: enabled);
    await _saveManifest();
  }

  Future<void> rename(String id, String name) async {
    final i = _sources.indexWhere((s) => s.id == id);
    if (i < 0 || name.trim().isEmpty) return;
    _sources[i] = _sources[i].copyWith(name: name.trim());
    await _saveManifest();
    await _saveSource(id);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _sources.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _sources.removeAt(oldIndex);
    _sources.insert(newIndex.clamp(0, _sources.length), item);
    await _saveManifest();
  }

  /// Removes a single tag from a source (Tag Library "delete" on an imported tag).
  Future<void> removeTag(String sourceId, String tagName) async {
    final list = _tags[sourceId];
    if (list == null) return;
    final lower = tagName.toLowerCase();
    list.removeWhere((t) => t.tag.toLowerCase() == lower);
    final i = _sources.indexWhere((s) => s.id == sourceId);
    if (i >= 0) _sources[i] = _sources[i].copyWith(tagCount: list.length);
    await _saveSource(sourceId);
    await _saveManifest();
  }

  TagSourceBundle bundle(String id) {
    final src = byId(id);
    if (src == null) throw StateError('Unknown tag source $id');
    return TagSourceBundle(source: src, tags: tagsOf(id));
  }

  // ── Per-tag user state (imported tags only) ──────────────────────────

  TagUserState? stateFor(String lowerName) => _userState[lowerName];

  Future<void> setFavorite(String tagName, bool favorite) async {
    final k = tagName.toLowerCase();
    _userState[k] = (_userState[k] ?? const TagUserState()).copyWith(favorite: favorite);
    await _saveUserState();
  }

  Future<void> addExample(String tagName, String path) async {
    final k = tagName.toLowerCase();
    final cur = _userState[k] ?? const TagUserState();
    _userState[k] = cur.copyWith(examples: [...cur.examples, path]);
    await _saveUserState();
  }

  Future<void> removeExample(String tagName, String path) async {
    final k = tagName.toLowerCase();
    final cur = _userState[k];
    if (cur == null) return;
    _userState[k] = cur.copyWith(examples: cur.examples.where((e) => e != path).toList());
    await _saveUserState();
  }

  Future<void> clearAllExamples() async {
    var changed = false;
    _userState = _userState.map((k, v) {
      if (v.examples.isNotEmpty) changed = true;
      return MapEntry(k, v.copyWith(examples: const []));
    });
    if (changed) await _saveUserState();
  }
}
