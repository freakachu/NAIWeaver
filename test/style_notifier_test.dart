import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/tools/providers/style_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String stylesPath;
  int changedCalls = 0;

  List<PromptStyle> seed() => [
        PromptStyle(name: 'Cinematic', prefix: 'cinematic, ', isDefault: true),
        PromptStyle(name: 'Anime', suffix: ', cel-shaded'),
        PromptStyle(name: 'Sketch', negativeContent: 'color'),
      ];

  StyleNotifier make({List<PromptStyle>? styles}) => StyleNotifier(
        tagService: TagService(filePath: p.join(tmp.path, 'tags.csv')),
        wildcardService: WildcardService(wildcardDir: p.join(tmp.path, 'wc')),
        initialStyles: styles ?? seed(),
        stylesFilePath: stylesPath,
        onStylesChanged: () => changedCalls++,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('style_notifier_test_');
    stylesPath = p.join(tmp.path, 'prompt_styles.json');
    changedCalls = 0;
  });

  tearDown(() async {
    // duplicateStyle persists without awaiting; on Windows the file may still
    // be open for a tick, so a failed cleanup must not fail the test.
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  List<String> names(StyleNotifier n) => n.state.styles.map((s) => s.name).toList();

  group('StyleNotifier.saveStyle (rename)', () {
    test('renaming keeps the count and drops the old name', () async {
      final n = make();
      n.selectStyle(n.state.styles[1]); // Anime
      n.nameController.text = 'Anime Redux';
      n.updateCurrentStyle(name: 'Anime Redux');
      await n.saveStyle();

      expect(n.state.styles.length, 3);
      expect(names(n), ['Cinematic', 'Anime Redux', 'Sketch']);
      expect(n.state.styles[1].suffix, ', cel-shaded');
      // The persisted file agrees with the in-memory list.
      final loaded = await StyleStorage.loadStyles(stylesPath);
      expect(loaded.map((s) => s.name), ['Cinematic', 'Anime Redux', 'Sketch']);
      expect(changedCalls, 1);
    });

    test('after a rename the new name is the key for the next save', () async {
      final n = make();
      n.selectStyle(n.state.styles[1]);
      n.nameController.text = 'Anime 2';
      n.updateCurrentStyle(name: 'Anime 2');
      await n.saveStyle();
      expect(n.state.originalName, 'Anime 2');
      expect(n.state.isModified, isFalse);

      // A second edit + save still replaces in place.
      n.nameController.text = 'Anime 3';
      n.updateCurrentStyle(name: 'Anime 3');
      await n.saveStyle();
      expect(names(n), ['Cinematic', 'Anime 3', 'Sketch']);
    });

    test('isDefault survives a rename', () async {
      final n = make();
      n.selectStyle(n.state.styles[0]); // Cinematic, isDefault
      n.nameController.text = 'Cine';
      n.updateCurrentStyle(name: 'Cine');
      await n.saveStyle();
      expect(n.state.styles[0].name, 'Cine');
      expect(n.state.styles[0].isDefault, isTrue);
      expect(n.state.styles.where((s) => s.isDefault).length, 1);
    });

    test('renaming onto another existing name takes the conflict path', () async {
      final n = make();
      n.selectStyle(n.state.styles[1]); // Anime
      n.nameController.text = 'Sketch';
      n.updateCurrentStyle(name: 'Sketch');
      expect(n.hasNameConflict(), isTrue);

      // The UI confirms the overwrite, then calls saveStyle: the edited entry
      // keeps its slot, the colliding one is removed — never two "Sketch".
      await n.saveStyle();
      expect(names(n), ['Cinematic', 'Sketch']);
      expect(n.state.styles[1].suffix, ', cel-shaded');
      expect(n.hasNameConflict(), isFalse);
    });

    test('an unchanged name is not a conflict', () {
      final n = make();
      n.selectStyle(n.state.styles[1]);
      expect(n.hasNameConflict(), isFalse);
    });

    test('content-only edits replace in place', () async {
      final n = make();
      n.selectStyle(n.state.styles[2]);
      n.updateCurrentStyle(content: 'monochrome, ');
      await n.saveStyle();
      expect(n.state.styles.length, 3);
      expect(n.state.styles[2].name, 'Sketch');
      // A negative-only style opens in negative mode, so the edit lands there.
      expect(n.state.styles[2].negativeContent, 'monochrome, ');
    });
  });

  group('StyleNotifier.saveAsNew', () {
    test('appends a copy and selects it', () async {
      final n = make();
      n.selectStyle(n.state.styles[1]); // Anime
      n.nameController.text = 'Anime Alt';
      n.updateCurrentStyle(name: 'Anime Alt');
      await n.saveAsNew();

      expect(n.state.styles.length, 4);
      expect(names(n), ['Cinematic', 'Anime', 'Sketch', 'Anime Alt']);
      expect(n.state.selectedStyle?.name, 'Anime Alt');
      expect(n.state.originalName, 'Anime Alt');
      expect(n.state.isModified, isFalse);
      // The original is untouched.
      expect(n.state.styles[1].suffix, ', cel-shaded');
    });

    test('an unchanged name gets suffixed (Copy), then (Copy 2)', () async {
      final n = make();
      n.selectStyle(n.state.styles[1]); // Anime
      await n.saveAsNew();
      expect(names(n).last, 'Anime (Copy)');
      expect(n.state.selectedStyle?.name, 'Anime (Copy)');

      n.selectStyle(n.state.styles[1]);
      await n.saveAsNew();
      expect(names(n).last, 'Anime (Copy 2)');
      expect(n.state.styles.length, 5);
    });

    test('isSelectedStyleSaved is false for a brand-new style until saved', () async {
      final n = make();
      n.createNewStyle();
      expect(n.isSelectedStyleSaved, isFalse);
      expect(n.state.selectedStyle?.name, 'NEW STYLE');
      n.updateCurrentStyle(content: 'x');
      await n.saveStyle();
      expect(n.isSelectedStyleSaved, isTrue);
      expect(n.state.styles.length, 4);
    });
  });

  group('StyleNotifier unique names', () {
    test('createNewStyle never collides with an existing name', () {
      final n = make(styles: [
        PromptStyle(name: 'NEW STYLE'),
        PromptStyle(name: 'NEW STYLE 2'),
      ]);
      n.createNewStyle();
      expect(n.state.selectedStyle?.name, 'NEW STYLE 3');
    });

    test('duplicateStyle picks the next free (Copy n) name', () {
      final n = make(styles: [
        PromptStyle(name: 'A'),
        PromptStyle(name: 'A (Copy)'),
      ]);
      n.duplicateStyle(n.state.styles[0]);
      expect(names(n), ['A', 'A (Copy)', 'A (Copy 2)']);
    });
  });
}
