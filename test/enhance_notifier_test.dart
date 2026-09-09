import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/models/nai_model.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/features/generation/models/nai_character.dart';
import 'package:naiweaver/features/tools/enhance/providers/enhance_notifier.dart';

/// Records the arguments of the last [generateImage] call instead of
/// talking to NovelAI. Everything else falls through to [noSuchMethod].
class FakeNovelAIService implements NovelAIService {
  Map<String, Object?>? lastCall;
  int calls = 0;

  @override
  Future<GenerationResult> generateImage({
    required String prompt,
    required int width,
    required int height,
    required int seed,
    int steps = 28,
    double scale = 6.0,
    String sampler = "k_euler_ancestral",
    String? negativePrompt,
    bool smea = false,
    bool smeaDyn = false,
    bool decrisper = false,
    String? noiseSchedule,
    double? cfgRescale,
    double? varietyBoostSigma,
    String? promptPrefix,
    String? promptSuffix,
    List<NaiCharacter> characters = const [],
    List<NaiInteraction> interactions = const [],
    String action = 'generate',
    String? sourceImageBase64,
    String? maskBase64,
    double? img2imgStrength,
    double? img2imgNoise,
    bool? img2imgColorCorrect,
    bool upscaledEnhance = false,
    int? maskBlur,
    List<String>? directorRefImages,
    List<Map<String, dynamic>>? directorRefDescriptions,
    List<double>? directorRefStrengths,
    List<double>? directorRefSecondaryStrengths,
    List<double>? directorRefInfoExtracted,
    List<String>? vibeTransferImages,
    List<double>? vibeTransferStrengths,
    List<double>? vibeTransferInfoExtracted,
    bool? useCoords,
    NaiModel model = NaiModel.fallback,
    bool transparentBackground = false,
  }) async {
    calls++;
    lastCall = {
      'width': width,
      'height': height,
      'action': action,
      'upscaledEnhance': upscaledEnhance,
      'model': model,
      'strength': img2imgStrength,
      'hasSource': sourceImageBase64 != null && sourceImageBase64.isNotEmpty,
    };
    return GenerationResult(imageBytes: Uint8List.fromList([1, 2, 3]), metadata: const {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Uint8List _png(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  return Uint8List.fromList(img.encodePng(image));
}

Future<EnhanceNotifier> _make({
  required NaiModel model,
  required int w,
  required int h,
  FakeNovelAIService? service,
}) async {
  final n = EnhanceNotifier();
  n.updateService(service ?? FakeNovelAIService());
  n.updateModel(model);
  await n.setSourceImage(_png(w, h));
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Max availability', () {
    test('offered on V5 for a source below 0.8 × the pixel cap', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      expect(n.maxEnhanceAvailable, isTrue);
    });

    test('offered on V5 Curated too (same family)', () async {
      final n = await _make(model: NaiModel.v5Curated, w: 512, h: 768);
      expect(n.maxEnhanceAvailable, isTrue);
    });

    test('never on V4.5', () async {
      final n = await _make(model: NaiModel.v45Full, w: 832, h: 1216);
      expect(n.maxEnhanceAvailable, isFalse);
      n.setMaxEnhance(true); // ignored
      expect(n.config.maxEnhance, isFalse);
    });

    test('not for a source already near the cap', () async {
      final n = await _make(model: NaiModel.v5Full, w: 1536, h: 1664);
      expect(n.maxEnhanceAvailable, isFalse);
    });

    test('nothing without a source', () {
      final n = EnhanceNotifier()..updateModel(NaiModel.v5Full);
      expect(n.maxEnhanceAvailable, isFalse);
      expect(n.availableScales, [1.0]);
    });
  });

  group('numeric scale chips (NovelAI [2, 1.5, 1] rule)', () {
    test('832×1216 → 1.5 and 1 (2× would exceed the cap)', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      expect(n.availableScales, [1.5, 1.0]);
    });

    test('512×768 → 2, 1.5 and 1', () async {
      final n = await _make(model: NaiModel.v45Full, w: 512, h: 768);
      expect(n.availableScales, [2.0, 1.5, 1.0]);
    });

    test('a source near the cap only offers 1×', () async {
      final n = await _make(model: NaiModel.v5Full, w: 1536, h: 1664);
      expect(n.availableScales, [1.0]);
    });

    test('every offered scale yields multiples of 64 within the cap', () async {
      final n = await _make(model: NaiModel.v5Full, w: 1024, h: 1024);
      for (final s in n.availableScales) {
        n.setScale(s);
        final (w, h) = n.predictedOutputSize;
        expect(w % 64, 0);
        expect(h % 64, 0);
        expect(w * h, lessThanOrEqualTo(naiMaxPixels));
      }
    });

    test('a scale that no longer fits a new, larger source falls back to 1×', () async {
      final n = await _make(model: NaiModel.v5Full, w: 512, h: 768);
      n.setScale(2.0);
      await n.setSourceImage(_png(1024, 1536));
      expect(n.config.scale, 1.0);
    });
  });

  group('output-dimension prediction', () {
    test('numeric scale rounds to the nearest 64', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setScale(1.5);
      expect(n.predictedOutputSize, (1280, 1856));
      expect(n.requestSize, (1280, 1856));
    });

    test('Max predicts the source aspect scaled to the cap (not 64-aligned)', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setMaxEnhance(true);
      final (w, h) = n.predictedOutputSize;
      expect(w * h, lessThanOrEqualTo(naiMaxPixels));
      expect(w * h, greaterThan(naiMaxPixels * 0.99), reason: 'right at the cap');
      expect((w / h - 832 / 1216).abs(), lessThan(0.005), reason: 'aspect preserved');
      // The REQUEST keeps the source size; the server does the scaling.
      expect(n.requestSize, (832, 1216));
    });

    test('Max prediction matches a live run: 896×1152 → 1564×2011', () async {
      final n = await _make(model: NaiModel.v5Full, w: 896, h: 1152);
      n.setMaxEnhance(true);
      expect(n.predictedOutputSize, (1564, 2011));
    });

    test('Max is 2× when that fits the cap (live: 512×768 → 1024×1536)', () async {
      final n = await _make(model: NaiModel.v5Full, w: 512, h: 768);
      n.setMaxEnhance(true);
      expect(n.predictedOutputSize, (1024, 1536));
      expect(n.requestSize, (512, 768));
    });

    test('Max rounds an odd-sized source to multiples of 64 in the request', () async {
      final n = await _make(model: NaiModel.v5Full, w: 1000, h: 1400);
      n.setMaxEnhance(true);
      expect(n.config.maxEnhance, isTrue);
      expect(n.requestSize, (1024, 1408));
    });
  });

  group('Max selection', () {
    test('selecting Max wins over the numeric scale; picking a scale clears Max', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setScale(1.5);
      n.setMaxEnhance(true);
      expect(n.config.maxEnhance, isTrue);
      expect(n.requestSize, (832, 1216));
      n.setScale(1.0);
      expect(n.config.maxEnhance, isFalse);
    });

    test('switching to a model without the capability clears Max', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setMaxEnhance(true);
      n.updateModel(NaiModel.v45Full);
      expect(n.config.maxEnhance, isFalse);
      // Coming back does not silently re-enable it.
      n.updateModel(NaiModel.v5Full);
      expect(n.config.maxEnhance, isFalse);
    });

    test('a new source too large for Max clears it', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setMaxEnhance(true);
      await n.setSourceImage(_png(1536, 1664));
      expect(n.config.maxEnhance, isFalse);
    });

    test('clear() resets the flag', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      n.setMaxEnhance(true);
      n.clear();
      expect(n.config.maxEnhance, isFalse);
    });
  });

  group('enhance() request', () {
    test('Max: source dimensions + upscaled_enhance on the V5 model', () async {
      final fake = FakeNovelAIService();
      final n = await _make(model: NaiModel.v5Full, w: 512, h: 768, service: fake);
      n.setMaxEnhance(true);
      await n.enhance();
      expect(fake.calls, 1);
      expect(fake.lastCall!['width'], 512);
      expect(fake.lastCall!['height'], 768);
      expect(fake.lastCall!['upscaledEnhance'], isTrue);
      expect(fake.lastCall!['action'], 'img2img');
      expect(fake.lastCall!['model'], NaiModel.v5Full);
      expect(fake.lastCall!['hasSource'], isTrue);
      expect(n.hasResult, isTrue);
      expect(n.error, isNull);
    });

    test('numeric scale: scaled dimensions, no upscaled_enhance', () async {
      final fake = FakeNovelAIService();
      final n = await _make(model: NaiModel.v5Full, w: 512, h: 768, service: fake);
      n.setScale(1.5);
      await n.enhance();
      expect(fake.lastCall!['width'], 768);
      expect(fake.lastCall!['height'], 1152);
      expect(fake.lastCall!['upscaledEnhance'], isFalse);
    });
  });

  group('cost estimate', () {
    test('is priced at the OUTPUT pixel count, so Max costs more than 1×', () async {
      final n = await _make(model: NaiModel.v5Full, w: 832, h: 1216);
      final base = n.estimateCost(isOpus: false).totalAnlas;
      n.setMaxEnhance(true);
      final max = n.estimateCost(isOpus: false).totalAnlas;
      expect(max, greaterThan(base));
      // img2img never gets the Opus free-base discount.
      expect(n.estimateCost(isOpus: true).opusBaseDiscountApplied, isFalse);
    });
  });
}
