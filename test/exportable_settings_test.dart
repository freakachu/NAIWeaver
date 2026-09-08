import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PreferencesService> makeService(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs, const FlutterSecureStorage());
  }

  group('PreferencesService backup allowlist', () {
    test('exportableSettings includes allowlisted keys and excludes security/device keys', () async {
      final service = await makeService({
        // allowlisted
        'furry_mode': true,
        'app_locale': 'zh',
        'gallery_grid_columns': 4,
        'jukebox_volume': 0.4,
        'model_render_settings': '{"v5":{"steps":17,"scale":6}}',
        // excluded — security
        'pin_lock_hash': 'secret',
        'pin_biometric_enabled': true,
        // excluded — device local
        'window_x': 100.0,
        'custom_output_dir': '/Users/me/out',
        'export_folder_path': '/Users/me/exports',
      });

      final exported = service.exportableSettings();

      expect(exported['furry_mode'], true);
      expect(exported['app_locale'], 'zh');
      expect(exported['gallery_grid_columns'], 4);
      expect(exported['jukebox_volume'], 0.4);
      // Per-model steps / CFG memory travels with a backup.
      expect(exported['model_render_settings'], '{"v5":{"steps":17,"scale":6}}');

      // Security and device-local keys must never leak into a shareable backup.
      expect(exported.containsKey('pin_lock_hash'), isFalse);
      expect(exported.containsKey('pin_biometric_enabled'), isFalse);
      expect(exported.containsKey('window_x'), isFalse);
      expect(exported.containsKey('custom_output_dir'), isFalse);
      expect(exported.containsKey('export_folder_path'), isFalse);
    });

    test('importSettings round-trips and ignores non-allowlisted keys', () async {
      final service = await makeService({});

      await service.importSettings({
        'furry_mode': true,
        'app_locale': 'ja',
        'gallery_grid_columns': 6,
        'model_render_settings': '{"v45":{"steps":23,"scale":5}}',
        // not on the allowlist — must be ignored
        'pin_lock_hash': 'nope',
      });

      expect(service.furryMode, true);
      expect(service.locale, 'ja');
      expect(service.galleryGridColumns, 6);
      expect(service.modelRenderSettings, '{"v45":{"steps":23,"scale":5}}');
      // Re-export should not surface the ignored key.
      expect(service.exportableSettings().containsKey('pin_lock_hash'), isFalse);
    });

    test('importSettings coerces whole-number doubles back to double', () async {
      final service = await makeService({});

      // JSON collapses 1.0 to an int; the double getter would otherwise throw.
      await service.importSettings({
        'jukebox_volume': 1, // int, but stored as a double key
        'ref_last_strength': 0, // int
      });

      expect(service.jukeboxVolume, 1.0);
      expect(service.refLastStrength, 0.0);
    });
  });
}
