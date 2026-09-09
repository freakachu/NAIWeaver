import 'dart:convert';

import '../../../core/models/nai_model.dart';
import '../../../core/services/styles.dart';

/// Steps + prompt guidance (CFG scale) — the two values a user tunes per
/// model and that a style may override.
typedef RenderValues = ({double steps, double scale});

/// Per-model-family memory of the user's steps / guidance.
///
/// Keyed by [NaiModelFamily] (V4.5 / V5), not wire id: Full and Curated of
/// one generation take the same numbers. Immutable; [remember] returns a new
/// instance. Serialised as `{"v45": {"steps": 17, "scale": 5}, ...}` and
/// tolerant of anything else on the way back in.
class ModelSettingsMemory {
  final Map<NaiModelFamily, RenderValues> _entries;

  const ModelSettingsMemory._(this._entries);
  const ModelSettingsMemory.empty() : _entries = const {};

  bool get isEmpty => _entries.isEmpty;

  Map<NaiModelFamily, RenderValues> get entries => Map.unmodifiable(_entries);

  RenderValues? entryFor(NaiModelFamily family) => _entries[family];

  ModelSettingsMemory remember(NaiModelFamily family, RenderValues values) =>
      ModelSettingsMemory._({..._entries, family: values});

  Map<String, dynamic> toJson() => {
        for (final e in _entries.entries)
          e.key.id: {'steps': e.value.steps, 'scale': e.value.scale},
      };

  /// Anything that is not a map of family → {steps, scale} is skipped; an
  /// unreadable value yields an empty memory rather than an error.
  static ModelSettingsMemory fromJson(Object? json) {
    if (json is! Map) return const ModelSettingsMemory.empty();
    final out = <NaiModelFamily, RenderValues>{};
    for (final entry in json.entries) {
      final family = NaiModelFamily.tryParse(entry.key.toString());
      final value = entry.value;
      if (family == null || value is! Map) continue;
      final steps = value['steps'];
      final scale = value['scale'];
      if (steps is! num || scale is! num) continue;
      out[family] = (steps: steps.toDouble(), scale: scale.toDouble());
    }
    return ModelSettingsMemory._(out);
  }

  String encode() => jsonEncode(toJson());

  static ModelSettingsMemory decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ModelSettingsMemory.empty();
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return const ModelSettingsMemory.empty();
    }
  }
}

/// Decides what steps / guidance the editor shows as models and styles
/// change. Pure state machine — no Flutter, no I/O — so the notifier can
/// delegate and the rules can be unit-tested on their own.
///
/// Rules:
/// * A user edit is remembered under the active model's family.
/// * On a model switch the current values are stored under the OLD family
///   (unless a style override is showing — those are the style's numbers,
///   not the user's) and the NEW family's stored values come back. A family
///   never used keeps whatever is on screen; model defaults are never
///   applied implicitly.
/// * The first active style with a render override pushes its values when it
///   becomes the override (and again after a model switch, since the switch
///   brings the new family's own values back). While that same style stays
///   the override, edits the user makes on top of it stick — toggling some
///   other style must not re-apply the numbers. When it is deselected, or
///   replaced by a style without one, the per-model values are restored
///   (falling back to what was on screen when the override was applied). A
///   style override wins over per-model memory.
class RenderSettingsCoordinator {
  ModelSettingsMemory memory;

  /// Name of the style whose override is currently applied, if any.
  String? overrideStyleName;

  /// Family the override was last pushed for; a different family means the
  /// values on screen are the new family's memory, not the style's.
  NaiModelFamily? _overrideFamily;

  RenderValues? _beforeOverride;

  RenderSettingsCoordinator({this.memory = const ModelSettingsMemory.empty()});

  bool get overrideActive => overrideStyleName != null;

  /// The user changed steps / guidance for [family].
  void rememberEdit(NaiModelFamily family, RenderValues current) {
    memory = memory.remember(family, current);
  }

  /// Model switch from [from] to [to]; returns what to show for [to].
  RenderValues switchFamily({
    required NaiModelFamily from,
    required NaiModelFamily to,
    required RenderValues current,
  }) {
    if (!overrideActive) memory = memory.remember(from, current);
    if (from == to) return current;
    return memory.entryFor(to) ?? current;
  }

  /// Re-evaluates the style override against the resolved active styles
  /// (in selection order) and returns what to show.
  RenderValues syncStyleOverride({
    required List<PromptStyle> activeStyles,
    required bool stylesEnabled,
    required NaiModelFamily family,
    required RenderValues current,
  }) {
    final style = stylesEnabled
        ? activeStyles.where((s) => s.hasRenderOverride).firstOrNull
        : null;

    if (style == null) {
      if (!overrideActive) return current;
      overrideStyleName = null;
      _overrideFamily = null;
      final restore = memory.entryFor(family) ?? _beforeOverride;
      _beforeOverride = null;
      return restore ?? current;
    }

    // Same style, same family: already applied — leave the user's edits alone.
    if (style.name == overrideStyleName && family == _overrideFamily) {
      return current;
    }

    if (!overrideActive) _beforeOverride = current;
    overrideStyleName = style.name;
    _overrideFamily = family;
    return (
      steps: style.steps ?? current.steps,
      scale: style.scale ?? current.scale,
    );
  }

  /// The override style was renamed; keep tracking it under the new name.
  void renameOverrideStyle(String oldName, String newName) {
    if (overrideStyleName == oldName) overrideStyleName = newName;
  }
}
