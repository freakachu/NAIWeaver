import 'package:flutter/foundation.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../utils/unique_file_path.dart';

/// Thin wrapper around the Storage Access Framework (SAF) for exporting images
/// to a user-chosen folder — including a removable SD card, which plain
/// `dart:io` `File` writes cannot reach under Android scoped storage (issue #13).
///
/// The export-folder preference stores either a plain filesystem path (internal
/// storage, written via `dart:io`) or a SAF tree URI (`content://…`, written
/// via this service). [isSafUri] distinguishes the two so callers can route a
/// write to the correct backend.
class SafExportService {
  SafExportService._();
  static final SafExportService instance = SafExportService._();

  final SafUtil _util = SafUtil();
  final SafStream _stream = SafStream();

  /// True if [path] is a SAF document-tree URI rather than a filesystem path.
  static bool isSafUri(String path) => path.startsWith('content://');

  /// SAF is only available on Android. Other platforms keep using `dart:io`.
  static bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True when [path] is a plain filesystem path that can no longer be written
  /// directly because the platform requires SAF for arbitrary folders.
  ///
  /// On Android 11+ (scoped storage) the app holds no broad storage permission,
  /// so a custom export folder stored as a bare filesystem path (e.g. carried
  /// over from an older version or a desktop session) is unreachable and a
  /// `dart:io` write would throw `PathAccessException`. Callers use this to
  /// surface the "re-pick it in Settings" guidance instead (issue #13).
  static bool isStalePlainPath(String path) =>
      path.isNotEmpty && isSupported && !isSafUri(path);

  /// Opens the system folder picker and requests a persistable write grant.
  /// Returns the chosen folder, or null if the user cancelled.
  ///
  /// The returned [SafFolder.uri] is a `content://…` string safe to store in
  /// preferences; the grant survives reboots thanks to `persistablePermission`.
  Future<SafFolder?> pickFolder() async {
    final dir = await _util.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (dir == null) return null;
    return SafFolder(uri: dir.uri, name: dir.name);
  }

  /// Whether we still hold a persisted write grant for [treeUri]. The user can
  /// revoke access (or pop the SD card), so callers should re-check before use.
  Future<bool> hasWriteAccess(String treeUri) async {
    try {
      return await _util.hasPersistedPermission(treeUri, checkWrite: true);
    } catch (_) {
      return false;
    }
  }

  /// Writes [bytes] as `<fileName>.png` into the SAF tree [treeUri].
  /// A `.png` extension is appended if not already present.
  ///
  /// Passes `overwrite: true` so re-exporting the same image replaces the
  /// existing file. Without it, `saf_stream` silently disambiguates to
  /// `name (1).png`, `name (2).png`, … — diverging from the plain-filesystem
  /// export path, which overwrites via `File.writeAsBytes`.
  Future<void> writePng(String treeUri, String fileName, Uint8List bytes) async {
    final name = fileName.toLowerCase().endsWith('.png') ? fileName : '$fileName.png';
    await _stream.writeFileBytes(treeUri, name, 'image/png', bytes, overwrite: true);
  }

  /// Creates (if needed) the folder chain [relativePath] — a `/`-joined
  /// string as produced by `expandSavePathPattern` — under [treeUri] and
  /// returns the URI of the innermost folder. An empty [relativePath] returns
  /// [treeUri] itself, so callers can pass the expanded pattern unconditionally.
  ///
  /// This is what lets the save-subfolder pattern (issue #27) apply to an
  /// SD-card / SAF export target, which has no filesystem path to `join`.
  Future<String> ensureSubfolder(String treeUri, String relativePath) async {
    final names = splitSubfolderPath(relativePath);
    if (names.isEmpty) return treeUri;
    final dir = await _util.mkdirp(treeUri, names);
    return dir.uri;
  }

  /// Next value for a `<digits>` counter inside the SAF folder [treeUri]: one
  /// more than the number of images already there — the SAF twin of
  /// `nextImageSequence`, using the same file-name rule so counters behave the
  /// same on both targets.
  Future<int> nextImageSequence(String treeUri) async {
    final entries = await _util.list(treeUri);
    var count = 0;
    for (final entry in entries) {
      if (entry.isDir) continue;
      if (isCountableImageName(entry.name)) count++;
    }
    return count + 1;
  }

  /// Splits a `/`- or `\`-separated relative path into folder names, dropping
  /// empty segments. `expandSavePathPattern` already strips `.`/`..`, but the
  /// split is defensive about them too so a SAF `mkdirp` can never be asked
  /// to walk upward.
  static List<String> splitSubfolderPath(String relativePath) {
    return relativePath
        .split(RegExp(r'[/\\]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
  }
}

/// A picked SAF folder: a persistable [uri] plus a human-readable [name].
class SafFolder {
  final String uri;
  final String name;
  const SafFolder({required this.uri, required this.name});
}
