import 'package:flutter/material.dart';
import '../../../core/services/wildcard_service.dart';
import '../../../core/utils/tag_suggestion_helper.dart';
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

  StyleNotifier({
    required TagService tagService,
    required WildcardService wildcardService,
    required List<PromptStyle> initialStyles,
    required String stylesFilePath,
    required this.onStylesChanged,
    String? initialStyleName,
    this.characterSuggestionsFor,
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
    } else {
      nameController.clear();
      contentController.clear();
    }
    notifyListeners();
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
  }) {
    if (_state.selectedStyle == null) return;

    final finalContent = content ?? contentController.text;
    
    PromptStyle updated;
    if (_state.isEditingNegative) {
      updated = PromptStyle(
        name: name ?? nameController.text,
        prefix: _state.selectedStyle!.prefix,
        suffix: _state.selectedStyle!.suffix,
        negativeContent: finalContent,
        isDefault: isDefault ?? _state.selectedStyle!.isDefault,
      );
    } else {
      final currentIsPrefix = isPrefix ?? (_state.selectedStyle!.prefix.isNotEmpty || _state.selectedStyle!.suffix.isEmpty);
      updated = PromptStyle(
        name: name ?? nameController.text,
        prefix: currentIsPrefix ? finalContent : "",
        suffix: currentIsPrefix ? "" : finalContent,
        negativeContent: _state.selectedStyle!.negativeContent,
        isDefault: isDefault ?? _state.selectedStyle!.isDefault,
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
    super.dispose();
  }
}
