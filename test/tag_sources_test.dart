import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/models/tag_category.dart';
import 'package:naiweaver/core/models/tag_source.dart';
import 'package:naiweaver/core/services/pack_service.dart';
import 'package:naiweaver/core/services/tag_service.dart';
import 'package:naiweaver/core/services/tag_source_service.dart';
import 'package:naiweaver/core/utils/tag_suggestion_helper.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

TagSource _src(String id, {String? name, bool enabled = true}) => TagSource(
      id: id,
      name: name ?? id,
      originFileName: '$id.csv',
      profile: 'e621',
      tagCount: 0,
      importedAt: DateTime(2026, 9, 7),
      enabled: enabled,
    );

DanbooruTag _t(String tag, int count, {String type = 'general', List<String> aliases = const []}) =>
    DanbooruTag(tag: tag, count: count, typeName: type, aliases: aliases);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('tag_sources_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> writeBundled(List<DanbooruTag> tags) async {
    final path = p.join(tmp.path, 'Tags', 'high-frequency-tags-list.json');
    await File(path).create(recursive: true);
    await File(path).writeAsString(jsonEncode(tags.map((t) => t.toJson()).toList()));
    return path;
  }

  group('TagSourceService', () {
    test('put / load round-trip keeps order, tags, source ids', () async {
      final dir = p.join(tmp.path, 'sources');
      final svc = TagSourceService(sourcesDir: dir);
      await svc.load();
      await svc.put(_src('a'), [_t('fox', 10, type: 'species'), _t('anthro', 20)]);
      await svc.put(_src('b'), [_t('wlop', 5, type: 'artist')]);

      final again = TagSourceService(sourcesDir: dir);
      await again.load();
      expect(again.sources.map((s) => s.id), ['a', 'b']);
      expect(again.sources.first.tagCount, 2);
      expect(again.tagsOf('a').map((t) => t.tag), ['fox', 'anthro']);
      expect(again.tagsOf('a').every((t) => t.sourceId == 'a'), isTrue);
      expect(File(p.join(dir, 'a.json')).existsSync(), isTrue);
    });

    test('replace, reorder, enable, rename, remove', () async {
      final svc = TagSourceService(sourcesDir: p.join(tmp.path, 'sources'));
      await svc.load();
      await svc.put(_src('a'), [_t('fox', 10)]);
      await svc.put(_src('b'), [_t('wlop', 5)]);

      await svc.put(_src('a'), [_t('fox', 11), _t('cat', 1)]);
      expect(svc.tagsOf('a').length, 2);
      expect(svc.byId('a')!.tagCount, 2);

      await svc.reorder(1, 0);
      expect(svc.sources.map((s) => s.id), ['b', 'a']);

      await svc.setEnabled('a', false);
      expect(svc.enabledSources.map((s) => s.id), ['b']);

      await svc.rename('b', 'Better');
      expect(svc.byName('better')!.id, 'b');

      await svc.removeTag('a', 'Cat');
      expect(svc.tagsOf('a').map((t) => t.tag), ['fox']);

      await svc.remove('a');
      expect(svc.byId('a'), isNull);
      expect(File(p.join(tmp.path, 'sources', 'a.json')).existsSync(), isFalse);
    });

    test('manifest entries whose file vanished are dropped on load', () async {
      final dir = p.join(tmp.path, 'sources');
      final svc = TagSourceService(sourcesDir: dir);
      await svc.load();
      await svc.put(_src('a'), [_t('fox', 10)]);
      await File(p.join(dir, 'a.json')).delete();
      final again = TagSourceService(sourcesDir: dir);
      await again.load();
      expect(again.sources, isEmpty);
    });

    test('user state (favourites/examples) persists separately from tags', () async {
      final dir = p.join(tmp.path, 'sources');
      final svc = TagSourceService(sourcesDir: dir);
      await svc.load();
      await svc.setFavorite('Fox', true);
      await svc.addExample('fox', '/x.png');
      final again = TagSourceService(sourcesDir: dir);
      await again.load();
      expect(again.stateFor('fox')!.favorite, isTrue);
      expect(again.stateFor('fox')!.examples, ['/x.png']);
    });

    test('badge abbreviation', () {
      expect(_src('x', name: 'e621').badge, 'E62');
      expect(_src('x', name: 'My Furry Tags').badge, 'MFT');
    });
  });

  group('TagService with sources', () {
    late TagSourceService sources;
    late TagService tagService;

    Future<void> boot() async {
      final bundledPath = await writeBundled([
        _t('solo', 4000000, aliases: ['ソロ']),
        _t('long hair', 3600000),
        _t('1girl', 5000000),
      ]);
      sources = TagSourceService(sourcesDir: p.join(tmp.path, 'sources'));
      await sources.load();
      await sources.put(_src('e621', name: 'e621'), [
        _t('solo', 1500000, aliases: ['female solo']),
        _t('canine', 900000, type: 'species'),
        _t('lore thing', 10, type: 'lore'),
        _t('sole female', 50000),
      ]);
      tagService = TagService(filePath: bundledPath, sourceService: sources);
      await tagService.loadTags();
    }

    test('merged view: bundled wins collisions but absorbs aliases; source tags searchable', () async {
      await boot();
      expect(tagService.isLoaded, isTrue);
      final solo = tagService.tags.firstWhere((t) => t.tag == 'solo');
      expect(solo.sourceId, isNull, reason: 'bundled record wins');
      expect(solo.count, 4000000);
      expect(solo.aliases, containsAll(['ソロ', 'female solo']));
      expect(tagService.tags.where((t) => t.tag == 'solo').length, 1);

      final canine = tagService.getSuggestions('can');
      expect(canine.map((t) => t.tag), contains('canine'));
      expect(canine.first.sourceId, 'e621');
      expect(tagService.sourceBadge('e621'), 'E62');
      expect(tagService.hasTag('canine'), isTrue);
      expect(tagService.bundledTags.any((t) => t.tag == 'canine'), isFalse);
    });

    test('prefix tier comes before substring tier, then aliases', () async {
      await boot();
      final r = tagService.getSuggestions('sol');
      expect(r.map((t) => t.tag).toList(), ['solo', 'sole female']);
      final alias = tagService.getSuggestions('female so');
      expect(alias.first.tag, 'solo');
      expect(alias.first.matchedAlias, 'female solo');
    });

    test('disabling a source removes its tags from lookup; bundled unaffected', () async {
      await boot();
      await sources.setEnabled('e621', false);
      tagService.refreshSources();
      expect(tagService.getSuggestions('can'), isEmpty);
      expect(tagService.hasTag('solo'), isTrue);
      expect(tagService.tags.firstWhere((t) => t.tag == 'solo').aliases, ['ソロ']);
    });

    test('favourite on an imported tag goes to the sidecar, not the bundled file', () async {
      await boot();
      final canine = tagService.tags.firstWhere((t) => t.tag == 'canine');
      await tagService.toggleFavorite(canine);
      expect(tagService.getFavorites(category: TagCategories.species).map((t) => t.tag), ['canine']);
      expect(sources.stateFor('canine')!.favorite, isTrue);
      final bundledJson = jsonDecode(await File(tagService.filePath).readAsString()) as List;
      expect(bundledJson.any((e) => e['tag'] == 'canine'), isFalse);

      // Survives re-import of the source.
      await sources.put(_src('e621', name: 'e621'), [_t('canine', 1, type: 'species')]);
      tagService.refreshSources();
      expect(tagService.tags.firstWhere((t) => t.tag == 'canine').isFavorite, isTrue);
    });

    test('/fs and /fl favourites shortcuts', () async {
      await boot();
      await tagService.toggleFavorite(tagService.tags.firstWhere((t) => t.tag == 'canine'));
      await tagService.toggleFavorite(tagService.tags.firstWhere((t) => t.tag == 'lore thing'));
      final species = TagSuggestionHelper.getSuggestions(
        text: '/fs',
        selection: const TextSelection.collapsed(offset: 3),
        tagService: tagService,
        supportFavorites: true,
      );
      expect(species.suggestions.map((t) => t.tag), ['canine']);
      final lore = TagSuggestionHelper.getSuggestions(
        text: '/fl',
        selection: const TextSelection.collapsed(offset: 3),
        tagService: tagService,
        supportFavorites: true,
      );
      expect(lore.suggestions.map((t) => t.tag), ['lore thing']);
    });

    test('deleting an imported tag removes it from its source file', () async {
      await boot();
      final canine = tagService.tags.firstWhere((t) => t.tag == 'canine');
      await tagService.deleteTag(canine);
      expect(tagService.hasTag('canine'), isFalse);
      expect(sources.tagsOf('e621').any((t) => t.tag == 'canine'), isFalse);
    });

    test('bundled edits still round-trip through the bundled file only', () async {
      await boot();
      await tagService.addTag(_t('brand new', 1));
      final bundledJson = jsonDecode(await File(tagService.filePath).readAsString()) as List;
      expect(bundledJson.any((e) => e['tag'] == 'brand new'), isTrue);
      expect(bundledJson.any((e) => e['tag'] == 'canine'), isFalse);
    });
  });

  group('pack round-trip', () {
    test('tag sources survive export/import', () {
      final bundle = TagSourceBundle(
        source: _src('e621', name: 'e621'),
        tags: [_t('canine', 900000, type: 'species', aliases: ['canid']), _t('anthro', 1)],
      );
      final bytes = PackService.exportPack(name: 'p', tagSources: [bundle]);
      final imported = PackService.importPack(bytes);
      expect(imported.manifest.tagSourceCount, 1);
      expect(imported.tagSources.length, 1);
      final round = imported.tagSources.single;
      expect(round.source.id, 'e621');
      expect(round.source.name, 'e621');
      expect(round.source.tagCount, 2);
      expect(round.tags.first.tag, 'canine');
      expect(round.tags.first.typeName, 'species');
      expect(round.tags.first.aliases, ['canid']);
      expect(round.tags.first.sourceId, 'e621');
    });
  });
}
