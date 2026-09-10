import '../../../generation/models/nai_character.dart';

class BeatCharacterSlot {
  final NaiCoordinate position;

  /// The action tags for this slot, e.g. "source#hugging", "target#hugging",
  /// "mutual#holding hands". A slot can hold multiple interactions at once
  /// (e.g. a character that is the source of one action and the target of
  /// another). Empty when no interaction is defined for this slot.
  final List<String> actionTags;

  final String positivePrompt;
  final String negativePrompt;

  BeatCharacterSlot({
    required this.position,
    this.actionTags = const [],
    this.positivePrompt = "",
    this.negativePrompt = "",
  });

  factory BeatCharacterSlot.fromJson(Map<String, dynamic> json) {
    // Backward-compatible: detect the legacy single-string `actionTag` field
    // vs the new `actionTags` list. Old saved cascades carry `actionTag`.
    final List<String> tags;
    if (json.containsKey('actionTags')) {
      tags = (json['actionTags'] as List?)?.cast<String>() ?? const [];
    } else {
      final legacy = json['actionTag'] as String?;
      tags = (legacy != null && legacy.isNotEmpty) ? [legacy] : const [];
    }
    return BeatCharacterSlot(
      position: NaiCoordinate.fromJson(json['position']),
      actionTags: tags,
      positivePrompt: json['positivePrompt'] ?? "",
      negativePrompt: json['negativePrompt'] ?? "",
    );
  }

  Map<String, dynamic> toJson() => {
    'position': position.toJson(),
    'actionTags': actionTags,
    'positivePrompt': positivePrompt,
    'negativePrompt': negativePrompt,
  };

  BeatCharacterSlot copyWith({
    NaiCoordinate? position,
    List<String>? actionTags,
    String? positivePrompt,
    String? negativePrompt,
  }) {
    return BeatCharacterSlot(
      position: position ?? this.position,
      actionTags: actionTags ?? this.actionTags,
      positivePrompt: positivePrompt ?? this.positivePrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
    );
  }
}

class CascadeBeat {
  final List<BeatCharacterSlot> characterSlots;

  /// Scene/action/composition tags for this beat (e.g. "2girls, hugging,
  /// wide shot, from above"). These feed the NovelAI **base prompt** and
  /// describe what is happening and how it is framed — distinct from
  /// [environmentTags], which describes *where* the scene takes place.
  /// They are concatenated ahead of the environment tags by the stitcher.
  final String sceneTags;

  final String environmentTags;

  // Per-beat generation settings
  final String sampler;
  final int steps;
  final double scale;
  final int width;
  final int height;
  final List<String> activeStyleNames;

  /// Per-beat override of [PromptCascade.useCoords]. `null` inherits the
  /// cascade-level setting so legacy beats keep their original behaviour.
  final bool? useCoords;

  CascadeBeat({
    required this.characterSlots,
    required this.environmentTags,
    this.sceneTags = "",
    this.sampler = "k_euler_ancestral",
    this.steps = 28,
    this.scale = 6.0,
    this.width = 832,
    this.height = 1216,
    this.activeStyleNames = const [],
    this.useCoords,
  });

  factory CascadeBeat.fromJson(Map<String, dynamic> json) => CascadeBeat(
    characterSlots: (json['characterSlots'] as List)
        .map((e) => BeatCharacterSlot.fromJson(e))
        .toList(),
    sceneTags: json['sceneTags'] ?? "",
    environmentTags: json['environmentTags'],
    sampler: json['sampler'] ?? "k_euler_ancestral",
    steps: json['steps'] ?? 28,
    scale: (json['scale'] as num?)?.toDouble() ?? 6.0,
    width: json['width'] ?? 832,
    height: json['height'] ?? 1216,
    activeStyleNames: (json['activeStyleNames'] as List?)?.cast<String>() ?? [],
    useCoords: json['useCoords'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'characterSlots': characterSlots.map((e) => e.toJson()).toList(),
    'sceneTags': sceneTags,
    'environmentTags': environmentTags,
    'sampler': sampler,
    'steps': steps,
    'scale': scale,
    'width': width,
    'height': height,
    'activeStyleNames': activeStyleNames,
    if (useCoords != null) 'useCoords': useCoords,
  };

  static const _unset = Object();

  CascadeBeat copyWith({
    List<BeatCharacterSlot>? characterSlots,
    String? sceneTags,
    String? environmentTags,
    String? sampler,
    int? steps,
    double? scale,
    int? width,
    int? height,
    List<String>? activeStyleNames,
    Object? useCoords = _unset,
  }) {
    return CascadeBeat(
      characterSlots: characterSlots ?? this.characterSlots,
      sceneTags: sceneTags ?? this.sceneTags,
      environmentTags: environmentTags ?? this.environmentTags,
      sampler: sampler ?? this.sampler,
      steps: steps ?? this.steps,
      scale: scale ?? this.scale,
      width: width ?? this.width,
      height: height ?? this.height,
      activeStyleNames: activeStyleNames ?? this.activeStyleNames,
      useCoords: identical(useCoords, _unset)
          ? this.useCoords
          : useCoords as bool?,
    );
  }
}
