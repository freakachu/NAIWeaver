import '../../../core/services/save_target_resolver.dart';
import '../../../core/utils/image_utils.dart';
import '../providers/gallery_notifier.dart';

/// Folder a gallery export of [item] should land in under [baseDir] — the
/// export folder picked in Settings, plain or a SAF tree (SD card) — once the
/// save-subfolder pattern (issue #27) is applied. The file keeps its gallery
/// name; only the folder is patterned, exactly as for a fresh render.
///
/// `<prompt>` / `<seed>` come from the image's own metadata when it has any,
/// `<album>` is the album the gallery is currently showing, and the date
/// tokens are the export time. Returns [baseDir] itself when no pattern is
/// set or it expands to nothing.
Future<String> galleryExportDir({
  required GalleryNotifier gallery,
  required GalleryItem item,
  required String baseDir,
  required String savePathPattern,
}) async {
  if (savePathPattern.isEmpty) return baseDir;
  var prompt = '';
  var seed = '';
  final comment = (await gallery.getMetadata(item))?['Comment'];
  if (comment != null) {
    final json = parseCommentJson(comment);
    prompt = (json?['prompt'] as String? ?? '').trim();
    seed = json?['seed']?.toString() ?? '';
  }
  final albumId = gallery.activeAlbumId;
  final albumName = albumId == null
      ? ''
      : gallery.albums
              .where((a) => a.id == albumId)
              .map((a) => a.name)
              .firstOrNull ??
          '';
  final target = await resolvePatternedSaveTarget(
    baseDir: baseDir,
    savePathPattern: savePathPattern,
    filenamePattern: '',
    prompt: prompt,
    seed: seed,
    fallbackBase: '',
    albumName: albumName,
    applyFilenamePattern: false,
  );
  return target.dir;
}
