import 'package:path/path.dart' as p;

import '../utils/filename_pattern.dart';
import '../utils/unique_file_path.dart';
import 'saf_export_service.dart';

/// Destination folder + filename base resolved from the pattern settings
/// (issue #27).
class SaveTarget {
  final String dir;
  final String base;
  const SaveTarget(this.dir, this.base);
}

/// Maps (base folder, expanded subfolder chain) to the final folder handle —
/// a joined path for a plain directory, a created child tree URI for SAF.
typedef JoinSubfolder = Future<String> Function(String base, String sub);

/// Yields the next `<digits>` value for the images already in [dir].
typedef CountImages = Future<int> Function(String dir);

/// Resolves where an image goes under [baseDir] from the save-subfolder and
/// filename patterns (issue #27). [baseDir] may be a plain directory or an
/// Android Storage Access Framework tree URI (`content://…`, e.g. an SD card
/// picked in Settings): the subfolder chain is joined or created accordingly
/// and `<digits>` counts the images already in the final folder, so counters
/// reset per subfolder on either kind of target.
///
/// The filename pattern needs [prompt] and [seed] (the same condition under
/// which the NAI-style default name applies) and falls back to
/// [fallbackBase] without them; the subfolder pattern still applies. Pass
/// [applyFilenamePattern] = false to keep [fallbackBase] as the name and only
/// resolve the folder — what the gallery's Export does for a file that
/// already has its name.
///
/// [joinSub] / [countImages] are injectable for tests; by default they pick
/// the plain-filesystem or SAF implementation from [baseDir].
Future<SaveTarget> resolvePatternedSaveTarget({
  required String baseDir,
  required String savePathPattern,
  required String filenamePattern,
  required String prompt,
  required String seed,
  required String fallbackBase,
  DateTime? savedAt,
  String albumName = '',
  bool applyFilenamePattern = true,
  JoinSubfolder? joinSub,
  CountImages? countImages,
}) async {
  final saf = SafExportService.isSafUri(baseDir);
  final join = joinSub ??
      (saf
          ? SafExportService.instance.ensureSubfolder
          : (String dir, String sub) async => p.join(dir, sub));
  final count = countImages ??
      (saf ? SafExportService.instance.nextImageSequence : nextImageSequence);

  final trimmedPrompt = prompt.trim();
  final fnPattern = applyFilenamePattern &&
          trimmedPrompt.isNotEmpty &&
          seed.isNotEmpty
      ? filenamePattern
      : '';
  if (savePathPattern.isEmpty && fnPattern.isEmpty) {
    return SaveTarget(baseDir, fallbackBase);
  }

  final at = savedAt ?? DateTime.now();
  var dirPath = baseDir;
  final sub = expandSavePathPattern(
      savePathPattern,
      FilenamePatternContext(
          prompt: trimmedPrompt, seed: seed, savedAt: at, albumName: albumName));
  if (sub.isNotEmpty) dirPath = await join(dirPath, sub);

  var base = fallbackBase;
  if (fnPattern.isNotEmpty) {
    // Only pay for a directory listing when the pattern actually counts.
    final seq = fnPattern.contains('<digits') ? await count(dirPath) : 1;
    final expanded = expandFilenamePattern(
        fnPattern,
        FilenamePatternContext(
            prompt: trimmedPrompt,
            seed: seed,
            savedAt: at,
            albumName: albumName,
            sequence: seq));
    if (expanded.isNotEmpty) base = expanded;
  }
  return SaveTarget(dirPath, base);
}
