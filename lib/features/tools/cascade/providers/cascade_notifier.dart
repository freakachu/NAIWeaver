import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prompt_cascade.dart';
import '../models/cascade_beat.dart';
import '../../../generation/models/nai_character.dart';

class CascadeState {
  final List<PromptCascade> savedCascades;
  final PromptCascade? activeCascade;
  final int? selectedBeatIndex;
  final bool isLoading;

  // Casting & Playback
  final List<String> characterAppearances;
  final String globalSceneTags;
  final String globalInjection;
  final Map<int, Uint8List?> beatPreviews;

  /// Free-text narration captions per beat index. Cast-time state for *this*
  /// run (like [characterAppearances]) — narration shown over the beat preview,
  /// never part of the saved cascade and never baked into [beatPreviews] bytes.
  final Map<int, String> beatCaptions;

  /// Whether narration captions are rendered over beat previews. User toggle.
  final bool captionsVisible;

  CascadeState({
    this.savedCascades = const [],
    this.activeCascade,
    this.selectedBeatIndex,
    this.isLoading = false,
    this.characterAppearances = const [],
    this.globalSceneTags = "",
    this.globalInjection = "",
    this.beatPreviews = const {},
    this.beatCaptions = const {},
    this.captionsVisible = true,
  });

  CascadeState copyWith({
    List<PromptCascade>? savedCascades,
    PromptCascade? activeCascade,
    bool clearActiveCascade = false,
    int? selectedBeatIndex,
    bool clearSelectedBeatIndex = false,
    bool? isLoading,
    List<String>? characterAppearances,
    String? globalSceneTags,
    String? globalInjection,
    Map<int, Uint8List?>? beatPreviews,
    Map<int, String>? beatCaptions,
    bool? captionsVisible,
  }) {
    return CascadeState(
      savedCascades: savedCascades ?? this.savedCascades,
      activeCascade: clearActiveCascade
          ? null
          : (activeCascade ?? this.activeCascade),
      selectedBeatIndex: clearSelectedBeatIndex
          ? null
          : (selectedBeatIndex ?? this.selectedBeatIndex),
      isLoading: isLoading ?? this.isLoading,
      characterAppearances: characterAppearances ?? this.characterAppearances,
      globalSceneTags: globalSceneTags ?? this.globalSceneTags,
      globalInjection: globalInjection ?? this.globalInjection,
      beatPreviews: beatPreviews ?? this.beatPreviews,
      beatCaptions: beatCaptions ?? this.beatCaptions,
      captionsVisible: captionsVisible ?? this.captionsVisible,
    );
  }
}

class CascadeNotifier extends ChangeNotifier {
  static const String _storageKey = 'saved_prompt_cascades';

  CascadeState _state = CascadeState();
  CascadeState get state => _state;

  String? _savedSnapshot;

  bool get hasUnsavedChanges {
    if (_state.activeCascade == null) return false;
    return json.encode(_state.activeCascade!.toJson()) != _savedSnapshot;
  }

  CascadeNotifier() {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    _state = _state.copyWith(isLoading: true);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> decoded = json.decode(jsonString);
        final cascades = decoded.map((e) => PromptCascade.fromJson(e)).toList();
        _state = _state.copyWith(savedCascades: cascades, isLoading: false);
      } else {
        _state = _state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('Error loading cascades: $e');
      _state = _state.copyWith(isLoading: false);
    }
    notifyListeners();
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(
        _state.savedCascades.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('Error saving cascades: $e');
    }
  }

  void setActiveCascade(PromptCascade? cascade) {
    _savedSnapshot = cascade != null ? json.encode(cascade.toJson()) : null;
    _state = _state.copyWith(
      activeCascade: cascade,
      clearActiveCascade: cascade == null,
      selectedBeatIndex: cascade != null && cascade.beats.isNotEmpty ? 0 : null,
      clearSelectedBeatIndex: cascade == null,
      characterAppearances: cascade != null
          ? List.generate(cascade.characterCount, (_) => "")
          : [],
      globalSceneTags: "",
      globalInjection: "",
      beatPreviews: {},
      beatCaptions: {},
    );
    notifyListeners();
  }

  void exitCascadeMode() {
    _state = _state.copyWith(
      clearActiveCascade: true,
      clearSelectedBeatIndex: true,
      characterAppearances: [],
      globalSceneTags: "",
      globalInjection: "",
      beatPreviews: {},
      beatCaptions: {},
    );
    notifyListeners();
  }

  void updateAppearance(int index, String appearance) {
    final updated = List<String>.from(_state.characterAppearances);
    if (index >= 0 && index < updated.length) {
      updated[index] = appearance;
      _state = _state.copyWith(characterAppearances: updated);
      notifyListeners();
    }
  }

  void updateGlobalSceneTags(String val) {
    _state = _state.copyWith(globalSceneTags: val);
    notifyListeners();
  }

  void updateGlobalInjection(String val) {
    _state = _state.copyWith(globalInjection: val);
    notifyListeners();
  }

  void setBeatPreview(int index, Uint8List? bytes) {
    final updated = Map<int, Uint8List?>.from(_state.beatPreviews);
    updated[index] = bytes;
    _state = _state.copyWith(beatPreviews: updated);
    notifyListeners();
  }

  void setBeatCaption(int index, String text) {
    final updated = Map<int, String>.from(_state.beatCaptions);
    if (text.isEmpty) {
      updated.remove(index);
    } else {
      updated[index] = text;
    }
    _state = _state.copyWith(beatCaptions: updated);
    notifyListeners();
  }

  void toggleCaptionsVisible() {
    _state = _state.copyWith(captionsVisible: !_state.captionsVisible);
    notifyListeners();
  }

  void selectBeat(int index) {
    if (_state.activeCascade == null ||
        index < 0 ||
        index >= _state.activeCascade!.beats.length)
      return;
    _state = _state.copyWith(selectedBeatIndex: index);
    notifyListeners();
  }

  void createNewCascade(
    String name,
    int characterCount, {
    bool useCoords = true,
  }) {
    final newCascade = PromptCascade(
      name: name,
      characterCount: characterCount,
      useCoords: useCoords,
      beats: [
        // Start with one empty beat
        CascadeBeat(
          characterSlots: List.generate(
            characterCount,
            (_) => BeatCharacterSlot(position: NaiCoordinate(x: 0.5, y: 0.5)),
          ),
          environmentTags: "",
          useCoords: useCoords,
        ),
      ],
    );
    _savedSnapshot = null; // Never saved yet → always dirty
    // Seed cast-time state the same way setActiveCascade does. Without this the
    // appearance list stays empty (0) while each beat has 1+ character slots, so
    // CascadeStitchingService.render throws "Not enough character appearances"
    // and beat generation silently no-ops.
    _state = _state.copyWith(
      activeCascade: newCascade,
      selectedBeatIndex: 0,
      characterAppearances: List.generate(characterCount, (_) => ""),
      globalSceneTags: "",
      globalInjection: "",
      beatPreviews: {},
      beatCaptions: {},
    );
    notifyListeners();
  }

  void saveActiveToLibrary() {
    if (_state.activeCascade == null) return;

    final existingIndex = _state.savedCascades.indexWhere(
      (c) => c.name == _state.activeCascade!.name,
    );
    List<PromptCascade> updatedList;
    if (existingIndex >= 0) {
      updatedList = List<PromptCascade>.from(_state.savedCascades)
        ..[existingIndex] = _state.activeCascade!;
    } else {
      updatedList = List<PromptCascade>.from(_state.savedCascades)
        ..add(_state.activeCascade!);
    }

    _savedSnapshot = json.encode(_state.activeCascade!.toJson());
    _state = _state.copyWith(savedCascades: updatedList);
    _saveToStorage();
    notifyListeners();
  }

  void deleteCascade(String name) {
    final updatedList = _state.savedCascades
        .where((c) => c.name != name)
        .toList();
    _state = _state.copyWith(savedCascades: updatedList);
    if (_state.activeCascade?.name == name) {
      _state = _state.copyWith(activeCascade: null, selectedBeatIndex: null);
    }
    _saveToStorage();
    notifyListeners();
  }

  void addBeat() {
    if (_state.activeCascade == null) return;

    final last = _state.activeCascade!.beats.isNotEmpty
        ? _state.activeCascade!.beats.last
        : null;
    final slotCount =
        last?.characterSlots.length ?? _state.activeCascade!.characterCount;
    final newBeat = CascadeBeat(
      characterSlots: List.generate(
        slotCount,
        (_) => BeatCharacterSlot(position: NaiCoordinate(x: 0.5, y: 0.5)),
      ),
      environmentTags: last?.environmentTags ?? "",
      width: last?.width ?? 832,
      height: last?.height ?? 1216,
      useCoords: last?.useCoords ?? _state.activeCascade!.useCoords,
    );

    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats)
      ..add(newBeat);
    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
      selectedBeatIndex: updatedBeats.length - 1,
    );
    notifyListeners();
  }

  void cloneBeat(int index) {
    if (_state.activeCascade == null ||
        index < 0 ||
        index >= _state.activeCascade!.beats.length)
      return;

    final sourceBeat = _state.activeCascade!.beats[index];
    final clonedBeat = CascadeBeat(
      characterSlots: sourceBeat.characterSlots
          .map(
            (s) => BeatCharacterSlot(
              position: s.position,
              actionTags: List.of(s.actionTags),
              positivePrompt: s.positivePrompt,
              negativePrompt: s.negativePrompt,
            ),
          )
          .toList(),
      sceneTags: sourceBeat.sceneTags,
      environmentTags: sourceBeat.environmentTags,
      sampler: sourceBeat.sampler,
      steps: sourceBeat.steps,
      scale: sourceBeat.scale,
      width: sourceBeat.width,
      height: sourceBeat.height,
      activeStyleNames: List.of(sourceBeat.activeStyleNames),
      useCoords: sourceBeat.useCoords,
    );

    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats)
      ..insert(index + 1, clonedBeat);
    // The cloned beat starts un-generated and un-captioned. Shift every cast-time
    // map entry at or after the insertion point up by one so previews/captions
    // stay glued to their beats.
    final insertAt = index + 1;
    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
      selectedBeatIndex: insertAt,
      beatPreviews: _shiftForInsert(_state.beatPreviews, insertAt),
      beatCaptions: _shiftForInsert(_state.beatCaptions, insertAt),
    );
    notifyListeners();
  }

  void removeBeat(int index) {
    if (_state.activeCascade == null || _state.activeCascade!.beats.length <= 1)
      return;

    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats)
      ..removeAt(index);
    int? newSelectedIndex = _state.selectedBeatIndex;
    if (newSelectedIndex != null) {
      if (newSelectedIndex >= updatedBeats.length) {
        newSelectedIndex = updatedBeats.length - 1;
      }
    }

    // Drop the removed beat's preview/caption and shift everything after it down
    // by one so the remaining beats keep their own cast-time state.
    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
      selectedBeatIndex: newSelectedIndex,
      beatPreviews: _shiftForRemoval(_state.beatPreviews, index),
      beatCaptions: _shiftForRemoval(_state.beatCaptions, index),
    );
    notifyListeners();
  }

  void reorderBeats(int oldIndex, int newIndex) {
    if (_state.activeCascade == null) return;

    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = updatedBeats.removeAt(oldIndex);
    updatedBeats.insert(newIndex, item);

    // Apply the same removeAt/insert permutation to the cast-time maps so each
    // beat's preview/caption travels with it.
    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
      selectedBeatIndex: newIndex,
      beatPreviews: _shiftForReorder(_state.beatPreviews, oldIndex, newIndex),
      beatCaptions: _shiftForReorder(_state.beatCaptions, oldIndex, newIndex),
    );
    notifyListeners();
  }

  /// Re-key an index-keyed cast-time map after a beat at [removed] is deleted:
  /// keys below [removed] stay put, the key at [removed] is dropped, keys above
  /// shift down by one.
  static Map<int, T> _shiftForRemoval<T>(Map<int, T> map, int removed) {
    final out = <int, T>{};
    map.forEach((k, v) {
      if (k < removed) {
        out[k] = v;
      } else if (k > removed) {
        out[k - 1] = v;
      }
    });
    return out;
  }

  /// Re-key an index-keyed cast-time map after a new beat is inserted at
  /// [insertAt]: keys below stay put, keys at or above shift up by one (leaving
  /// [insertAt] empty for the new beat).
  static Map<int, T> _shiftForInsert<T>(Map<int, T> map, int insertAt) {
    final out = <int, T>{};
    map.forEach((k, v) {
      out[k >= insertAt ? k + 1 : k] = v;
    });
    return out;
  }

  /// Re-key an index-keyed cast-time map under the same removeAt(oldIndex) +
  /// insert(newIndex) permutation applied to the beats list, so each beat's
  /// preview/caption follows it to its new position.
  static Map<int, T> _shiftForReorder<T>(
    Map<int, T> map,
    int oldIndex,
    int newIndex,
  ) {
    final out = <int, T>{};
    map.forEach((k, v) {
      int nk;
      if (k == oldIndex) {
        nk = newIndex;
      } else {
        // First account for the removeAt(oldIndex)...
        var shifted = k > oldIndex ? k - 1 : k;
        // ...then the insert(newIndex).
        if (shifted >= newIndex) shifted += 1;
        nk = shifted;
      }
      out[nk] = v;
    });
    return out;
  }

  /// Copies [sceneTags] onto every beat in the active cascade. Powers the
  /// "apply to all beats" action — the fixed-shot / changing-action workflow.
  void applySceneToAllBeats(String sceneTags) {
    if (_state.activeCascade == null) return;
    final updatedBeats = _state.activeCascade!.beats
        .map((b) => b.copyWith(sceneTags: sceneTags))
        .toList();
    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
    );
    notifyListeners();
  }

  void updateActiveBeat(CascadeBeat updatedBeat) {
    if (_state.activeCascade == null || _state.selectedBeatIndex == null)
      return;

    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats);
    updatedBeats[_state.selectedBeatIndex!] = updatedBeat;

    _state = _state.copyWith(
      activeCascade: _state.activeCascade!.copyWith(beats: updatedBeats),
    );
    notifyListeners();
  }

  static BeatCharacterSlot _emptySlot() =>
      BeatCharacterSlot(position: NaiCoordinate(x: 0.5, y: 0.5));

  /// Keeps [PromptCascade.characterCount] and cast-time appearances in sync
  /// with the largest per-beat slot list.
  void _syncCastRoster(PromptCascade cascade) {
    final maxSlots = cascade.beats.fold<int>(
      0,
      (m, b) => math.max(m, b.characterSlots.length),
    );
    var appearances = List<String>.from(_state.characterAppearances);
    while (appearances.length < maxSlots) {
      appearances.add('');
    }
    if (appearances.length > maxSlots) {
      appearances = appearances.sublist(0, maxSlots);
    }
    _state = _state.copyWith(
      activeCascade: cascade.copyWith(characterCount: maxSlots),
      characterAppearances: appearances,
    );
  }

  void addCharacterToActiveBeat() {
    if (_state.activeCascade == null || _state.selectedBeatIndex == null)
      return;
    final beat = _state.activeCascade!.beats[_state.selectedBeatIndex!];
    if (beat.characterSlots.length >= PromptCascade.maxCharacterSlots) return;

    final updatedSlots = List<BeatCharacterSlot>.from(beat.characterSlots)
      ..add(_emptySlot());
    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats);
    updatedBeats[_state.selectedBeatIndex!] = beat.copyWith(
      characterSlots: updatedSlots,
    );
    _syncCastRoster(_state.activeCascade!.copyWith(beats: updatedBeats));
    notifyListeners();
  }

  void removeCharacterFromActiveBeat(int index) {
    if (_state.activeCascade == null || _state.selectedBeatIndex == null)
      return;
    final beat = _state.activeCascade!.beats[_state.selectedBeatIndex!];
    if (index < 0 || index >= beat.characterSlots.length) return;

    final updatedSlots = List<BeatCharacterSlot>.from(beat.characterSlots)
      ..removeAt(index);
    final updatedBeats = List<CascadeBeat>.from(_state.activeCascade!.beats);
    updatedBeats[_state.selectedBeatIndex!] = beat.copyWith(
      characterSlots: updatedSlots,
    );
    _syncCastRoster(_state.activeCascade!.copyWith(beats: updatedBeats));
    notifyListeners();
  }

  void reorderCharactersInActiveBeat(int oldIndex, int newIndex) {
    if (_state.activeCascade == null || _state.selectedBeatIndex == null)
      return;
    final beat = _state.activeCascade!.beats[_state.selectedBeatIndex!];
    if (oldIndex < 0 || oldIndex >= beat.characterSlots.length) return;
    var dest = newIndex;
    if (dest > oldIndex) dest -= 1;
    if (dest < 0 || dest >= beat.characterSlots.length) return;

    final updatedSlots = List<BeatCharacterSlot>.from(beat.characterSlots);
    final item = updatedSlots.removeAt(oldIndex);
    updatedSlots.insert(dest, item);
    updateActiveBeat(beat.copyWith(characterSlots: updatedSlots));
  }

  void setActiveBeatUseCoords(bool useCoords) {
    if (_state.activeCascade == null || _state.selectedBeatIndex == null)
      return;
    final beat = _state.activeCascade!.beats[_state.selectedBeatIndex!];
    updateActiveBeat(beat.copyWith(useCoords: useCoords));
  }
}
