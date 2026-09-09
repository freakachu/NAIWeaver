import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/models/nai_model.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/services/styles.dart';
import 'package:naiweaver/features/generation/services/model_settings_memory.dart';
import 'package:naiweaver/features/generation/services/session_snapshot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const v45 = NaiModelFamily.v45;
const v5 = NaiModelFamily.v5;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ModelSettingsMemory', () {
    test('remember / entryFor, immutable', () {
      const empty = ModelSettingsMemory.empty();
      final m = empty.remember(v5, (steps: 17, scale: 6));
      expect(empty.isEmpty, isTrue);
      expect(m.entryFor(v5), (steps: 17.0, scale: 6.0));
      expect(m.entryFor(v45), isNull);
    });

    test('JSON round-trip', () {
      final m = const ModelSettingsMemory.empty()
          .remember(v45, (steps: 23, scale: 5))
          .remember(v5, (steps: 17, scale: 6.5));
      final back = ModelSettingsMemory.decode(m.encode());
      expect(back.entryFor(v45), (steps: 23.0, scale: 5.0));
      expect(back.entryFor(v5), (steps: 17.0, scale: 6.5));
      expect(jsonDecode(m.encode()), {
        'v45': {'steps': 23.0, 'scale': 5.0},
        'v5': {'steps': 17.0, 'scale': 6.5},
      });
    });

    test('decode is tolerant of garbage, partial and foreign entries', () {
      expect(ModelSettingsMemory.decode(null).isEmpty, isTrue);
      expect(ModelSettingsMemory.decode('').isEmpty, isTrue);
      expect(ModelSettingsMemory.decode('not json').isEmpty, isTrue);
      expect(ModelSettingsMemory.decode('[1,2]').isEmpty, isTrue);
      final m = ModelSettingsMemory.decode(jsonEncode({
        'v5': {'steps': 17, 'scale': 6}, // ints, as JSON collapses them
        'v45': {'steps': 'x', 'scale': 5}, // non-numeric → skipped
        'v9': {'steps': 1, 'scale': 1}, // unknown family → skipped
        'v45x': 'nope',
      }));
      expect(m.entryFor(v5), (steps: 17.0, scale: 6.0));
      expect(m.entryFor(v45), isNull);
      expect(m.entries.length, 1);
    });
  });

  group('RenderSettingsCoordinator — per-model memory (Part A)', () {
    test('V4.5 → V5 → V4.5 restores each family\'s own values', () {
      final c = RenderSettingsCoordinator();
      // User tuned V4.5 to 28 / 5.
      c.rememberEdit(v45, (steps: 28, scale: 5));
      // Switch to V5: never used → keeps the current values.
      var shown = c.switchFamily(from: v45, to: v5, current: (steps: 28, scale: 5));
      expect(shown, (steps: 28.0, scale: 5.0));
      // Tune V5 to 17 / 7.
      c.rememberEdit(v5, (steps: 17, scale: 7));
      // Back to V4.5: its values come back.
      shown = c.switchFamily(from: v5, to: v45, current: (steps: 17, scale: 7));
      expect(shown, (steps: 28.0, scale: 5.0));
      // And to V5 again: 17 / 7.
      shown = c.switchFamily(from: v45, to: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
    });

    test('switching parks the on-screen values under the old family', () {
      final c = RenderSettingsCoordinator();
      c.switchFamily(from: v45, to: v5, current: (steps: 31, scale: 4));
      expect(c.memory.entryFor(v45), (steps: 31.0, scale: 4.0));
    });

    test('a never-used family keeps the current values, no model defaults', () {
      final c = RenderSettingsCoordinator();
      final shown = c.switchFamily(from: v45, to: v5, current: (steps: 40, scale: 3));
      expect(shown, (steps: 40.0, scale: 3.0));
      expect(shown.steps, isNot(NaiModelDefaults.v5.steps.toDouble()));
    });

    test('Full ↔ Curated of the same family is not a switch', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v5, (steps: 17, scale: 7));
      final shown = c.switchFamily(from: v5, to: v5, current: (steps: 20, scale: 8));
      expect(shown, (steps: 20.0, scale: 8.0));
    });
  });

  group('RenderSettingsCoordinator — style override (Part B)', () {
    final plain = PromptStyle(name: 'Plain');
    final fast = PromptStyle(name: 'Fast', steps: 12, scale: 4);
    final stepsOnly = PromptStyle(name: 'StepsOnly', steps: 15);

    test('selecting a style with an override applies it; deselecting restores', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v5, (steps: 17, scale: 7));

      var shown = c.syncStyleOverride(
          activeStyles: [plain, fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      expect(shown, (steps: 12.0, scale: 4.0));
      expect(c.overrideStyleName, 'Fast');
      expect(c.overrideActive, isTrue);

      shown = c.syncStyleOverride(
          activeStyles: [plain], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
      expect(c.overrideActive, isFalse);
    });

    test('without a per-model entry, restore falls back to the pre-override values', () {
      final c = RenderSettingsCoordinator();
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v45, current: (steps: 30, scale: 6));
      expect(shown, (steps: 12.0, scale: 4.0));
      shown = c.syncStyleOverride(activeStyles: const [], stylesEnabled: true, family: v45, current: shown);
      expect(shown, (steps: 30.0, scale: 6.0));
    });

    test('a partial override only touches the value it sets', () {
      final c = RenderSettingsCoordinator();
      final shown = c.syncStyleOverride(
          activeStyles: [stepsOnly], stylesEnabled: true, family: v5, current: (steps: 28, scale: 9));
      expect(shown, (steps: 15.0, scale: 9.0));
    });

    test('replacing an override style by another swaps values; by a plain one restores', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v5, (steps: 17, scale: 7));
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      shown = c.syncStyleOverride(activeStyles: [stepsOnly], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 15.0, scale: 4.0)); // scale untouched by StepsOnly
      expect(c.overrideStyleName, 'StepsOnly');
      shown = c.syncStyleOverride(activeStyles: [plain], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
    });

    test('styles disabled → no override, and lifting restores', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v5, (steps: 17, scale: 7));
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      expect(shown, (steps: 12.0, scale: 4.0));
      shown = c.syncStyleOverride(activeStyles: [fast], stylesEnabled: false, family: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
      expect(c.overrideActive, isFalse);
    });

    test('style override wins over per-model memory across a model switch', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v45, (steps: 28, scale: 5));
      c.rememberEdit(v5, (steps: 17, scale: 7));
      // Override active on V4.5.
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v45, current: (steps: 28, scale: 5));
      // Switch to V5: the style's numbers must NOT be parked as V4.5's.
      shown = c.switchFamily(from: v45, to: v5, current: shown);
      expect(c.memory.entryFor(v45), (steps: 28.0, scale: 5.0));
      expect(shown, (steps: 17.0, scale: 7.0));
      // The style is still active on V5 → its numbers show again.
      shown = c.syncStyleOverride(activeStyles: [fast], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 12.0, scale: 4.0));
      // Deselect on V5 → V5's own memory.
      shown = c.syncStyleOverride(activeStyles: const [], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
    });

    test('a user edit on top of an override survives toggling another style', () {
      final c = RenderSettingsCoordinator();
      c.rememberEdit(v5, (steps: 17, scale: 7));
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      expect(shown, (steps: 12.0, scale: 4.0));
      // User nudges steps 12 → 20 with Fast still selected, then toggles Plain.
      shown = c.syncStyleOverride(
          activeStyles: [fast, plain], stylesEnabled: true, family: v5, current: (steps: 20, scale: 4));
      expect(shown, (steps: 20.0, scale: 4.0), reason: 'the override is not re-applied');
      expect(c.overrideStyleName, 'Fast');
      // Deselecting Fast restores V5's own memory.
      shown = c.syncStyleOverride(activeStyles: [plain], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 17.0, scale: 7.0));
    });

    test('renaming the override style keeps it tracked under the new name', () {
      final c = RenderSettingsCoordinator();
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      c.renameOverrideStyle('Fast', 'Quick');
      expect(c.overrideStyleName, 'Quick');
      final quick = fast.copyWith(name: 'Quick');
      shown = c.syncStyleOverride(
          activeStyles: [quick], stylesEnabled: true, family: v5, current: (steps: 20, scale: 4));
      expect(shown, (steps: 20.0, scale: 4.0), reason: 'same style, not re-applied');
      shown = c.syncStyleOverride(activeStyles: const [], stylesEnabled: true, family: v5, current: shown);
      expect(c.overrideActive, isFalse);
    });

    test('a user edit while an override is active is what comes back on deselect', () {
      final c = RenderSettingsCoordinator();
      var shown = c.syncStyleOverride(
          activeStyles: [fast], stylesEnabled: true, family: v5, current: (steps: 17, scale: 7));
      c.rememberEdit(v5, (steps: 22, scale: 4)); // user nudged steps/scale
      shown = c.syncStyleOverride(activeStyles: const [], stylesEnabled: true, family: v5, current: shown);
      expect(shown, (steps: 22.0, scale: 4.0));
    });
  });

  group('persistence', () {
    SessionSnapshot snapshot({Map<String, dynamic>? memory}) => SessionSnapshot(
          prompt: '',
          negativePrompt: '',
          seed: '',
          width: 832,
          height: 1216,
          scale: 5,
          steps: 28,
          sampler: 'k_euler_ancestral',
          smea: false,
          smeaDyn: false,
          decrisper: false,
          randomizeSeed: true,
          autoPositioning: false,
          activeStyleNames: const [],
          isStyleEnabled: true,
          furryMode: false,
          model: NaiModel.v5Full,
          characters: const [],
          interactions: const [],
          directorReferences: const [],
          vibeTransfers: const [],
          modelSettingsMemory: memory,
        );

    test('SessionSnapshot round-trips the memory under its own key', () {
      final memory = const ModelSettingsMemory.empty()
          .remember(v45, (steps: 28, scale: 5))
          .remember(v5, (steps: 17, scale: 7));
      final json = jsonDecode(jsonEncode(snapshot(memory: memory.toJson()).toJson())) as Map<String, dynamic>;
      expect(json.containsKey('model_settings_memory'), isTrue);
      final back = SessionSnapshot.fromJson(json);
      final restored = ModelSettingsMemory.fromJson(back.modelSettingsMemory);
      expect(restored.entryFor(v45), (steps: 28.0, scale: 5.0));
      expect(restored.entryFor(v5), (steps: 17.0, scale: 7.0));
    });

    test('a snapshot without the key (pre-0.9.4) restores with no memory', () {
      final json = snapshot().toJson()..remove('model_settings_memory');
      final back = SessionSnapshot.fromJson(json);
      expect(back.modelSettingsMemory, isNull);
      expect(ModelSettingsMemory.fromJson(back.modelSettingsMemory).isEmpty, isTrue);
      // Garbage under the key is ignored too.
      final bad = SessionSnapshot.fromJson({...snapshot().toJson(), 'model_settings_memory': 'x'});
      expect(bad.modelSettingsMemory, isNull);
    });

    test('PreferencesService round-trips and clears the memory', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PreferencesService(prefs, const FlutterSecureStorage());
      expect(service.modelRenderSettings, '');

      final memory = const ModelSettingsMemory.empty().remember(v5, (steps: 17, scale: 6));
      await service.setModelRenderSettings(memory.encode());
      expect(ModelSettingsMemory.decode(service.modelRenderSettings).entryFor(v5), (steps: 17.0, scale: 6.0));
      expect(service.exportableSettings()['model_render_settings'], memory.encode());

      await service.setModelRenderSettings('{}');
      expect(service.modelRenderSettings, '');
    });
  });

  group('PromptStyle render override', () {
    test('missing JSON fields → null (no override)', () {
      final s = PromptStyle.fromJson({'name': 'a'});
      expect(s.steps, isNull);
      expect(s.scale, isNull);
      expect(s.hasRenderOverride, isFalse);
      expect(s.toJson().containsKey('steps'), isFalse);
    });

    test('round-trips, tolerating ints and rejecting junk', () {
      final s = PromptStyle.fromJson({'name': 'a', 'steps': 12, 'scale': 4.5});
      expect(s.steps, 12.0);
      expect(s.scale, 4.5);
      expect(s.hasRenderOverride, isTrue);
      final back = PromptStyle.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.steps, 12.0);
      expect(back.scale, 4.5);
      expect(PromptStyle.fromJson({'name': 'a', 'steps': 'lots'}).steps, isNull);
    });

    test('copyWith keeps, changes or clears the override', () {
      final s = PromptStyle(name: 'a', steps: 12, scale: 4);
      expect(s.copyWith(name: 'b').steps, 12);
      expect(s.copyWith(steps: 20).steps, 20);
      expect(s.copyWith(clearRenderOverride: true).hasRenderOverride, isFalse);
      expect(PromptStyle(name: 'a', steps: 15).hasRenderOverride, isTrue);
    });
  });
}
