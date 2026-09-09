import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../../../../core/models/nai_model.dart';
import '../../../../core/services/nai_cost_estimator.dart';
import '../../../../core/services/novel_ai_service.dart';
import '../../../generation/models/nai_character.dart';
import '../models/enhance_config.dart';

/// Session render settings Enhance mirrors from the main editor (issue #35).
typedef EnhanceRenderSettings = ({
  String noiseSchedule,
  double cfgRescale,
  double? varietyBoostSigma,
  bool transparentBackground,
});

class EnhanceNotifier extends ChangeNotifier {
  NovelAIService? _service;
  NaiModel _model = NaiModel.fallback;
  EnhanceRenderSettings Function()? _sessionRenderSettings;

  static const String defaultNegativePrompt = 'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract]';

  Uint8List? _sourceImageBytes;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  String _prompt = '';
  String _negativePrompt = defaultNegativePrompt;
  EnhanceConfig _config = const EnhanceConfig();
  Uint8List? _resultBytes;
  bool _isProcessing = false;
  String? _error;
  String _status = '';

  String? _promptPrefix;
  String? _promptSuffix;
  String? _styleNegativeContent;
  List<NaiCharacter> _characters = const [];
  List<NaiInteraction> _interactions = const [];
  bool _useCoords = false;

  Uint8List? get sourceImageBytes => _sourceImageBytes;
  int get sourceWidth => _sourceWidth;
  int get sourceHeight => _sourceHeight;
  String get prompt => _prompt;
  String get negativePrompt => _negativePrompt;
  EnhanceConfig get config => _config;
  Uint8List? get resultBytes => _resultBytes;
  bool get isProcessing => _isProcessing;
  String? get error => _error;
  String get status => _status;
  bool get hasSource => _sourceImageBytes != null;
  bool get hasResult => _resultBytes != null;

  void updateService(NovelAIService? service) {
    _service = service;
  }

  NaiModel get model => _model;

  /// Enhance renders with the same model as the main editor (it used to be
  /// hard-wired to V4.5 Full regardless of the CURATED toggle). A Max
  /// selection is dropped when the new model cannot do it (V4.5).
  void updateModel(NaiModel model) {
    _model = model;
    if (_config.maxEnhance && !maxEnhanceAvailable) {
      _config = _config.copyWith(maxEnhance: false);
      notifyListeners();
    }
  }

  /// Steps / guidance Enhance sends (the service defaults); used for the
  /// cost estimate so it matches the request.
  static const int enhanceSteps = 28;

  /// Whether NovelAI offers Enhance "Max" for the current model and source
  /// (`caps.maxEnhance` and the source is below 0.8 × the pixel cap).
  bool get maxEnhanceAvailable =>
      hasSource && naiMaxEnhanceAvailable(_model, _sourceWidth, _sourceHeight);

  /// The numeric scale chips NovelAI's frontend offers: `[2, 1.5, 1]`, kept
  /// only where the rounded-to-64 output stays within the 3,145,728 px cap.
  /// 832×1216 → `[1.5, 1]`; 512×768 → `[2, 1.5, 1]`.
  List<double> get availableScales {
    if (!hasSource) return const [1.0];
    return [2.0, 1.5, 1.0].where((scale) {
      final (w, h) = _scaledSize(scale);
      return w * h <= naiMaxPixels;
    }).toList();
  }

  /// Source dimensions × [scale], each rounded to the nearest multiple of 64
  /// (what the app has always sent for Enhance).
  (int, int) _scaledSize(double scale) => (
        ((_sourceWidth * scale) / 64).round() * 64,
        ((_sourceHeight * scale) / 64).round() * 64,
      );

  /// What Max returns, per live runs on 2026-09-09: **2× the sent size**
  /// when that fits the 3,145,728 px cap (512×768 → 1024×1536), otherwise the
  /// sent aspect scaled to the cap (896×1152 → 1564×2011). The server does
  /// not align the capped size to 64, so this rounds to the pixel and only
  /// nudges down when rounding would overshoot the cap.
  (int, int) get predictedMaxSize {
    if (_sourceWidth <= 0 || _sourceHeight <= 0) return (0, 0);
    final (sw, sh) = _scaledSize(1.0); // what is actually sent
    if (4 * sw * sh <= naiMaxPixels) return (2 * sw, 2 * sh);
    final k = math.sqrt(naiMaxPixels / (sw * sh));
    var w = math.max(1, (sw * k).round());
    var h = math.max(1, (sh * k).round());
    if (w * h > naiMaxPixels) {
      w = math.max(1, (sw * k).floor());
      h = math.max(1, (sh * k).floor());
    }
    return (w, h);
  }

  /// Dimensions of the image Enhance will produce with the current config.
  (int, int) get predictedOutputSize =>
      _config.maxEnhance ? predictedMaxSize : _scaledSize(_config.scale);

  /// Dimensions sent in the request. Max keeps the SOURCE size (the server
  /// scales) — rounded to multiples of 64 like every other NovelAI request,
  /// so an odd-sized import (1000×1400) goes out as 1024×1408; numeric scales
  /// send the scaled size.
  (int, int) get requestSize =>
      _config.maxEnhance ? _scaledSize(1.0) : _scaledSize(_config.scale);

  /// Anlas estimate for the next Enhance, priced at the OUTPUT pixel count.
  /// Max costs the ordinary img2img price of its output size times
  /// [naiMaxEnhanceCostFactor] (fit to live runs — see the constant); it is
  /// charged in Anlas even on Opus.
  NaiImageCostEstimate estimateCost({required bool isOpus}) {
    final (w, h) = predictedOutputSize;
    return estimateNaiImageCost(
      width: w,
      height: h,
      steps: enhanceSteps,
      smea: false,
      smeaDyn: false,
      isOpus: isOpus,
      hasImageInput: true,
      strengthFactor: _config.maxEnhance
          ? _config.strength * naiMaxEnhanceCostFactor
          : _config.strength,
    );
  }

  /// Wires a live view of the main editor's session render settings
  /// (noise schedule / rescale / Variety+ / Transparent BG, issue #35).
  /// A getter rather than a pushed copy: these change on every slider move,
  /// and Enhance must render with what the user currently sees.
  void updateRenderSettingsSource(EnhanceRenderSettings Function() source) {
    _sessionRenderSettings = source;
  }

  Future<void> setSourceImage(Uint8List bytes) async {
    final decoded = await compute(_decodeImageDimensions, bytes);
    if (decoded == null) return;
    _sourceImageBytes = bytes;
    _sourceWidth = decoded.$1;
    _sourceHeight = decoded.$2;
    _resultBytes = null;
    _error = null;
    // A source that is already near the cap has no Max, and a numeric scale
    // that would overflow the cap is not offered either.
    if (_config.maxEnhance && !maxEnhanceAvailable) {
      _config = _config.copyWith(maxEnhance: false);
    }
    if (!availableScales.contains(_config.scale)) {
      _config = _config.copyWith(scale: 1.0);
    }
    notifyListeners();
  }

  void setPrompt(String value) {
    _prompt = value;
  }

  void setNegativePrompt(String value) {
    _negativePrompt = value;
  }

  void setStrength(double value) {
    _config = _config.copyWith(strength: value.clamp(0.0, 1.0));
    notifyListeners();
  }

  void setNoise(double value) {
    _config = _config.copyWith(noise: value.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// Picks a numeric scale; this deselects Max.
  void setScale(double value) {
    _config = _config.copyWith(scale: value, maxEnhance: false);
    notifyListeners();
  }

  /// Selects / clears Enhance "Max". Ignored when the model or source cannot
  /// do it (see [maxEnhanceAvailable]).
  void setMaxEnhance(bool value) {
    if (value && !maxEnhanceAvailable) return;
    _config = _config.copyWith(maxEnhance: value);
    notifyListeners();
  }

  void setStyleData({
    String? promptPrefix,
    String? promptSuffix,
    String? styleNegativeContent,
  }) {
    _promptPrefix = promptPrefix;
    _promptSuffix = promptSuffix;
    _styleNegativeContent = styleNegativeContent;
  }

  void setCharacterData({
    List<NaiCharacter> characters = const [],
    List<NaiInteraction> interactions = const [],
    bool useCoords = false,
  }) {
    _characters = characters;
    _interactions = interactions;
    _useCoords = useCoords;
  }

  Future<void> enhance() async {
    if (_service == null || _sourceImageBytes == null) return;
    _isProcessing = true;
    _error = null;
    _resultBytes = null;
    _status = 'Enhancing...';
    notifyListeners();

    try {
      // Step 1: Resize and encode source for img2img
      final sourceBase64 = await compute(_resizeAndEncode, _ResizeParams(
        bytes: _sourceImageBytes!,
        width: _sourceWidth,
        height: _sourceHeight,
      ));

      // Step 2: Generate enhanced image via img2img. A numeric scale sends
      // the scaled size (rounded to 64); Max sends the SOURCE size (also
      // rounded to 64) plus `upscaled_enhance: true` and lets the server
      // scale to the cap.
      final (outWidth, outHeight) = requestSize;

      final effectiveNegative = _styleNegativeContent != null && _styleNegativeContent!.isNotEmpty
          ? '$_negativePrompt, $_styleNegativeContent'
          : _negativePrompt;

      final render = _sessionRenderSettings?.call();

      final result = await _service!.generateImage(
        prompt: _prompt,
        negativePrompt: effectiveNegative,
        noiseSchedule: render?.noiseSchedule,
        cfgRescale: render?.cfgRescale,
        varietyBoostSigma: render?.varietyBoostSigma,
        transparentBackground: render?.transparentBackground ?? false,
        width: outWidth,
        height: outHeight,
        seed: DateTime.now().microsecondsSinceEpoch % 4294967295,
        action: 'img2img',
        sourceImageBase64: sourceBase64,
        img2imgStrength: _config.strength,
        img2imgNoise: _config.noise,
        upscaledEnhance: _config.maxEnhance,
        promptPrefix: _promptPrefix,
        promptSuffix: _promptSuffix,
        characters: _characters,
        interactions: _interactions,
        useCoords: _useCoords,
        model: _model,
      );

      _resultBytes = result.imageBytes;
      _status = '';
    } on UnauthorizedException {
      _error = 'Authentication error: check API key';
    } catch (e) {
      _error = e.toString();
    } finally {
      _isProcessing = false;
      _status = '';
      notifyListeners();
    }
  }

  void clearResult() {
    _resultBytes = null;
    _error = null;
    notifyListeners();
  }

  void clear() {
    _sourceImageBytes = null;
    _sourceWidth = 0;
    _sourceHeight = 0;
    _resultBytes = null;
    _error = null;
    _isProcessing = false;
    _status = '';
    _prompt = '';
    _negativePrompt = defaultNegativePrompt;
    _config = const EnhanceConfig();
    _promptPrefix = null;
    _promptSuffix = null;
    _styleNegativeContent = null;
    _characters = const [];
    _interactions = const [];
    _useCoords = false;
    notifyListeners();
  }
}

(int, int)? _decodeImageDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return (decoded.width, decoded.height);
}

class _ResizeParams {
  final Uint8List bytes;
  final int width;
  final int height;
  _ResizeParams({required this.bytes, required this.width, required this.height});
}

String _resizeAndEncode(_ResizeParams params) {
  final decoded = img.decodeImage(params.bytes);
  if (decoded == null) throw Exception('Failed to decode source image');
  final resized = img.copyResize(decoded, width: params.width, height: params.height);
  final rgb = resized.convert(numChannels: 3);
  final pngBytes = img.encodePng(rgb);
  return base64Encode(pngBytes);
}
