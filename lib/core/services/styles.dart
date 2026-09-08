import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/nai_model.dart';
import 'kv_store.dart';

class PromptStyle {
  final String name;
  final String prefix;
  final String suffix;
  final String negativeContent;
  final bool isDefault;

  /// Model families this style is written for. Keyed by family (V4.5 / V5),
  /// not wire id, because Full and Curated share prompt conventions. Never
  /// empty: a style with no explicit target works with every model.
  final Set<NaiModelFamily> models;

  /// Every family — what a style targets when it says nothing.
  static final Set<NaiModelFamily> allModels =
      Set.unmodifiable(NaiModelFamily.values.toSet());

  PromptStyle({
    required this.name,
    this.prefix = "",
    this.suffix = "",
    this.negativeContent = "",
    this.isDefault = false,
    Set<NaiModelFamily>? models,
  }) : models = (models == null || models.isEmpty)
            ? allModels
            : Set.unmodifiable(models);

  /// True when the style is meant for [model]'s family.
  bool supports(NaiModel model) => models.contains(model.family);

  /// True when the style is not restricted to one family.
  bool get targetsAllModels => models.length == NaiModelFamily.values.length;

  PromptStyle copyWith({
    String? name,
    String? prefix,
    String? suffix,
    String? negativeContent,
    bool? isDefault,
    Set<NaiModelFamily>? models,
  }) =>
      PromptStyle(
        name: name ?? this.name,
        prefix: prefix ?? this.prefix,
        suffix: suffix ?? this.suffix,
        negativeContent: negativeContent ?? this.negativeContent,
        isDefault: isDefault ?? this.isDefault,
        models: models ?? this.models,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'prefix': prefix,
        'suffix': suffix,
        'negativeContent': negativeContent,
        'isDefault': isDefault,
        'models': models.map((m) => m.id).toList(),
      };

  /// A missing, empty or unrecognisable `models` list means "every model", so
  /// pre-0.9.4 user files, packs and imports keep working unchanged.
  factory PromptStyle.fromJson(Map<String, dynamic> json) => PromptStyle(
        name: json['name'],
        prefix: json['prefix'] ?? "",
        suffix: json['suffix'] ?? "",
        negativeContent: json['negativeContent'] ?? "",
        isDefault: json['isDefault'] ?? false,
        models: parseStyleModels(json['models']),
      );
}

/// Parses a JSON `models` value (list of family ids / labels). Unknown
/// entries are ignored; null is returned for anything that yields no family
/// so the [PromptStyle] constructor falls back to "all".
Set<NaiModelFamily>? parseStyleModels(Object? raw) {
  if (raw is! List) return null;
  final out = <NaiModelFamily>{};
  for (final entry in raw) {
    final f = NaiModelFamily.tryParse(entry?.toString());
    if (f != null) out.add(f);
  }
  return out.isEmpty ? null : out;
}

/// The styles a user may pick while [model] is active.
List<PromptStyle> stylesForModel(List<PromptStyle> styles, NaiModel model) =>
    styles.where((s) => s.supports(model)).toList();

/// How many styles [stylesForModel] leaves out for [model].
int hiddenStyleCount(List<PromptStyle> styles, NaiModel model) =>
    styles.where((s) => !s.supports(model)).length;

/// Active style names after switching to [model].
///
/// A style that already targets the new family (or targets every family) is
/// never touched, and neither is a name that no longer resolves to a style.
/// A style made only for the other family is swapped for the first
/// `isDefault` style that targets the new one — or simply dropped when there
/// is none. Order is preserved and nothing is listed twice.
List<String> reconcileActiveStylesForModel({
  required List<String> activeStyleNames,
  required List<PromptStyle> styles,
  required NaiModel model,
}) {
  final fallback = styles
      .where((s) => s.isDefault && s.supports(model))
      .map((s) => s.name)
      .firstOrNull;
  final out = <String>[];
  for (final name in activeStyleNames) {
    final style = styles.where((s) => s.name == name).firstOrNull;
    final String? keep;
    if (style == null || style.supports(model)) {
      keep = name;
    } else {
      keep = fallback;
    }
    if (keep != null && !out.contains(keep)) out.add(keep);
  }
  return out;
}

class StyleStorage {
  static const String _prefsKey = 'saved_prompt_styles';

  static Future<List<PromptStyle>> loadStyles(String filePath) async {
    try {
      final stored = await KvStore.readString(
        path: filePath,
        prefsKey: _prefsKey,
      );
      if (stored != null) {
        final List<dynamic> jsonList = jsonDecode(stored);
        return jsonList.map((j) => PromptStyle.fromJson(j)).toList();
      }

      // First run (or web with nothing saved): seed from bundled asset.
      final content = await rootBundle.loadString('prompt_styles.json');
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => PromptStyle.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Error loading styles: $e');
    }

    return [
      PromptStyle(
        name: "Quality V4.5 (NAI Default)",
        prefix: "best quality, amazing quality, very aesthetic, absurdres, ",
        models: {NaiModelFamily.v45},
      ),
    ];
  }

  static Future<void> saveStyles(
      String filePath, List<PromptStyle> styles) async {
    try {
      final jsonString = jsonEncode(styles.map((s) => s.toJson()).toList());
      await KvStore.writeString(
        path: filePath,
        prefsKey: _prefsKey,
        value: jsonString,
      );
    } catch (e) {
      debugPrint('Error saving styles: $e');
    }
  }

  /// Resets styles to bundled defaults by overwriting saved data.
  static Future<List<PromptStyle>> resetToDefaults(String filePath) async {
    try {
      final content = await rootBundle.loadString('prompt_styles.json');
      await KvStore.writeString(
        path: filePath,
        prefsKey: _prefsKey,
        value: content,
      );
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => PromptStyle.fromJson(j)).toList();
    } catch (e) {
      debugPrint('Error resetting styles: $e');
      return [
        PromptStyle(
          name: "Quality V4.5 (NAI Default)",
          prefix: "best quality, amazing quality, very aesthetic, absurdres, ",
          models: {NaiModelFamily.v45},
        ),
      ];
    }
  }
}
