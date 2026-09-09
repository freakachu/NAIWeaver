import 'package:flutter_test/flutter_test.dart';
import 'package:naiweaver/core/services/nai_cost_estimator.dart';

/// Enhance "Max" pricing, pinned to four live Opus runs on 2026-09-09 (V5
/// Full, k_euler_ancestral). The output size, steps and strength are what was
/// sent; the Anlas figure is what the account was charged. See
/// `test/live/enhance_max_live_test.dart` for the probe that produced them.
void main() {
  int cost({required int w, required int h, required int steps, required double strength}) =>
      estimateNaiImageCost(
        width: w,
        height: h,
        steps: steps,
        smea: false,
        smeaDyn: false,
        isOpus: true,
        hasImageInput: true,
        strengthFactor: strength * naiMaxEnhanceCostFactor,
      ).totalAnlas;

  group('Enhance Max cost factor reproduces the live samples', () {
    test('896×1152 → 1564×2011, 23 steps, strength 0.3 → 23 Anlas', () {
      expect(cost(w: 1564, h: 2011, steps: 23, strength: 0.3), 23);
    });
    test('896×1152 → 1564×2011, 28 steps, strength 0.3 → 27 Anlas', () {
      expect(cost(w: 1564, h: 2011, steps: 28, strength: 0.3), 27);
    });
    test('896×1152 → 1564×2011, 23 steps, strength 0.6 → 45 Anlas', () {
      expect(cost(w: 1564, h: 2011, steps: 23, strength: 0.6), 45);
    });
    test('512×768 → 1024×1536, 23 steps, strength 0.3 → 12 Anlas', () {
      expect(cost(w: 1024, h: 1536, steps: 23, strength: 0.3), 12);
    });
    test('Max is never free on Opus (it is an img2img at > 1 MP)', () {
      expect(
        estimateNaiImageCost(
          width: 1024, height: 1536, steps: 23, smea: false, smeaDyn: false,
          isOpus: true, hasImageInput: true, strengthFactor: 0.3 * naiMaxEnhanceCostFactor,
        ).opusBaseDiscountApplied,
        isFalse,
      );
    });
  });
}
