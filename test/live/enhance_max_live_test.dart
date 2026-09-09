// Live check of NovelAI Enhance "Max" (`upscaled_enhance: true`) on V5.
//
// Skipped unless a token is supplied — it spends Anlas / Opus allowance:
//
//   flutter test test/live/enhance_max_live_test.dart \
//     --dart-define=NAI_TOKEN=pst-… \
//     --dart-define=NAI_SOURCE_IMAGE=C:/path/to/source.png \
//     [--dart-define=NAI_RESULT_DIR=C:/where/to/write]
//
// Sends the source at its 64-rounded size the way `EnhanceNotifier` does,
// asks for Max, and checks the result comes back larger than the source and
// near the 3,145,728 px cap. The result PNG and a JSON summary are written to
// NAI_RESULT_DIR (default: the system temp dir).
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naiweaver/core/models/nai_model.dart';
import 'package:naiweaver/core/services/novel_ai_service.dart';
import 'package:naiweaver/core/utils/image_utils.dart';
import 'package:path/path.dart' as p;

const _token = String.fromEnvironment('NAI_TOKEN');
const _source = String.fromEnvironment('NAI_SOURCE_IMAGE');
const _resultDir = String.fromEnvironment('NAI_RESULT_DIR');
const _steps = int.fromEnvironment('NAI_STEPS', defaultValue: 23);
final _strength =
    double.tryParse(const String.fromEnvironment('NAI_STRENGTH', defaultValue: '0.3')) ?? 0.3;
// Optional: downscale the source to this size first (pricing probes).
const _sourceW = int.fromEnvironment('NAI_SOURCE_W', defaultValue: 0);
const _sourceH = int.fromEnvironment('NAI_SOURCE_H', defaultValue: 0);

int _round64(int v) => (v / 64).round() * 64;

void main() {
  test(
    'Enhance Max on V5 returns a ~3.1 MP image',
    () async {
      final bytes = await File(_source).readAsBytes();
      var decoded = img.decodeImage(bytes)!;
      if (_sourceW > 0 && _sourceH > 0) {
        decoded = img.copyResize(decoded, width: _sourceW, height: _sourceH);
      }
      final w = _round64(decoded.width);
      final h = _round64(decoded.height);
      expect(naiMaxEnhanceAvailable(NaiModel.v5Full, decoded.width, decoded.height), isTrue,
          reason: 'source must be below 0.8 × the pixel cap for Max to be offered');

      // Same preparation as EnhanceNotifier._resizeAndEncode.
      final resized = img.copyResize(decoded, width: w, height: h);
      final rgb = resized.convert(numChannels: 3);
      final sourceBase64 = base64Encode(img.encodePng(rgb));

      // Prompt: the image's own, when it carries NovelAI metadata.
      var prompt = 'masterpiece, best quality, highly detailed';
      final comment = extractMetadata(bytes)?['Comment'];
      if (comment != null) {
        final json = parseCommentJson(comment);
        final own = (json?['prompt'] as String? ?? '').trim();
        if (own.isNotEmpty) prompt = own;
      }

      final service = NovelAIService(_token);
      final before = await service.getSubscription();
      final started = DateTime.now();
      final result = await service.generateImage(
        model: NaiModel.v5Full,
        prompt: prompt,
        negativePrompt: 'lowres, bad anatomy, bad hands, worst quality',
        width: w,
        height: h,
        seed: 424242,
        steps: _steps,
        scale: 7.0,
        sampler: 'k_euler_ancestral',
        action: 'img2img',
        sourceImageBase64: sourceBase64,
        img2imgStrength: _strength,
        img2imgNoise: 0.0,
        upscaledEnhance: true,
      );
      final elapsed = DateTime.now().difference(started);
      final after = await service.getSubscription();

      final out = img.decodeImage(result.imageBytes)!;
      final dir = _resultDir.isNotEmpty ? _resultDir : Directory.systemTemp.path;
      await Directory(dir).create(recursive: true);
      final pngPath = p.join(dir, 'enhance_max_result.png');
      await File(pngPath).writeAsBytes(result.imageBytes);
      final summary = {
        'source': {'w': decoded.width, 'h': decoded.height, 'sent_w': w, 'sent_h': h},
        'result': {'w': out.width, 'h': out.height, 'pixels': out.width * out.height, 'bytes': result.imageBytes.length},
        'cap': naiMaxPixels,
        'steps': _steps,
        'strength': _strength,
        'elapsed_ms': elapsed.inMilliseconds,
        'anlas_before': before?.anlas,
        'anlas_after': after?.anlas,
        'usage_before': before?.usage?.percent,
        'usage_after': after?.usage?.percent,
        'tier': before?.tier,
        'png': pngPath,
      };
      await File(p.join(dir, 'enhance_max_result.json'))
          .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
      // ignore: avoid_print
      print('ENHANCE_MAX_RESULT ${jsonEncode(summary)}');

      // Observed rule: 2× the source, or the source aspect scaled to the cap
      // when 2× would exceed it (512×768 → 1024×1536; 896×1152 → 1564×2011).
      final expectedPixels = math.min(4 * w * h, naiMaxPixels);
      expect(out.width * out.height, greaterThan(w * h), reason: 'Max must upscale');
      expect(out.width * out.height, lessThanOrEqualTo(naiMaxPixels));
      expect(out.width * out.height, greaterThan(expectedPixels * 0.99), reason: '2× or the cap');
      expect((out.width / out.height - w / h).abs(), lessThan(0.05), reason: 'aspect preserved');
    },
    skip: _token.isEmpty || _source.isEmpty
        ? 'set --dart-define=NAI_TOKEN and NAI_SOURCE_IMAGE to run against the live API'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
