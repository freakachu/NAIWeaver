import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/preferences/gallery_preferences.dart';
import 'package:naiweaver/core/services/preferences_service.dart';
import 'package:naiweaver/core/theme/theme_notifier.dart';
import 'package:naiweaver/core/utils/app_snackbar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _wrap(Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final prefsService = PreferencesService(prefs, const FlutterSecureStorage());
  return ChangeNotifierProvider<ThemeNotifier>(
    create: (_) => ThemeNotifier(prefsService),
    child: MaterialApp(home: child),
  );
}

void main() {
  group('showTopToast', () {
    testWidgets('appears at the top of the screen and removes itself', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(await _wrap(
        Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.expand());
        }),
      ));

      showTopToast(ctx, 'COPIED', duration: const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('COPIED'), findsOneWidget);
      final toastTop = tester.getTopLeft(find.text('COPIED')).dy;
      final screenH = tester.getSize(find.byType(Scaffold)).height;
      expect(toastTop, lessThan(screenH / 4),
          reason: 'toast must sit in the top quarter, not the bottom snackbar slot');

      // Auto-dismiss: duration + exit animation.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('COPIED'), findsNothing);
    });
  });

  group('GalleryPreferences.viewerControlsPinned', () {
    test('defaults to false and round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = GalleryPreferences(await SharedPreferences.getInstance());
      expect(prefs.viewerControlsPinned, isFalse);
      await prefs.setViewerControlsPinned(true);
      expect(prefs.viewerControlsPinned, isTrue);
      await prefs.setViewerControlsPinned(false);
      expect(prefs.viewerControlsPinned, isFalse);
    });
  });
}
