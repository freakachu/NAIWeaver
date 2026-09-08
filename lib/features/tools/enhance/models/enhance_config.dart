class EnhanceConfig {
  final double strength;
  final double noise;
  final double scale;

  /// NovelAI's Enhance "Max" (`upscaled_enhance: true`): the request keeps
  /// the source dimensions and the server returns the image scaled to the
  /// 3,145,728 px cap. When set, [scale] is ignored.
  final bool maxEnhance;

  const EnhanceConfig({
    this.strength = 0.5,
    this.noise = 0.0,
    this.scale = 1.0,
    this.maxEnhance = false,
  });

  EnhanceConfig copyWith({
    double? strength,
    double? noise,
    double? scale,
    bool? maxEnhance,
  }) {
    return EnhanceConfig(
      strength: strength ?? this.strength,
      noise: noise ?? this.noise,
      scale: scale ?? this.scale,
      maxEnhance: maxEnhance ?? this.maxEnhance,
    );
  }
}
