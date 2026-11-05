import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart';
import 'audio_dsp_models.dart';
import 'audio_dsp_service.dart';

final audioDspServiceProvider = Provider<AudioDspService>(
  (ref) => AudioDspService(),
);

final audioDspProvider =
    StateNotifierProvider<AudioDspNotifier, AudioDspState>((ref) {
      final store = ref.watch(jsonStoreProvider);
      final service = ref.watch(audioDspServiceProvider);
      return AudioDspNotifier(store, service);
    });

class AudioDspState {
  const AudioDspState({
    this.enabled = false,
    this.presetId = AudioPresets.flatId,
    List<int>? bandLevels,
    List<int>? bands,
    this.bassBoost = 0,
    this.virtualizer = 0,
    this.preampDb = 0.0,
    bool? limiterEnabled,
    bool? headroomGuard,
    this.crossfadeSeconds = 3,
    bool? smartGapless,
    bool? smartAlbumGapless,
    bool? normalizeVolume,
    bool? volumeNormalization,
    this.customPresets = const {},
  })  : bandLevels =
            bandLevels ?? bands ?? const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        limiterEnabled = limiterEnabled ?? headroomGuard ?? true,
        smartGapless = smartGapless ?? smartAlbumGapless ?? true,
        normalizeVolume = normalizeVolume ?? volumeNormalization ?? true;

  final bool enabled;
  final String presetId;
  final List<int> bandLevels;
  final int bassBoost;
  final int virtualizer;
  final double preampDb;
  final bool limiterEnabled;
  final int crossfadeSeconds;
  final bool smartGapless;
  final bool normalizeVolume;
  final Map<String, AudioPreset> customPresets;

  List<int> get bands => bandLevels;
  bool get headroomGuard => limiterEnabled;
  bool get smartAlbumGapless => smartGapless;
  bool get volumeNormalization => normalizeVolume;

  double get requiredHeadroomDb =>
      HeadroomGuard.calculateRequiredHeadroomDb(bandLevels, bassBoost);

  double get safeGainDb =>
      limiterEnabled
          ? HeadroomGuard.calculateSafeInputGainDb(preampDb, requiredHeadroomDb)
          : preampDb;

  bool get isCustom => presetId == AudioPresets.customId;

  AudioDspState copyWith({
    bool? enabled,
    String? presetId,
    List<int>? bandLevels,
    int? bassBoost,
    int? virtualizer,
    double? preampDb,
    bool? limiterEnabled,
    int? crossfadeSeconds,
    bool? smartGapless,
    bool? normalizeVolume,
    Map<String, AudioPreset>? customPresets,
  }) {
    return AudioDspState(
      enabled: enabled ?? this.enabled,
      presetId: presetId ?? this.presetId,
      bandLevels: bandLevels ?? this.bandLevels,
      bassBoost: bassBoost ?? this.bassBoost,
      virtualizer: virtualizer ?? this.virtualizer,
      preampDb: preampDb ?? this.preampDb,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      smartGapless: smartGapless ?? this.smartGapless,
      normalizeVolume: normalizeVolume ?? this.normalizeVolume,
      customPresets: customPresets ?? this.customPresets,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'presetId': presetId,
    'bandLevels': bandLevels,
    'bassBoost': bassBoost,
    'virtualizer': virtualizer,
    'preampDb': preampDb,
    'limiterEnabled': limiterEnabled,
    'crossfadeSeconds': crossfadeSeconds,
    'smartGapless': smartGapless,
    'normalizeVolume': normalizeVolume,
    'customPresets': customPresets.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory AudioDspState.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return AudioDspState(
        bandLevels: List.filled(AudioPresets.bandCount, 0),
      );
    }
    final rawLevels = (json['bandLevels'] ?? json['bands']) as List?;
    final levels =
        rawLevels != null && rawLevels.length == AudioPresets.bandCount
            ? rawLevels.map((e) => (e as num).toInt()).toList()
            : List.filled(AudioPresets.bandCount, 0);

    final rawCustom = json['customPresets'];
    final custom = <String, AudioPreset>{};
    if (rawCustom is Map) {
      for (final entry in rawCustom.entries) {
        if (entry.value is Map) {
          custom[entry.key.toString()] = AudioPreset.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
        }
      }
    } else if (rawCustom is List) {
      for (final item in rawCustom) {
        if (item is Map) {
          final p = AudioPreset.fromJson(item.cast<String, dynamic>());
          custom[p.id] = p;
        }
      }
    }

    return AudioDspState(
      enabled: json['enabled'] as bool? ?? false,
      presetId: json['presetId'] as String? ?? AudioPresets.flatId,
      bandLevels: levels,
      bassBoost: (json['bassBoost'] as num?)?.toInt() ?? 0,
      virtualizer: (json['virtualizer'] as num?)?.toInt() ?? 0,
      preampDb: (json['preampDb'] as num?)?.toDouble() ?? 0.0,
      limiterEnabled:
          (json['limiterEnabled'] ?? json['headroomGuard']) as bool? ?? true,
      crossfadeSeconds: (json['crossfadeSeconds'] as num?)?.toInt() ?? 3,
      smartGapless:
          (json['smartGapless'] ?? json['smartAlbumGapless']) as bool? ?? true,
      normalizeVolume:
          (json['normalizeVolume'] ?? json['volumeNormalization']) as bool? ??
          true,
      customPresets: custom,
    );
  }
}

class AudioDspNotifier extends StateNotifier<AudioDspState> {
  AudioDspNotifier(this._store, this._service)
    : super(
        AudioDspState(
          bandLevels: List.filled(AudioPresets.bandCount, 0),
        ),
      ) {
    _load();
  }

  final JsonStore _store;
  final AudioDspService _service;
  static const String _storeKey = 'bloom_audio_dsp';

  void _load() {
    final map = _store.readMap(_storeKey);
    if (map.isNotEmpty) {
      state = AudioDspState.fromJson(map);
    }
    _syncService();
  }

  void _persist() {
    _store.write(_storeKey, state.toJson());
    _syncService();
  }

  void _syncService() {
    _service.apply(
      enabled: state.enabled,
      bandLevels: state.bandLevels,
      bassBoost: state.bassBoost,
      virtualizer: state.virtualizer,
      safeGainDb: state.safeGainDb,
    );
  }

  void toggleEnabled() {
    state = state.copyWith(enabled: !state.enabled);
    _persist();
  }

  void setEnabled(bool enabled) {
    if (state.enabled == enabled) return;
    state = state.copyWith(enabled: enabled);
    _persist();
  }

  void setPreset(String presetId) {
    final preset = AudioPresets.byId(presetId, state.customPresets);
    state = state.copyWith(
      presetId: preset.id,
      bandLevels: List<int>.from(preset.levels),
      bassBoost: preset.bassBoost,
      virtualizer: preset.virtualizer,
    );
    _persist();
  }

  void setBandLevel(int index, int level) {
    if (index < 0 || index >= AudioPresets.bandCount) return;
    final updated = List<int>.from(state.bandLevels);
    updated[index] = level.clamp(-100, 100);
    state = state.copyWith(
      presetId: AudioPresets.customId,
      bandLevels: updated,
    );
    _persist();
  }

  void setBassBoost(int strength) {
    state = state.copyWith(bassBoost: strength.clamp(0, 100));
    _persist();
  }

  void setVirtualizer(int strength) {
    state = state.copyWith(virtualizer: strength.clamp(0, 100));
    _persist();
  }

  void setPreampDb(double db) {
    state = state.copyWith(preampDb: db.clamp(-12.0, 3.0));
    _persist();
  }

  void setLimiterEnabled(bool enabled) {
    state = state.copyWith(limiterEnabled: enabled);
    _persist();
  }

  void setCrossfadeSeconds(int seconds) {
    state = state.copyWith(crossfadeSeconds: seconds.clamp(0, 12));
    _persist();
  }

  void setSmartGapless(bool enabled) {
    state = state.copyWith(smartGapless: enabled);
    _persist();
  }

  void setNormalizeVolume(bool enabled) {
    state = state.copyWith(normalizeVolume: enabled);
    _persist();
  }

  void resetToFlat() {
    setPreset(AudioPresets.flatId);
  }

  void saveCustomPreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final preset = AudioPreset(
      id: id,
      name: trimmed,
      levels: List<int>.from(state.bandLevels),
      bassBoost: state.bassBoost,
      virtualizer: state.virtualizer,
    );
    final updated = Map<String, AudioPreset>.from(state.customPresets);
    updated[id] = preset;
    state = state.copyWith(
      presetId: id,
      customPresets: updated,
    );
    _persist();
  }

  void deleteCustomPreset(String id) {
    final updated = Map<String, AudioPreset>.from(state.customPresets);
    updated.remove(id);
    state = state.copyWith(
      presetId: state.presetId == id ? AudioPresets.flatId : state.presetId,
      customPresets: updated,
    );
    _persist();
  }
}
