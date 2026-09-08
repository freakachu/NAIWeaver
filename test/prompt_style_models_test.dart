import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/models/nai_model.dart';
import 'package:naiweaver/core/services/pack_service.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/wildcard_service.dart';
import 'package:naiweaver/features/tools/providers/style_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaiModelFamily', () {
    test('every model maps to its family regardless of Full / Curated', () {
      expect(NaiModel.v45Full.family, NaiModelFamily.v45);
      expect(NaiModel.v45Curated.family, NaiModelFamily.v45);
      expect(NaiModel.v5Full.family, NaiModelFamily.v5);
      expect(NaiModel.v5Curated.family, NaiModelFamily.v5);
    });

    test('tryParse accepts ids, labels, enum names and wire ids', () {
      expect(NaiModelFamily.tryParse('v45'), NaiModelFamily.v45);
      expect(NaiModelFamily.tryParse('V4.5'), NaiModelFamily.v45);
      expect(NaiModelFamily.tryParse('v5'), NaiModelFamily.v5);
      expect(NaiModelFamily.tryParse('V5'), NaiModelFamily.v5);
      expect(NaiModelFamily.tryParse('nai-diffusion-5-curated'), NaiModelFamily.v5);
      expect(NaiModelFamily.tryParse('nai-diffusion-4-5-full'), NaiModelFamily.v45);
      expect(NaiModelFamily.tryParse('v6'), isNull);
      expect(NaiModelFamily.tryParse(''), isNull);
      expect(NaiModelFamily.tryParse(null), isNull);
    });
  });

  group('PromptStyle.models', () {
    test('missing field means every model (pre-0.9.4 files keep working)', () {
      final s = PromptStyle.fromJson({'name': 'Old', 'prefix': 'x, '});
      expect(s.models, PromptStyle.allModels);
      expect(s.targetsAllModels, isTrue);
      expect(s.supports(NaiModel.v45Full), isTrue);
      expect(s.supports(NaiModel.v5Full), isTrue);
    });

    test('empty, null and unknown lists also mean every model', () {
      expect(PromptStyle.fromJson({'name': 'a', 'models': []}).targetsAllModels, isTrue);
      expect(PromptStyle.fromJson({'name': 'a', 'models': null}).targetsAllModels, isTrue);
      expect(PromptStyle.fromJson({'name': 'a', 'models': ['v9', 42]}).targetsAllModels, isTrue);
      expect(PromptStyle.fromJson({'name': 'a', 'models': 'v5'}).targetsAllModels, isTrue);
    });

    test('a single family restricts the style; unknown entries are ignored', () {
      final v5 = PromptStyle.fromJson({'name': 'a', 'models': ['v5', 'bogus']});
      expect(v5.models, {NaiModelFamily.v5});
      expect(v5.supports(NaiModel.v5Curated), isTrue);
      expect(v5.supports(NaiModel.v45Full), isFalse);
      expect(v5.targetsAllModels, isFalse);
    });

    test('constructor treats an empty set as "all"', () {
      expect(PromptStyle(name: 'a', models: {}).targetsAllModels, isTrue);
    });

    test('toJson / fromJson round-trips the field as a list of ids', () {
      final original = PromptStyle(name: 'Cine', prefix: 'cinematic, ', models: {NaiModelFamily.v45});
      final json = original.toJson();
      expect(json['models'], ['v45']);
      final back = PromptStyle.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.models, {NaiModelFamily.v45});
      expect(back.name, 'Cine');
      expect(back.prefix, 'cinematic, ');

      final both = PromptStyle(name: 'b').toJson();
      expect((both['models'] as List).toSet(), {'v45', 'v5'});
    });

    test('copyWith keeps models unless overridden', () {
      final s = PromptStyle(name: 'a', models: {NaiModelFamily.v5});
      expect(s.copyWith(name: 'b').models, {NaiModelFamily.v5});
      expect(s.copyWith(models: {NaiModelFamily.v45}).models, {NaiModelFamily.v45});
    });
  });

  group('style filtering', () {
    final styles = [
      PromptStyle(name: 'Both'),
      PromptStyle(name: 'Only45', models: {NaiModelFamily.v45}),
      PromptStyle(name: 'Only5', models: {NaiModelFamily.v5}),
    ];

    test('stylesForModel keeps the current family and "both"', () {
      expect(stylesForModel(styles, NaiModel.v45Full).map((s) => s.name), ['Both', 'Only45']);
      expect(stylesForModel(styles, NaiModel.v5Curated).map((s) => s.name), ['Both', 'Only5']);
    });

    test('hiddenStyleCount counts the other family only', () {
      expect(hiddenStyleCount(styles, NaiModel.v45Full), 1);
      expect(hiddenStyleCount(styles, NaiModel.v5Full), 1);
      expect(hiddenStyleCount([PromptStyle(name: 'x')], NaiModel.v5Full), 0);
    });
  });

  group('reconcileActiveStylesForModel (model switch)', () {
    final styles = [
      PromptStyle(name: 'Both', isDefault: true),
      PromptStyle(name: 'Q45', prefix: 'q45, ', models: {NaiModelFamily.v45}),
      PromptStyle(name: 'Q5', prefix: 'q5, ', isDefault: true, models: {NaiModelFamily.v5}),
      PromptStyle(name: 'Art45', prefix: 'art, ', models: {NaiModelFamily.v45}),
      PromptStyle(name: 'Art5', prefix: 'art, ', models: {NaiModelFamily.v5}),
    ];

    List<String> to(NaiModel m, List<String> active, [List<PromptStyle>? list]) =>
        reconcileActiveStylesForModel(activeStyleNames: active, styles: list ?? styles, model: m);

    test('a V4.5-only style is swapped for the V5 default', () {
      expect(to(NaiModel.v5Full, ['Q45']), ['Both']);
    });

    test('the isDefault style that targets the new model wins, in list order', () {
      // 'Both' is the first isDefault that supports V5; Q5 is second.
      expect(to(NaiModel.v5Full, ['Art45']), ['Both']);
      // With no "both" default, the family-specific default is used.
      final onlyQ5Default = styles.map((s) => s.name == 'Both' ? s.copyWith(isDefault: false) : s).toList();
      expect(to(NaiModel.v5Full, ['Art45'], onlyQ5Default), ['Q5']);
    });

    test('a style that targets both is never replaced', () {
      expect(to(NaiModel.v5Full, ['Both']), ['Both']);
      expect(to(NaiModel.v45Curated, ['Both']), ['Both']);
    });

    test('a style already made for the new model is kept', () {
      expect(to(NaiModel.v5Full, ['Q5', 'Art5']), ['Q5', 'Art5']);
      expect(to(NaiModel.v45Full, ['Q45', 'Art45']), ['Q45', 'Art45']);
    });

    test('without a suitable default the style is dropped', () {
      final noDefaults = styles.map((s) => s.copyWith(isDefault: false)).toList();
      expect(to(NaiModel.v5Full, ['Q45'], noDefaults), isEmpty);
      expect(to(NaiModel.v5Full, ['Q45', 'Both'], noDefaults), ['Both']);
    });

    test('unknown names are left alone and nothing is listed twice', () {
      expect(to(NaiModel.v5Full, ['ghost', 'Q45', 'Art45']), ['ghost', 'Both']);
      expect(to(NaiModel.v5Full, ['Both', 'Q45']), ['Both']);
    });

    test('order is preserved', () {
      expect(to(NaiModel.v45Full, ['Art45', 'Both', 'Q45']), ['Art45', 'Both', 'Q45']);
    });
  });

  group('persistence', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('style_models_test_');
    });
    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // best effort
      }
    });

    test('StyleStorage round-trips models', () async {
      final path = p.join(tmp.path, 'prompt_styles.json');
      await StyleStorage.saveStyles(path, [
        PromptStyle(name: 'A', models: {NaiModelFamily.v5}),
        PromptStyle(name: 'B'),
      ]);
      final loaded = await StyleStorage.loadStyles(path);
      expect(loaded[0].models, {NaiModelFamily.v5});
      expect(loaded[1].targetsAllModels, isTrue);
    });

    test('a pre-0.9.4 styles file (no models key) loads as "both"', () async {
      final path = p.join(tmp.path, 'prompt_styles.json');
      await File(path).writeAsString(jsonEncode([
        {'name': 'Legacy', 'prefix': 'x, ', 'suffix': '', 'negativeContent': ''},
      ]));
      final loaded = await StyleStorage.loadStyles(path);
      expect(loaded.single.targetsAllModels, isTrue);
    });

    test('the bundled prompt_styles.json marks V4.5 and V5 entries', () {
      final raw = File('prompt_styles.json').readAsStringSync();
      final styles = (jsonDecode(raw) as List)
          .map((j) => PromptStyle.fromJson(j as Map<String, dynamic>))
          .toList();
      expect(styles, isNotEmpty);
      for (final s in styles) {
        if (s.name.contains('V4.5')) {
          expect(s.models, {NaiModelFamily.v45}, reason: s.name);
        } else if (s.name.contains('V5')) {
          expect(s.models, {NaiModelFamily.v5}, reason: s.name);
        } else {
          expect(s.targetsAllModels, isTrue, reason: s.name);
        }
      }
      // The hardcoded fallback names in StyleStorage still resolve.
      expect(styles.any((s) => s.name == 'Quality V4.5 (NAI Default)'), isTrue);
      expect(styles.any((s) => s.name == 'Light V4.5 - NAI'), isTrue);
    });

    test('pack export / import preserves models', () {
      final bytes = PackService.exportPack(name: 'test', styles: [
        PromptStyle(name: 'V5 only', suffix: ', x', models: {NaiModelFamily.v5}),
        PromptStyle(name: 'Everything'),
      ]);
      final imported = PackService.importPack(bytes);
      final byName = {for (final s in imported.styles) s.name: s};
      expect(byName['V5 only']!.models, {NaiModelFamily.v5});
      expect(byName['Everything']!.targetsAllModels, isTrue);
    });
  });

  group('StyleNotifier.toggleModelFamily', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('style_models_notifier_');
    });
    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // best effort
      }
    });

    StyleNotifier make() => StyleNotifier(
          tagService: TagService(filePath: p.join(tmp.path, 'tags.csv')),
          wildcardService: WildcardService(wildcardDir: p.join(tmp.path, 'wc')),
          initialStyles: [PromptStyle(name: 'A')],
          stylesFilePath: p.join(tmp.path, 'prompt_styles.json'),
          onStylesChanged: () {},
        );

    test('toggles off and on, but never clears the last family', () {
      final n = make();
      n.selectStyle(n.state.styles.first);
      expect(n.state.selectedStyle!.targetsAllModels, isTrue);

      n.toggleModelFamily(NaiModelFamily.v45);
      expect(n.state.selectedStyle!.models, {NaiModelFamily.v5});
      expect(n.state.isModified, isTrue);

      n.toggleModelFamily(NaiModelFamily.v5); // would leave nothing → ignored
      expect(n.state.selectedStyle!.models, {NaiModelFamily.v5});

      n.toggleModelFamily(NaiModelFamily.v45);
      expect(n.state.selectedStyle!.targetsAllModels, isTrue);
    });

    test('a new style defaults to both and the choice survives a save', () async {
      final n = make();
      n.createNewStyle();
      expect(n.state.selectedStyle!.targetsAllModels, isTrue);
      n.toggleModelFamily(NaiModelFamily.v45);
      n.updateCurrentStyle(content: 'v5 look, ');
      await n.saveStyle();
      final saved = await StyleStorage.loadStyles(p.join(tmp.path, 'prompt_styles.json'));
      expect(saved.last.models, {NaiModelFamily.v5});
      expect(saved.last.prefix, 'v5 look, ');
    });
  });
}
