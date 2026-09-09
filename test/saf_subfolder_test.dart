import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/saf_export_service.dart';
import 'package:naiweaver/core/services/save_target_resolver.dart';
import 'package:naiweaver/core/utils/unique_file_path.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

/// In-memory stand-in for the SAF platform channel: records `mkdirp` calls and
/// serves canned directory listings, so the subfolder / `<digits>` logic that
/// backs the Android SD-card export can run under `flutter test`.
class _FakeSafUtil extends SafUtilPlatform {
  final List<List<String>> mkdirpCalls = [];
  final Map<String, List<SafDocumentFile>> listings = {};

  @override
  Future<SafDocumentFile> mkdirp(String uri, List<String> names) async {
    mkdirpCalls.add(names);
    return SafDocumentFile(
      uri: '$uri/${names.join('/')}',
      name: names.last,
      isDir: true,
      length: 0,
      lastModified: 0,
    );
  }

  @override
  Future<List<SafDocumentFile>> list(String uri) async =>
      listings[uri] ?? const [];
}

SafDocumentFile _entry(String name, {bool isDir = false}) => SafDocumentFile(
    uri: 'content://tree/x/$name',
    name: name,
    isDir: isDir,
    length: 1,
    lastModified: 0);

void main() {
  late _FakeSafUtil fake;

  setUp(() {
    fake = _FakeSafUtil();
    SafUtilPlatform.instance = fake;
  });

  group('splitSubfolderPath', () {
    test('splits on either separator and drops empty / dot segments', () {
      expect(SafExportService.splitSubfolderPath('2026/09/07'),
          ['2026', '09', '07']);
      expect(SafExportService.splitSubfolderPath(r'a\b//c/./..'),
          ['a', 'b', 'c']);
      expect(SafExportService.splitSubfolderPath(''), isEmpty);
    });
  });

  group('ensureSubfolder', () {
    test('returns the tree itself for an empty pattern without mkdirp',
        () async {
      final uri = await SafExportService.instance
          .ensureSubfolder('content://tree/root', '');
      expect(uri, 'content://tree/root');
      expect(fake.mkdirpCalls, isEmpty);
    });

    test('creates the chain under the tree and returns the innermost folder',
        () async {
      final uri = await SafExportService.instance
          .ensureSubfolder('content://tree/root', '2026/09/07');
      expect(fake.mkdirpCalls, [
        ['2026', '09', '07']
      ]);
      expect(uri, 'content://tree/root/2026/09/07');
    });
  });

  group('nextImageSequence (SAF)', () {
    test('counts images only, using the same rule as the filesystem counter',
        () async {
      fake.listings['content://tree/d'] = [
        _entry('a.png'),
        _entry('b.webp'),
        _entry('c.jpg'),
        _entry('c.canvas.png'), // canvas sidecar: excluded
        _entry('notes.txt'),
        _entry('sub', isDir: true),
      ];
      expect(
          await SafExportService.instance.nextImageSequence('content://tree/d'),
          4);
      expect(
          await SafExportService.instance.nextImageSequence('content://empty'),
          1);
    });
  });

  group('isCountableImageName', () {
    test('accepts image extensions case-insensitively and rejects sidecars',
        () {
      expect(isCountableImageName('x.PNG'), isTrue);
      expect(isCountableImageName('x.jpeg'), isTrue);
      expect(isCountableImageName('x.canvas.png'), isFalse);
      expect(isCountableImageName('x.json'), isFalse);
    });
  });

  group('resolvePatternedSaveTarget', () {
    final at = DateTime(2026, 9, 7, 14, 5, 9);

    test('SAF tree: creates the subfolder chain and counts <digits> in it',
        () async {
      fake.listings['content://tree/root/2026/09'] = [_entry('a.png'), _entry('b.png')];
      final t = await resolvePatternedSaveTarget(
        baseDir: 'content://tree/root',
        savePathPattern: '<year>/<month>',
        filenamePattern: '<digits:000>-<seed>',
        prompt: '1girl',
        seed: '42',
        fallbackBase: 'fallback',
        savedAt: at,
      );
      expect(t.dir, 'content://tree/root/2026/09');
      expect(t.base, '003-42');
      expect(fake.mkdirpCalls, [
        ['2026', '09']
      ]);
    });

    test('plain folder: joins the subfolder as a path (no SAF calls)', () async {
      final t = await resolvePatternedSaveTarget(
        baseDir: r'D:\out',
        savePathPattern: '<year>',
        filenamePattern: '',
        prompt: '1girl',
        seed: '42',
        fallbackBase: 'name',
        savedAt: at,
      );
      expect(t.dir.replaceAll('\\', '/'), 'D:/out/2026');
      expect(t.base, 'name');
      expect(fake.mkdirpCalls, isEmpty);
    });

    test('no patterns → base folder and fallback name untouched', () async {
      final t = await resolvePatternedSaveTarget(
        baseDir: 'content://tree/root',
        savePathPattern: '',
        filenamePattern: '',
        prompt: '1girl',
        seed: '42',
        fallbackBase: 'name',
      );
      expect(t.dir, 'content://tree/root');
      expect(t.base, 'name');
      expect(fake.mkdirpCalls, isEmpty);
    });

    test('folder-only mode keeps the name and works without prompt / seed '
        '(gallery export of an imported image)', () async {
      final t = await resolvePatternedSaveTarget(
        baseDir: 'content://tree/root',
        savePathPattern: '<year>/<prompt>/<month>',
        filenamePattern: '<seed>',
        prompt: '',
        seed: '',
        fallbackBase: 'keep-me',
        savedAt: at,
        applyFilenamePattern: false,
      );
      // The empty <prompt> segment is dropped; the chain still applies.
      expect(t.dir, 'content://tree/root/2026/09');
      expect(t.base, 'keep-me');
    });

    test('the filename pattern needs prompt and seed; the subfolder does not',
        () async {
      final t = await resolvePatternedSaveTarget(
        baseDir: 'content://tree/root',
        savePathPattern: '<year>',
        filenamePattern: '<seed>',
        prompt: '',
        seed: '',
        fallbackBase: 'fallback',
        savedAt: at,
      );
      expect(t.dir, 'content://tree/root/2026');
      expect(t.base, 'fallback');
    });
  });
}
