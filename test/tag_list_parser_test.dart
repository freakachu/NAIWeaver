import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/models/tag_category.dart';
import 'package:naiweaver/core/services/tag_list_parser.dart';

TagImportOptions _opts(TagListSniff s, {
  TagSiteProfile? profile,
  int minCount = 0,
  Set<String>? include,
  bool spaces = true,
  bool aliases = true,
  Map<String, String?> custom = const {},
  TagColumnMapping? mapping,
}) =>
    TagImportOptions(
      sourceId: 'src',
      mapping: mapping ?? s.mapping,
      profile: profile ?? s.guessedProfile,
      minCount: minCount,
      includeCategories: include,
      underscoresToSpaces: spaces,
      includeAliases: aliases,
      customCategoryMap: custom,
    );

void main() {
  group('sniff — CSV', () {
    test('a1111 tag-autocomplete layout without header (danbooru)', () {
      const csv = '1girl,0,4114588,"1girls,sole_female"\n'
          'solo,0,3426446,"female_solo,solo_female"\n'
          'highres,5,3008413,"high_res,high_resolution,hires"\n'
          'hatsune_miku,4,100000,\n'
          'wlop,1,5000,\n';
      final s = TagListParser.sniff(csv);
      expect(s.format, TagListFormat.csv);
      expect(s.hasHeader, isFalse);
      expect(s.delimiter, ',');
      expect(s.mapping.name, '0');
      expect(s.mapping.category, '1');
      expect(s.mapping.count, '2');
      expect(s.mapping.aliases, '3');
      expect(s.rows.length, 5);
      expect(s.guessedProfile, TagSiteProfile.danbooru);
      expect(s.categoryValues, ['0', '1', '4', '5']);
      expect(s.countHistogram[0], 5);
      expect(s.countHistogram[10000], 4);
      expect(s.countHistogram[5000], 5);
    });

    test('e621 codes 6–8 flip the profile guess to e621', () {
      const csv = 'canine,5,900000,\nabsurd_res,7,800000,\nsome_story,8,10,\n';
      final s = TagListParser.sniff(csv);
      expect(s.guessedProfile, TagSiteProfile.e621);
    });

    test('codes ≥ 9 mean a merged danbooru+e621 list', () {
      const csv = '1girl,0,4114588,\nfox,12,50000,\nabsurd_res,14,80000,\n';
      final s = TagListParser.sniff(csv);
      expect(s.guessedProfile, TagSiteProfile.e621Merged);
    });

    test('header row in the app\'s own source-file order', () {
      const csv = 'tag,category,count,alias\n'
          '1girl,0,4974288,"女の子,女性"\n'
          'solo,0,4005860,"ソロ,solo"\n';
      final s = TagListParser.sniff(csv);
      expect(s.hasHeader, isTrue);
      expect(s.columns.map((c) => c.label), ['tag', 'category', 'count', 'alias']);
      expect(s.mapping.name, '0');
      expect(s.mapping.category, '1');
      expect(s.mapping.count, '2');
      expect(s.mapping.aliases, '3');
      expect(s.rows.length, 2);
    });

    test('e621 db_export header in a different column order', () {
      const csv = 'id,name,category,post_count\n1,anthro,0,2500000\n2,fox,5,600000\n3,lore_thing,8,4\n';
      final s = TagListParser.sniff(csv);
      expect(s.hasHeader, isTrue);
      expect(s.mapping.name, '1');
      expect(s.mapping.category, '2');
      expect(s.mapping.count, '3');
      expect(s.mapping.aliases, isNull);
      expect(s.guessedProfile, TagSiteProfile.e621);
    });

    test('semicolon and tab delimiters are detected', () {
      final semi = TagListParser.sniff('1girl;0;100\nsolo;0;90\n');
      expect(semi.delimiter, ';');
      expect(semi.mapping.count, '2');
      final tab = TagListParser.sniff('1girl\t0\t100\nsolo\t0\t90\n');
      expect(tab.delimiter, '\t');
    });

    test('two columns: name,count when numeric, name,category otherwise', () {
      expect(TagListParser.sniff('1girl,100\nsolo,90\n').mapping.count, '1');
      final cat = TagListParser.sniff('1girl,general\nwlop,artist\n');
      expect(cat.mapping.category, '1');
      expect(cat.mapping.count, isNull);
    });

    test('BOM + CRLF are tolerated', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('1girl,0,10,\r\nsolo,0,9,\r\n')]);
      final s = TagListParser.sniff(TagListParser.decodeBytes(bytes));
      expect(s.rows.length, 2);
      expect(s.rows.first.first, '1girl');
    });

    test('gzip-compressed input is transparently decoded', () {
      final plain = utf8.encode('1girl,0,10,\nsolo,0,9,\n');
      final gz = Uint8List.fromList(GZipEncoder().encode(plain));
      final text = TagListParser.decodeBytes(gz);
      expect(TagListParser.sniff(text).rows.length, 2);
    });

    test('quoted fields keep embedded delimiters and escaped quotes', () {
      final fields = TagListParser.parseCsvLine('a,"b,c","say ""hi""",d', ',');
      expect(fields, ['a', 'b,c', 'say "hi"', 'd']);
    });
  });

  group('sniff — JSON and text', () {
    test('array of objects maps keys by vocabulary', () {
      final json = jsonEncode([
        {'tag': 'long hair', 'count': 100, 'type_name': 'general', 'aliases': ['長髪']},
        {'tag': 'wlop', 'count': 5, 'type_name': 'artist', 'aliases': []},
      ]);
      final s = TagListParser.sniff(json);
      expect(s.format, TagListFormat.jsonObjects);
      expect(s.mapping.name, 'tag');
      expect(s.mapping.category, 'type_name');
      expect(s.mapping.count, 'count');
      expect(s.mapping.aliases, 'aliases');
      expect(s.hasNumericCategories, isFalse);
    });

    test('exported source bundle is read through its tags array', () {
      final json = jsonEncode({
        'source': {'id': 'x', 'name': 'X'},
        'tags': [
          {'tag': 'fox', 'count': 3, 'type_name': 'species'},
        ],
      });
      final s = TagListParser.sniff(json);
      expect(s.format, TagListFormat.jsonObjects);
      expect(s.rows.length, 1);
    });

    test('array of strings and name→count map', () {
      final strings = TagListParser.sniff(jsonEncode(['a', 'b']));
      expect(strings.format, TagListFormat.jsonStrings);
      expect(strings.rows.length, 2);
      final map = TagListParser.sniff(jsonEncode({'1girl': 10, 'solo': 5}));
      expect(map.format, TagListFormat.jsonMap);
      expect(map.mapping.count, '1');
      expect(map.countHistogram[10], 1);
    });

    test('plain text — one tag per line', () {
      final s = TagListParser.sniff('long hair\nblue eyes\n\nsmile\n');
      expect(s.format, TagListFormat.plainText);
      expect(s.rows.length, 3);
    });

    test('empty / whitespace input is empty', () {
      expect(TagListParser.sniff('   \n').isEmpty, isTrue);
    });
  });

  group('parse', () {
    const e621Csv = 'canine,5,900000,"canid"\n'
        'anthro,0,2500000,\n'
        'absurd_res,7,800000,"absurdres"\n'
        'some_story,8,10,\n'
        'broken_tag,6,999,\n'
        'wlop,1,5000,\n'
        'anthro,0,1,"anthropomorphic"\n'
        '^_^,0,50,\n';

    test('e621 profile: species/meta/lore mapped, invalid dropped, dupes merged', () {
      final s = TagListParser.sniff(e621Csv);
      final r = TagListParser.parse(s, _opts(s, profile: TagSiteProfile.e621));
      final byName = {for (final t in r.tags) t.tag: t};
      expect(byName['canine']!.typeName, TagCategories.species);
      expect(byName['absurd res']!.typeName, TagCategories.meta);
      expect(byName['some story']!.typeName, TagCategories.lore);
      expect(byName['wlop']!.typeName, TagCategories.artist);
      expect(byName.containsKey('broken tag'), isFalse);
      expect(r.skippedInvalid, 1);
      // duplicate anthro: keeps max count, unions aliases
      expect(r.skippedDuplicate, 1);
      expect(byName['anthro']!.count, 2500000);
      expect(byName['anthro']!.aliases, ['anthropomorphic']);
      expect(byName['^_^'], isNotNull, reason: 'emoticon tags keep underscores');
      expect(r.tags.every((t) => t.sourceId == 'src'), isTrue);
    });

    test('same file under the danbooru profile reads 5 as meta', () {
      final s = TagListParser.sniff(e621Csv);
      final r = TagListParser.parse(s, _opts(s, profile: TagSiteProfile.danbooru));
      final canine = r.tags.firstWhere((t) => t.tag == 'canine');
      expect(canine.typeName, TagCategories.meta);
      // 7 and 8 are unknown under danbooru → default category, not dropped
      expect(r.tags.firstWhere((t) => t.tag == 'absurd res').typeName, TagCategories.general);
    });

    test('minimum count and category filter', () {
      final s = TagListParser.sniff(e621Csv);
      final r = TagListParser.parse(
        s,
        _opts(s, profile: TagSiteProfile.e621, minCount: 100, include: {TagCategories.species, TagCategories.general}),
      );
      expect(r.tags.map((t) => t.tag).toSet(), {'canine', 'anthro'});
      expect(r.skippedBelowMin, 3); // some_story(10), duplicate anthro(1), ^_^(50)
      expect(r.skippedByCategory, 2); // absurd_res (meta), wlop (artist)
    });

    test('underscore handling and alias import can be switched off', () {
      final s = TagListParser.sniff(e621Csv);
      final r = TagListParser.parse(s, _opts(s, profile: TagSiteProfile.e621, spaces: false, aliases: false));
      expect(r.tags.any((t) => t.tag == 'absurd_res'), isTrue);
      expect(r.tags.every((t) => t.aliases.isEmpty), isTrue);
    });

    test('custom map overrides codes and can skip a value', () {
      final s = TagListParser.sniff(e621Csv);
      final r = TagListParser.parse(
        s,
        _opts(s, profile: TagSiteProfile.custom, custom: {
          '5': TagCategories.character,
          '0': TagCategories.general,
          '7': null,
          '8': TagCategories.lore,
          '6': TagCategories.invalid,
          '1': TagCategories.artist,
        }),
      );
      expect(r.tags.firstWhere((t) => t.tag == 'canine').typeName, TagCategories.character);
      expect(r.tags.any((t) => t.tag == 'absurd res'), isFalse);
      expect(r.skippedByCategory, 1);
    });

    test('textual categories resolve without a profile', () {
      final s = TagListParser.sniff('tag,category,count\nfox,Species,10\nwlop,artist,3\nmiku,char,2\n');
      final r = TagListParser.parse(s, _opts(s));
      expect(r.tags.map((t) => t.typeName), [TagCategories.species, TagCategories.artist, TagCategories.character]);
    });

    test('remapping columns is honoured', () {
      final s = TagListParser.sniff('10,1girl\n9,solo\n');
      // sniff guesses name=0 (non-numeric second col → category); user fixes it.
      final r = TagListParser.parse(s, _opts(s, mapping: const TagColumnMapping(name: '1', count: '0')));
      expect(r.tags.map((t) => t.tag), ['1girl', 'solo']);
      expect(r.tags.first.count, 10);
    });

    test('normalizeTagName', () {
      expect(TagListParser.normalizeTagName('long_hair', underscoresToSpaces: true), 'long hair');
      expect(TagListParser.normalizeTagName('"quoted_tag"', underscoresToSpaces: true), 'quoted tag');
      expect(TagListParser.normalizeTagName('>_<', underscoresToSpaces: true), '>_<');
      expect(TagListParser.normalizeTagName('0_0', underscoresToSpaces: true), '0_0');
      expect(TagListParser.normalizeTagName('  a   b ', underscoresToSpaces: true), 'a b');
    });
  });

  group('TagSiteProfile / TagCategories', () {
    test('guess', () {
      expect(TagSiteProfile.guess(['0', '1', '3', '4', '5']), TagSiteProfile.danbooru);
      expect(TagSiteProfile.guess(['0', '5', '7']), TagSiteProfile.e621);
      expect(TagSiteProfile.guess(['0', '12']), TagSiteProfile.e621Merged);
      expect(TagSiteProfile.guess(['general', 'artist']), TagSiteProfile.danbooru);
    });

    test('favourite shortcut letters round-trip for every real category with one', () {
      for (final c in TagCategories.all) {
        final letter = TagCategories.shortcutLetter(c);
        if (letter == null) continue;
        expect(TagCategories.fromShortcutLetter(letter), c);
      }
      expect(TagCategories.fromShortcutLetter('s'), TagCategories.species);
      expect(TagCategories.fromShortcutLetter('l'), TagCategories.lore);
    });
  });
}
