import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../follow/follow_mode_controller.dart';
import '../follow/follow_mode_session.dart';
import '../follow/onset_detector.dart';
import 'song_session_models.dart';

abstract class AppSettingsStorage {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> values);
}

class FileAppSettingsStorage implements AppSettingsStorage {
  static const _fileName = 'settings.json';
  static const _backupFileName = 'settings.backup.json';

  final Future<Directory> Function() _directoryProvider;

  FileAppSettingsStorage({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  @override
  Future<Map<String, Object?>> read() async {
    final file = await _settingsFile();
    final backupFile = await _backupFile();

    try {
      if (await file.exists()) {
        return await _readJsonMap(file);
      }
    } catch (_) {
      // Fall through to backup recovery.
    }

    try {
      if (await backupFile.exists()) {
        return await _readJsonMap(backupFile);
      }
    } catch (_) {}

    return const {};
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    final file = await _settingsFile();
    final backupFile = await _backupFile();
    final tempFile = File('${file.path}.tmp');
    await file.parent.create(recursive: true);

    if (await file.exists()) {
      try {
        await _readJsonMap(file);
        await file.copy(backupFile.path);
      } catch (_) {
        // Do not replace a valid backup with a malformed primary file.
      }
    }

    await tempFile.writeAsString(jsonEncode(values), flush: true);
    await tempFile.rename(file.path);
    await file.copy(backupFile.path);
  }

  Future<File> _settingsFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_fileName');
  }

  Future<File> _backupFile() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$_backupFileName');
  }

  Future<Map<String, Object?>> _readJsonMap(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Settings JSON must be an object');
    }
    return Map<String, Object?>.from(decoded);
  }
}

class AppSettingsController extends ChangeNotifier {
  static const int settingsSchemaVersion = 2;
  static const int maxRecentMidiEntries = 20;
  static const double defaultPlaybackSpeedValue = 1.0;
  static const double defaultMicrophoneMinPrecisionValue = 0.6;
  static const double defaultOnsetVolumeThresholdValue = 0.0005;
  static const int defaultNoteMatchToleranceValue = 0;
  static const bool defaultAllowOctaveErrorValue = false;
  static const double defaultMinMeasuredSpeedFactorValue = 0.6;
  static const double defaultMaxMeasuredSpeedFactorValue = 1.6;
  static const double defaultRestThresholdSecondsValue = 1.0;
  static const int defaultInputLatencyCompensationMsValue = 0;
  static const bool defaultLoopPlaybackValue = false;
  static const bool defaultAutoStopAllNotesValue = true;
  static const bool defaultShowDebugInfoValue = false;

  final AppSettingsStorage _storage;

  double _defaultPlaybackSpeed = defaultPlaybackSpeedValue;
  double _microphoneMinPrecision = defaultMicrophoneMinPrecisionValue;
  double _onsetVolumeThreshold = defaultOnsetVolumeThresholdValue;
  int _noteMatchTolerance = defaultNoteMatchToleranceValue;
  bool _allowOctaveError = defaultAllowOctaveErrorValue;
  double _minMeasuredSpeedFactor = defaultMinMeasuredSpeedFactorValue;
  double _maxMeasuredSpeedFactor = defaultMaxMeasuredSpeedFactorValue;
  double _restThresholdSeconds = defaultRestThresholdSecondsValue;
  int _inputLatencyCompensationMs = defaultInputLatencyCompensationMsValue;
  bool _loopPlayback = defaultLoopPlaybackValue;
  bool _autoStopAllNotes = defaultAutoStopAllNotesValue;
  bool _showDebugInfo = defaultShowDebugInfoValue;
  List<RecentMidiEntry> _recentMidiEntries = const [];
  Map<String, MidiSessionSnapshot> _songSessions = const {};
  bool _isLoaded = false;
  Future<void> _pendingWrite = Future<void>.value();
  Object? _lastPersistenceError;

  AppSettingsController({AppSettingsStorage? storage})
    : _storage = storage ?? FileAppSettingsStorage();

  double get defaultPlaybackSpeed => _defaultPlaybackSpeed;
  double get microphoneMinPrecision => _microphoneMinPrecision;
  double get onsetVolumeThreshold => _onsetVolumeThreshold;
  int get noteMatchTolerance => _noteMatchTolerance;
  bool get allowOctaveError => _allowOctaveError;
  double get minMeasuredSpeedFactor => _minMeasuredSpeedFactor;
  double get maxMeasuredSpeedFactor => _maxMeasuredSpeedFactor;
  double get restThresholdSeconds => _restThresholdSeconds;
  int get inputLatencyCompensationMs => _inputLatencyCompensationMs;
  bool get loopPlayback => _loopPlayback;
  bool get autoStopAllNotes => _autoStopAllNotes;
  bool get showDebugInfo => _showDebugInfo;
  List<RecentMidiEntry> get recentMidiEntries =>
      List.unmodifiable(_recentMidiEntries);
  bool get isLoaded => _isLoaded;
  Object? get lastPersistenceError => _lastPersistenceError;

  FollowModeSessionConfig get followSessionConfig =>
      FollowModeSessionConfig(minPrecision: _microphoneMinPrecision);

  OnsetDetectorConfig get onsetDetectorConfig => OnsetDetectorConfig(
    volumeThreshold: _onsetVolumeThreshold,
    precisionThreshold: _microphoneMinPrecision,
    inputLatencyCompensationMs: _inputLatencyCompensationMs,
  );

  FollowModeConfig get followModeConfig => FollowModeConfig(
    noteMatchTolerance: _noteMatchTolerance,
    allowOctaveError: _allowOctaveError,
    minMeasuredSpeedFactor: _minMeasuredSpeedFactor,
    maxMeasuredSpeedFactor: _maxMeasuredSpeedFactor,
    restThresholdSeconds: _restThresholdSeconds,
  );

  Future<void> load() async {
    var values = const <String, Object?>{};
    try {
      values = await _storage.read();
      final storedSchemaVersion = _readInt(
        values,
        'schemaVersion',
        0,
        min: 0,
        max: settingsSchemaVersion,
      );
      _defaultPlaybackSpeed = _readDouble(
        values,
        'defaultPlaybackSpeed',
        defaultPlaybackSpeedValue,
        min: 0.25,
        max: 4.0,
      );
      _microphoneMinPrecision = _readDouble(
        values,
        'microphoneMinPrecision',
        defaultMicrophoneMinPrecisionValue,
        min: 0.4,
        max: 0.95,
      );
      _onsetVolumeThreshold = _readDouble(
        values,
        'onsetVolumeThreshold',
        defaultOnsetVolumeThresholdValue,
        min: 0.0001,
        max: 0.005,
      );
      _noteMatchTolerance = storedSchemaVersion < 2
          ? defaultNoteMatchToleranceValue
          : _readInt(
              values,
              'noteMatchTolerance',
              defaultNoteMatchToleranceValue,
              min: 0,
              max: 4,
            );
      _allowOctaveError = storedSchemaVersion < 2
          ? defaultAllowOctaveErrorValue
          : _readBool(values, 'allowOctaveError', defaultAllowOctaveErrorValue);
      _minMeasuredSpeedFactor = _readDouble(
        values,
        'minMeasuredSpeedFactor',
        defaultMinMeasuredSpeedFactorValue,
        min: 0.4,
        max: 1.0,
      );
      _maxMeasuredSpeedFactor = _readDouble(
        values,
        'maxMeasuredSpeedFactor',
        defaultMaxMeasuredSpeedFactorValue,
        min: 1.0,
        max: 2.2,
      );
      _restThresholdSeconds = _readDouble(
        values,
        'restThresholdSeconds',
        defaultRestThresholdSecondsValue,
        min: 0.5,
        max: 3.0,
      );
      _inputLatencyCompensationMs = _readInt(
        values,
        'inputLatencyCompensationMs',
        defaultInputLatencyCompensationMsValue,
        min: -300,
        max: 300,
      );
      _loopPlayback = _readBool(
        values,
        'loopPlayback',
        defaultLoopPlaybackValue,
      );
      _autoStopAllNotes = _readBool(
        values,
        'autoStopAllNotes',
        defaultAutoStopAllNotesValue,
      );
      _showDebugInfo = _readBool(
        values,
        'showDebugInfo',
        defaultShowDebugInfoValue,
      );
      _recentMidiEntries = _readRecentMidiEntries(values);
      _songSessions = _readSongSessions(values, _recentMidiEntries);
      _normalizeMeasuredSpeedRange();
    } catch (error) {
      _lastPersistenceError = error;
      // Keep safe defaults if the settings file is missing or malformed.
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  void setDefaultPlaybackSpeed(double value) {
    _update(() => _defaultPlaybackSpeed = _clampDouble(value, 0.25, 4.0));
  }

  void setMicrophoneMinPrecision(double value) {
    _update(() => _microphoneMinPrecision = _clampDouble(value, 0.4, 0.95));
  }

  void setOnsetVolumeThreshold(double value) {
    _update(() => _onsetVolumeThreshold = _clampDouble(value, 0.0001, 0.005));
  }

  void setNoteMatchTolerance(int value) {
    _update(() => _noteMatchTolerance = _clampInt(value, 0, 4));
  }

  void setAllowOctaveError({required bool value}) {
    _update(() => _allowOctaveError = value);
  }

  void setMinMeasuredSpeedFactor(double value) {
    _update(() {
      _minMeasuredSpeedFactor = _clampDouble(value, 0.4, 1.0);
      _normalizeMeasuredSpeedRange();
    });
  }

  void setMaxMeasuredSpeedFactor(double value) {
    _update(() {
      _maxMeasuredSpeedFactor = _clampDouble(value, 1.0, 2.2);
      _normalizeMeasuredSpeedRange();
    });
  }

  void setRestThresholdSeconds(double value) {
    _update(() => _restThresholdSeconds = _clampDouble(value, 0.5, 3.0));
  }

  void setInputLatencyCompensationMs(int value) {
    _update(() => _inputLatencyCompensationMs = _clampInt(value, -300, 300));
  }

  void setLoopPlayback({required bool value}) {
    _update(() => _loopPlayback = value);
  }

  void setAutoStopAllNotes({required bool value}) {
    _update(() => _autoStopAllNotes = value);
  }

  void setShowDebugInfo({required bool value}) {
    _update(() => _showDebugInfo = value);
  }

  MidiSessionSnapshot? sessionForSong(String songId) => _songSessions[songId];

  void recordMidiImported(RecentMidiEntry entry) {
    _update(() {
      final nowMs = _nowMs();
      final existing = _recentMidiEntries.where((item) => item.id == entry.id);
      final importedAtMs = existing.isEmpty
          ? entry.importedAtMs
          : existing.first.importedAtMs;
      final updatedEntry = entry.copyWith(
        importedAtMs: importedAtMs,
        lastOpenedAtMs: nowMs,
      );
      _recentMidiEntries = [
        updatedEntry,
        ..._recentMidiEntries.where((item) => item.id != entry.id),
      ]..sort((a, b) => b.lastOpenedAtMs.compareTo(a.lastOpenedAtMs));
      if (_recentMidiEntries.length > maxRecentMidiEntries) {
        _recentMidiEntries = _recentMidiEntries
            .take(maxRecentMidiEntries)
            .toList();
      }
      _pruneSongSessions();
    });
  }

  void saveSessionSnapshot(MidiSessionSnapshot snapshot) {
    _update(() {
      _songSessions = {
        ..._songSessions,
        snapshot.songId: snapshot.copyWith(updatedAtMs: _nowMs()),
      };
    });
  }

  void updateSongPosition(
    String songId,
    double currentTime, {
    double? playbackSpeed,
  }) {
    _updateSession(songId, (session, nowMs) {
      return session.copyWith(
        currentTime: _clampDouble(currentTime, 0.0, (1 << 30).toDouble()),
        playbackSpeed: playbackSpeed == null
            ? session.playbackSpeed
            : _clampDouble(playbackSpeed, 0.25, 4.0),
        updatedAtMs: nowMs,
      );
    });
  }

  void setMelodyTrack(String songId, int? trackIndex) {
    _updateSession(songId, (session, nowMs) {
      return session.copyWith(melodyTrackIndex: trackIndex, updatedAtMs: nowMs);
    });
  }

  void updateTrackPreference(
    String songId,
    int trackIndex,
    TrackPreference preference,
  ) {
    _updateSession(songId, (session, nowMs) {
      final preferences = Map<int, TrackPreference>.from(
        session.trackPreferences,
      );
      preferences[trackIndex] = TrackPreference(
        isMuted: preference.isMuted,
        volume: _clampDouble(preference.volume, 0, 1),
      );
      return session.copyWith(
        trackPreferences: preferences,
        updatedAtMs: nowMs,
      );
    });
  }

  void removeRecentMidi(String songId) {
    _update(() {
      _recentMidiEntries = _recentMidiEntries
          .where((entry) => entry.id != songId)
          .toList();
      _songSessions = Map<String, MidiSessionSnapshot>.from(_songSessions)
        ..remove(songId);
    });
  }

  void clearRecentMidi() {
    _update(() {
      _recentMidiEntries = const [];
      _songSessions = const {};
    });
  }

  void resetToDefaults() {
    _update(() {
      _defaultPlaybackSpeed = defaultPlaybackSpeedValue;
      _microphoneMinPrecision = defaultMicrophoneMinPrecisionValue;
      _onsetVolumeThreshold = defaultOnsetVolumeThresholdValue;
      _noteMatchTolerance = defaultNoteMatchToleranceValue;
      _allowOctaveError = defaultAllowOctaveErrorValue;
      _minMeasuredSpeedFactor = defaultMinMeasuredSpeedFactorValue;
      _maxMeasuredSpeedFactor = defaultMaxMeasuredSpeedFactorValue;
      _restThresholdSeconds = defaultRestThresholdSecondsValue;
      _inputLatencyCompensationMs = defaultInputLatencyCompensationMsValue;
      _loopPlayback = defaultLoopPlaybackValue;
      _autoStopAllNotes = defaultAutoStopAllNotesValue;
      _showDebugInfo = defaultShowDebugInfoValue;
    });
  }

  Future<void> flush() => _pendingWrite;

  void _update(VoidCallback updateValues) {
    updateValues();
    notifyListeners();
    _enqueueWrite(_toJson());
  }

  void _enqueueWrite(Map<String, Object?> values) {
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await _storage.write(values);
        _lastPersistenceError = null;
      } catch (error) {
        _lastPersistenceError = error;
      }
    });
    unawaited(_pendingWrite);
  }

  Map<String, Object?> _toJson() => {
    'schemaVersion': settingsSchemaVersion,
    'defaultPlaybackSpeed': _defaultPlaybackSpeed,
    'microphoneMinPrecision': _microphoneMinPrecision,
    'onsetVolumeThreshold': _onsetVolumeThreshold,
    'noteMatchTolerance': _noteMatchTolerance,
    'allowOctaveError': _allowOctaveError,
    'minMeasuredSpeedFactor': _minMeasuredSpeedFactor,
    'maxMeasuredSpeedFactor': _maxMeasuredSpeedFactor,
    'restThresholdSeconds': _restThresholdSeconds,
    'inputLatencyCompensationMs': _inputLatencyCompensationMs,
    'loopPlayback': _loopPlayback,
    'autoStopAllNotes': _autoStopAllNotes,
    'showDebugInfo': _showDebugInfo,
    'recentMidiEntries': _recentMidiEntries
        .map((entry) => entry.toJson())
        .toList(),
    'songSessions': _songSessions.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  void _updateSession(
    String songId,
    MidiSessionSnapshot Function(MidiSessionSnapshot session, int nowMs) update,
  ) {
    _update(() {
      final nowMs = _nowMs();
      final current =
          _songSessions[songId] ?? MidiSessionSnapshot.empty(songId, nowMs);
      _songSessions = {..._songSessions, songId: update(current, nowMs)};
    });
  }

  List<RecentMidiEntry> _readRecentMidiEntries(Map<String, Object?> values) {
    final raw = values['recentMidiEntries'];
    if (raw is! List) return const [];
    final entries = <RecentMidiEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        entries.add(RecentMidiEntry.fromJson(Map<String, Object?>.from(item)));
      } catch (_) {}
    }
    entries.sort((a, b) => b.lastOpenedAtMs.compareTo(a.lastOpenedAtMs));
    return entries.take(maxRecentMidiEntries).toList();
  }

  Map<String, MidiSessionSnapshot> _readSongSessions(
    Map<String, Object?> values,
    List<RecentMidiEntry> recentEntries,
  ) {
    final raw = values['songSessions'];
    if (raw is! Map) return const {};
    final recentIds = recentEntries.map((entry) => entry.id).toSet();
    final sessions = <String, MidiSessionSnapshot>{};
    for (final entry in raw.entries) {
      final songId = entry.key.toString();
      final value = entry.value;
      if (!recentIds.contains(songId) || value is! Map) continue;
      try {
        sessions[songId] = MidiSessionSnapshot.fromJson(
          Map<String, Object?>.from(value),
        );
      } catch (_) {}
    }
    return sessions;
  }

  void _pruneSongSessions() {
    final recentIds = _recentMidiEntries.map((entry) => entry.id).toSet();
    _songSessions = Map<String, MidiSessionSnapshot>.from(_songSessions)
      ..removeWhere((songId, _) => !recentIds.contains(songId));
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  void _normalizeMeasuredSpeedRange() {
    if (_minMeasuredSpeedFactor > _maxMeasuredSpeedFactor) {
      _minMeasuredSpeedFactor = _maxMeasuredSpeedFactor;
    }
  }

  double _readDouble(
    Map<String, Object?> values,
    String key,
    double fallback, {
    required double min,
    required double max,
  }) {
    final value = values[key];
    if (value is num) {
      return _clampDouble(value.toDouble(), min, max);
    }
    return fallback;
  }

  int _readInt(
    Map<String, Object?> values,
    String key,
    int fallback, {
    required int min,
    required int max,
  }) {
    final value = values[key];
    if (value is num) {
      return _clampInt(value.round(), min, max);
    }
    return fallback;
  }

  bool _readBool(Map<String, Object?> values, String key, bool fallback) {
    final value = values[key];
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  double _clampDouble(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
