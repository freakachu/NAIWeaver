import 'package:flutter/foundation.dart';
import '../../../generation/models/nai_character.dart';
import '../../../../core/services/styles.dart';
import '../models/cascade_beat.dart';

class CascadeStitchedRequest {
  final String baseCaption;
  final List<NaiCharacter> characters;
  final String sampler;
  final int steps;
  final double scale;
  final int width;
  final int height;
  final bool useCoords;
  final String negativePrompt;

  CascadeStitchedRequest({
    required this.baseCaption,
    required this.characters,
    required this.sampler,
    required this.steps,
    required this.scale,
    required this.width,
    required this.height,
    this.useCoords = true,
    this.negativePrompt = "",
  });
}

class CascadeStitchingService {
  /// Renders a single [CascadeBeat] into a [CascadeStitchedRequest].
  ///
  /// [appearances] should be a list of character appearance strings (e.g. "1girl, miku, blue hair").
  /// [appearances] is indexed by [BeatCharacterSlot.castIndex], so every slot
  /// on the beat must have a cast index inside the list.
  /// [globalStyle] is an optional style string from the style tool.
  /// [manualPrompt] is an optional additional prompt from the user during casting.
  static CascadeStitchedRequest render({
    required CascadeBeat beat,
    required List<String> appearances,
    String? globalSceneTags,
    String? globalStyle,
    String? manualPrompt,
    bool useCoords = true,
    List<String> activeStyleNames = const [],
    List<PromptStyle> availableStyles = const [],
  }) {
    for (final slot in beat.characterSlots) {
      if (slot.castIndex < 0 || slot.castIndex >= appearances.length) {
        throw ArgumentError(
            "Not enough character appearances provided. Slot needs cast index ${slot.castIndex}, got ${appearances.length} appearances");
      }
    }

    // Build the base caption, front-loaded in NovelAI base-prompt order:
    // [GlobalScene] + [BeatScene] + [Environment] + [ManualPrompt] + [GlobalStyle].
    // Scene/action/composition tags (subject count, action, camera) lead because
    // NovelAI reads the base prompt left-to-right with front-loaded weight; the
    // cast-time global scene (shared across every beat) leads the per-beat scene,
    // then environment (where), the user's manual injection, and finally style.
    final List<String> basePromptParts = [];
    if (globalSceneTags != null && globalSceneTags.trim().isNotEmpty) {
      basePromptParts.add(globalSceneTags.trim());
    }
    if (beat.sceneTags.isNotEmpty) {
      basePromptParts.add(beat.sceneTags);
    }
    if (beat.environmentTags.isNotEmpty) {
      basePromptParts.add(beat.environmentTags);
    }
    if (manualPrompt != null && manualPrompt.trim().isNotEmpty) {
      basePromptParts.add(manualPrompt.trim());
    }
    if (globalStyle != null && globalStyle.trim().isNotEmpty) {
      basePromptParts.add(globalStyle.trim());
    }
    // Apply style prefix/suffix
    String? stylePrefix;
    String? styleSuffix;
    final List<String> styleNegatives = [];
    for (final styleName in activeStyleNames) {
      try {
        final style = availableStyles.firstWhere((s) => s.name == styleName);
        if (style.prefix.isNotEmpty) stylePrefix = (stylePrefix ?? '') + style.prefix;
        if (style.suffix.isNotEmpty) styleSuffix = (styleSuffix ?? '') + style.suffix;
        if (style.negativeContent.isNotEmpty) styleNegatives.add(style.negativeContent);
      } catch (e) {
        debugPrint('CascadeStitchingService.render: $e');
      }
    }

    final rawCaption = basePromptParts.join(", ");
    final String baseCaption = [
      if (stylePrefix != null) stylePrefix,
      rawCaption,
      if (styleSuffix != null) styleSuffix,
    ].join('');

    final String negativePrompt = styleNegatives.join('');

    // Build the NaiCharacter objects
    final List<NaiCharacter> characters = [];
    for (int i = 0; i < beat.characterSlots.length; i++) {
      final slot = beat.characterSlots[i];
      final appearance = appearances[slot.castIndex];

      // Final Character Prompt = [ActionTags] + [UserCharacterAppearance] + [SlotPositivePrompt]
      // Note: each action tag is in format "source#action", "target#action", or "mutual#action".
      // NovelAIService handles these prefixes if they are in the character prompt.
      final List<String> charPromptParts = [];
      for (final tag in slot.actionTags) {
        if (tag.isNotEmpty) charPromptParts.add(tag);
      }
      if (appearance.trim().isNotEmpty) {
        charPromptParts.add(appearance.trim());
      }
      if (slot.positivePrompt.trim().isNotEmpty) {
        charPromptParts.add(slot.positivePrompt.trim());
      }
      final String characterPrompt = charPromptParts.join(", ");

      characters.add(NaiCharacter(
        prompt: characterPrompt,
        uc: slot.negativePrompt,
        center: slot.position,
      ));
    }

    return CascadeStitchedRequest(
      baseCaption: baseCaption,
      characters: characters,
      sampler: beat.sampler,
      steps: beat.steps,
      scale: beat.scale,
      width: beat.width,
      height: beat.height,
      useCoords: useCoords,
      negativePrompt: negativePrompt,
    );
  }
}
