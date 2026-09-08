import 'package:flutter/material.dart';
import '../../../core/services/wildcard_service.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
import '../../../core/models/nai_model.dart';
import '../../../core/services/styles.dart';
import '../../../core/services/tag_service.dart';

class StyleState {
  final List<PromptStyle> styles;
  final PromptStyle? selectedStyle;
  final String? originalName;
  final List<DanbooruTag> tagSuggestions;
  final String currentTagQuery;
  final bool isModified;
  final bool isEditingNegative;

  StyleState({
    this.styles = const [],
    this.selectedStyle,
    this.originalName,
    this.tagSuggestions = const [],
    this.currentTagQuery = "",
    this.isModified = false,
    this.isEditingNegative = false,
  });

  StyleState copyWith({
    List<PromptStyle>? styles,
    PromptStyle? selectedStyle,
    String? originalName,
    List<DanbooruTag>? tagSuggestions,
    String? currentTagQuery,
    bool? isModified,
    bool? isEditingNegative,
  }) {
    return StyleState(
      styles: styles ?? this.styles,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      originalName: originalName ?? this.originalName,
      tagSuggestions: tagSuggestions ?? this.tagSuggestions,
      currentTagQuery: currentTagQuery ?? this.currentTagQuery,
      isModified: isModified ?? this.isModified,
      isEditingNegative: isEditingNegative ?? this.isEditingNegative,
    );
  }
}

class StyleNotifier extends ChangeNotifier {
  StyleState _state = StyleState();
  StyleState get state => _state;

  final TagService _tagService;
  final WildcardService _wildcardService;
  final String _stylesFilePath;
  final VoidCallback onStylesChanged;
  final List<DanbooruTag> Function(String query)? characterSuggestionsFor;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController contentController = TextEditingController();

  /// Text for the per-style steps / guidance override fields.
  final TextEditingController stepsController = TextEditingController();
  final TextEditingController scaleController = TextEditingController();

  /// Values the override starts from when switched on — the editor's current
  /// steps / guidance, so "custom for this style" begins at what is in use.
  final ({double steps, double scale}) overrideSeed;

  StyleNotifier({
    required TagService tagService,
    required WildcardService wildcardService,
    required List<PromptStyle> initialStyles,
    required String stylesFilePath,
    required this.onStylesChanged,
    String? initialStyleName,
    this.characterSuggestionsFor,
    this.overrideSeed = (steps: 28, scale: 5),
  }) : _tagService = tagService,
       _wildcardService = wildcardService,
       _stylesFilePath = stylesFilePath {
    _state = _state.copyWith(styles: initialStyles);
    if (initialStyleName != null) {
      final match = initialStyles.where((s) => s.name == initialStyleName).firstOrNull;
      if (match != null) selectStyle(match);
    }
  }

  void selectStyle(PromptStyle? style) {
    _state = _state.copyWith(
      selectedStyle: style,
      originalName: style?.name,
      isModified: false,
      isEditingNegative: style != null && style.negativeContent.isNotEmpty && style.prefix.isEmpty && style.suffix.isEmpty,
      tagSuggestions: [],
    );
    
    if (style != null) {
      nameController.text = style.name;
      _updateContentController();
      _updateOverrideControllers(style);
    } else {
      nameController.clear();
      contentController.clear();
      stepsController.clear();
      scaleController.clear();
    }
    notifyListeners();
  }

  void _updateOverrideControllers(PromptStyle style) {
    stepsController.text = style.steps == null ? '' : _fmt(style.steps!);
    scaleController.text = style.scale == null ? '' : _fmt(style.scale!);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Switches the per-style steps / guidance override on (seeded from
  /// [overrideSeed]) or off (both cleared).
  void setRenderOverrideEnabled(bool enabled) {
    final current = _state.selectedStyle;
    if (current == null) return;
    if (enabled) {
      updateCurrentStyle(
        steps: current.steps ?? overrideSeed.steps,
        scale: current.scale ?? overrideSeed.scale,
      );
      _updateOverrideControllers(_state.selectedStyle!);
    } else {
      updateCurrentStyle(clearRenderOverride: true);
      stepsController.clear();
      scaleController.clear();
    }
  }

  /// Parses the STEPS field (1–50, whole numbers). Unparseable input leaves
  /// the stored value alone.
  void setOverrideSteps(String text) {
    final v = double.tryParse(text.trim());
    if (v == null) return;
    updateCurrentStyle(steps: v.clamp(1, 50).roundToDouble());
  }

  /// Parses the CFG field (1–30). Unparseable input leaves the value alone.
  void setOverrideScale(String text) {
    final v = double.tryParse(text.trim());
    if (v == null) return;
    updateCurrentStyle(scale: v.clamp(1.0, 30.0).toDouble());
  }

  void setEditingNegative(bool value) {
    _state = _state.copyWith(isEditingNegative: value);
    _updateContentController();
    notifyListeners();
  }

  void _updateContentController() {
    if (_state.selectedStyle == null) return;
    
    if (_state.isEditingNegative) {
      contentController.text = _state.selectedStyle!.negativeContent;
    } else {
      contentController.text = _state.selectedStyle!.prefix.isNotEmpty 
          ? _state.selectedStyle!.prefix 
          : _state.selectedStyle!.suffix;
    }
  }

  void updateCurrentStyle({
    String? name,
    String? content,
    bool? isPrefix,
    bool? isDefault,
    Set<NaiModelFamily>? models,
    double? steps,
    double? scale,
    bool clearRenderOverride = false,
  }) {
    if (_state.selectedStyle == null) return;

    final finalContent = content ?? contentController.text;
    final current = _state.selectedStyle!;
    final overrideSteps = clearRenderOverride ? null : (steps ?? current.steps);
    final overrideScale = clearRenderOverride ? null : (scale ?? current.scale);

    PromptStyle updated;
    if (_state.isEditingNegative) {
      updated = PromptStyle(
        name: name ?? nameController.text,
        prefix: current.prefix,
        suffix: current.suffix,
        negativeContent: finalContent,
        isDefault: isDefault ?? current.isDefault,
        models: models ?? current.models,
        steps: overrideSteps,
        scale: overrideScale,
      );
    } else {
      final currentIsPrefix = isPrefix ?? (current.prefix.isNotEmpty || current.suffix.isEmpty);
      updated = PromptStyle(
        name: name ?? nameController.text,
        prefix: currentIsPrefix ? finalContent : "",
        suffix: currentIsPrefix ? "" : finalContent,
        negativeContent: current.negativeContent,
        isDefault: isDefault ?? current.isDefault,
        models: models ?? current.models,
        steps: overrideSteps,
        scale: overrideScale,
      );
    }

    _state = _state.copyWith(
      selectedStyle: updated,
      isModified: true,
    );
    notifyListeners();
  }

  /// Whether the selected style already exists in the saved list. False for a
  /// style created by [createNewStyle] that has not been saved yet.
  bool get isSelectedStyleSaved =>
      _state.originalName != null &&
      _state.styles.any((s) => s.name == _state.originalName);

  /// Overwrites the style being edited, keyed by the name it had when it was
  /// selected ([StyleState.originalName]) — so renaming replaces the entry in
  /// place instead of appending a duplicate and leaving the old name behind.
  ///
  /// If the new name collides with a *different* existing style (the UI asks
  /// for confirmation first via [hasNameConflict]), that other entry is
  /// removed so the list never holds two styles with the same name. A style
  /// that was never saved is appended.
  /// Toggles a target family on the edited style. At least one family must
  /// stay selected, so the last one cannot be switched off.
  void toggleModelFamily(NaiModelFamily family) {
    final current = _state.selectedStyle;
    if (current == null) return;
    final next = Set<NaiModelFamily>.from(current.models);
    if (next.contains(family)) {
      if (next.length == 1) return;
      next.remove(family);
    } else {
      next.add(family);
    }
    updateCurrentStyle(models: next);
  }

  Future<void> saveStyle() async {
    if (_state.selectedStyle == null) return;

    final finalStyle = _state.selectedStyle!;
    final originalName = _state.originalName;
    final updatedStyles = List<PromptStyle>.from(_state.styles);

    final index = updatedStyles.indexWhere((s) => s.name == originalName);
    if (index != -1) {
      updatedStyles[index] = finalStyle;
      // Rename onto another existing style: the edited entry keeps its slot,
      // the colliding one is dropped (the user confirmed the overwrite).
      updatedStyles.removeWhere(
          (s) => s.name == finalStyle.name && !identical(s, finalStyle));
    } else {
      updatedStyles.add(finalStyle);
    }

    _state = _state.copyWith(
      styles: updatedStyles,
      originalName: finalStyle.name,
      isModified: false,
    );
    await StyleStorage.saveStyles(_stylesFilePath, updatedStyles);
    onStylesChanged();
    notifyListeners();
  }

  /// Appends a copy of the edited style under the current name and selects
  /// it. The original entry is left untouched. If the name is already taken
  /// (including when the user did not change it), it is suffixed
  /// " (Copy)", " (Copy 2)", … like [duplicateStyle].
  Future<void> saveAsNew() async {
    if (_state.selectedStyle == null) return;

    final source = _state.selectedStyle!;
    final newStyle = source.copyWith(name: uniqueName(source.name));
    final updatedStyles = List<PromptStyle>.from(_state.styles)..add(newStyle);

    _state = _state.copyWith(styles: updatedStyles);
    selectStyle(newStyle);
    await StyleStorage.saveStyles(_stylesFilePath, updatedStyles);
    onStylesChanged();
    notifyListeners();
  }

  /// [base] if no saved style has that name, otherwise the first free
  /// "base (Copy)", "base (Copy 2)", … — or, with [numbered], "base 2",
  /// "base 3", … (used for the placeholder name of a brand-new style).
  String uniqueName(String base, {bool numbered = false}) {
    final taken = _state.styles.map((s) => s.name).toSet();
    final trimmed = base.trim();
    if (!taken.contains(trimmed)) return trimmed;
    for (var n = 1;; n++) {
      final candidate = numbered
          ? '$trimmed ${n + 1}'
          : (n == 1 ? '$trimmed (Copy)' : '$trimmed (Copy $n)');
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> deleteStyle(PromptStyle style) async {
    final updatedStyles = List<PromptStyle>.from(_state.styles)..removeWhere((s) => s.name == style.name);
    if (_state.originalName == style.name) {
      selectStyle(null);
    }
    _state = _state.copyWith(styles: updatedStyles);
    await StyleStorage.saveStyles(_stylesFilePath, updatedStyles);
    onStylesChanged();
    notifyListeners();
  }

  void duplicateStyle(PromptStyle style) {
    final newStyle = style.copyWith(name: uniqueName(style.name));

    final updatedStyles = List<PromptStyle>.from(_state.styles)..add(newStyle);
    _state = _state.copyWith(styles: updatedStyles);
    StyleStorage.saveStyles(_stylesFilePath, updatedStyles).then((_) => onStylesChanged());
    notifyListeners();
  }

  Future<void> reorderStyles(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final updatedStyles = List<PromptStyle>.from(_state.styles);
    final item = updatedStyles.removeAt(oldIndex);
    updatedStyles.insert(newIndex, item);
    _state = _state.copyWith(styles: updatedStyles);
    await StyleStorage.saveStyles(_stylesFilePath, updatedStyles);
    onStylesChanged();
    notifyListeners();
  }

  bool hasNameConflict() {
    final currentName = nameController.text.trim();
    if (currentName.isEmpty) return false;
    return _state.styles.any((s) => s.name == currentName && s.name != _state.originalName);
  }

  Future<void> resetToDefaults() async {
    final defaults = await StyleStorage.resetToDefaults(_stylesFilePath);
    _state = _state.copyWith(styles: defaults, isModified: false);
    selectStyle(null);
    onStylesChanged();
    notifyListeners();
  }

  void createNewStyle() {
    final newStyle = PromptStyle(
      name: uniqueName("NEW STYLE", numbered: true),
      prefix: "",
      suffix: "",
      negativeContent: "",
      isDefault: false,
    );
    selectStyle(newStyle);
  }

  void handleTagSuggestions(String text, TextSelection selection) {
    final result = TagSuggestionHelper.getSuggestions(
      text: text,
      selection: selection,
      tagService: _tagService,
      supportFavorites: true,
      wildcardService: _wildcardService,
      characterSuggestionsFor: characterSuggestionsFor,
    );
    _state = _state.copyWith(
      tagSuggestions: result.suggestions,
      currentTagQuery: result.query,
    );
    notifyListeners();
  }

  void clearTagSuggestions() {
    if (_state.tagSuggestions.isEmpty) return;
    _state = _state.copyWith(tagSuggestions: [], currentTagQuery: "");
    notifyListeners();
  }

  void applyTagSuggestion(DanbooruTag tag) {
    TagSuggestionHelper.applyTag(contentController, tag);
    _state = _state.copyWith(tagSuggestions: [], currentTagQuery: "");
    updateCurrentStyle(content: contentController.text);
    notifyListeners();
  }

  @override
  void dispose() {
    nameController.dispose();
    contentController.dispose();
    stepsController.dispose();
    scaleController.dispose();
    super.dispose();
  }
}
