/// One imported tag list ("source"): where it came from and how it is
/// surfaced. The tags themselves live in a sibling file keyed by [id]; this
/// record is the manifest entry.
///
/// The bundled Danbooru list is *not* a `TagSource` — it is always present
/// and always wins name collisions, so it needs no manifest entry.
class TagSource {
  final String id;
  final String name;
  final String originFileName;

  /// `TagSiteProfile.name` used at import time; informational only.
  final String profile;
  final bool enabled;
  final int tagCount;
  final DateTime importedAt;

  const TagSource({
    required this.id,
    required this.name,
    required this.originFileName,
    required this.profile,
    required this.tagCount,
    required this.importedAt,
    this.enabled = true,
  });

  TagSource copyWith({
    String? name,
    String? originFileName,
    String? profile,
    bool? enabled,
    int? tagCount,
    DateTime? importedAt,
  }) {
    return TagSource(
      id: id,
      name: name ?? this.name,
      originFileName: originFileName ?? this.originFileName,
      profile: profile ?? this.profile,
      enabled: enabled ?? this.enabled,
      tagCount: tagCount ?? this.tagCount,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  /// Short badge label shown next to suggestion chips: the first letters of
  /// the name's words (`e621` → `E62`, `My Furry Tags` → `MFT`).
  String get badge {
    final words = name
        .trim()
        .split(RegExp(r'[\s_\-]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return id.substring(0, id.length.clamp(0, 3)).toUpperCase();
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, w.length.clamp(0, 3)).toUpperCase();
    }
    return words.take(3).map((w) => w[0]).join().toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'origin_file_name': originFileName,
        'profile': profile,
        'enabled': enabled,
        'tag_count': tagCount,
        'imported_at': importedAt.toIso8601String(),
      };

  factory TagSource.fromJson(Map<String, dynamic> json) {
    return TagSource(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      originFileName: json['origin_file_name'] as String? ?? '',
      profile: json['profile'] as String? ?? 'danbooru',
      enabled: json['enabled'] as bool? ?? true,
      tagCount: json['tag_count'] as int? ?? 0,
      importedAt: DateTime.tryParse(json['imported_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Filesystem-safe id derived from a display name, with a time suffix so
  /// two imports of the same name never collide on disk.
  static String makeId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${slug.isEmpty ? 'list' : slug}_$stamp';
  }
}
