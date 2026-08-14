import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../follow/follow_mode_controller.dart';
import '../follow/follow_mode_session.dart';
import '../follow/onset_detector.dart';
import '../../models/midi_score_part.dart';
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
  static const int settingsSchemaVersion = 3;
  static const int maxRecentMidiEntries = 20;
  static const int maxSongScorePartSelections = 100;
  static const int maxScorePartIdsPerSong = 64;
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
  static const defaultScorePartKindsValue = {MidiPartKind.piano};

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
  Set<MidiPartKind> _defaultScorePartKinds = defaultScorePartKindsValue;
  Map<String, Set<String>> _songScorePartSelections = const {};
  bool _isLoaded = false;
  Future<void>? _loadFuture;
  Future<void> _pendingWrite = Future<void>.value();
  Future<void> _pendingScorePartTransaction = Future<void>.value();
  final Map<_ResettableSettingsField, int> _resettableFieldRevisions = {};
  int _settingsRevision = 0;
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
  Set<MidiPartKind> get defaultScorePartKinds =>
      Set<MidiPartKind>.unmodifiable(_defaultScorePartKinds);

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

  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
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
      _defaultScorePartKinds = _readDefaultScorePartKinds(values);
      _songScorePartSelections = _readSongScorePartSelections(values);
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
    _update(
      () => _defaultPlaybackSpeed = _clampDouble(value, 0.25, 4.0),
      resettableFields: {_ResettableSettingsField.defaultPlaybackSpeed},
    );
  }

  void setMicrophoneMinPrecision(double value) {
    _update(
      () => _microphoneMinPrecision = _clampDouble(value, 0.4, 0.95),
      resettableFields: {_ResettableSettingsField.microphoneMinPrecision},
    );
  }

  void setOnsetVolumeThreshold(double value) {
    _update(
      () => _onsetVolumeThreshold = _clampDouble(value, 0.0001, 0.005),
      resettableFields: {_ResettableSettingsField.onsetVolumeThreshold},
    );
  }

  void setNoteMatchTolerance(int value) {
    _update(
      () => _noteMatchTolerance = _clampInt(value, 0, 4),
      resettableFields: {_ResettableSettingsField.noteMatchTolerance},
    );
  }

  void setAllowOctaveError({required bool value}) {
    _update(
      () => _allowOctaveError = value,
      resettableFields: {_ResettableSettingsField.allowOctaveError},
    );
  }

  void setMinMeasuredSpeedFactor(double value) {
    _update(() {
      _minMeasuredSpeedFactor = _clampDouble(value, 0.4, 1.0);
      _normalizeMeasuredSpeedRange();
    }, resettableFields: {_ResettableSettingsField.minMeasuredSpeedFactor});
  }

  void setMaxMeasuredSpeedFactor(double value) {
    _update(() {
      _maxMeasuredSpeedFactor = _clampDouble(value, 1.0, 2.2);
      _normalizeMeasuredSpeedRange();
    }, resettableFields: {_ResettableSettingsField.maxMeasuredSpeedFactor});
  }

  void setRestThresholdSeconds(double value) {
    _update(
      () => _restThresholdSeconds = _clampDouble(value, 0.5, 3.0),
      resettableFields: {_ResettableSettingsField.restThresholdSeconds},
    );
  }

  void setInputLatencyCompensationMs(int value) {
    _update(
      () => _inputLatencyCompensationMs = _clampInt(value, -300, 300),
      resettableFields: {_ResettableSettingsField.inputLatencyCompensationMs},
    );
  }

  void setLoopPlayback({required bool value}) {
    _update(
      () => _loopPlayback = value,
      resettableFields: {_ResettableSettingsField.loopPlayback},
    );
  }

  void setAutoStopAllNotes({required bool value}) {
    _update(
      () => _autoStopAllNotes = value,
      resettableFields: {_ResettableSettingsField.autoStopAllNotes},
    );
  }

  void setShowDebugInfo({required bool value}) {
    _update(
      () => _showDebugInfo = value,
      resettableFields: {_ResettableSettingsField.showDebugInfo},
    );
  }

  Set<String>? scorePartSelectionForSong(String fingerprint) {
    final selection = _songScorePartSelections[fingerprint.trim()];
    return selection == null ? null : Set<String>.unmodifiable(selection);
  }

  Future<void> setDefaultScorePartKinds(Set<MidiPartKind> kinds) {
    final next = kinds.isEmpty
        ? defaultScorePartKindsValue
        : Set<MidiPartKind>.of(kinds);
    return _runScorePartTransaction(() {
      _defaultScorePartKinds = next;
      return true;
    });
  }

  Future<void> setScorePartSelectionForSong(
    String fingerprint,
    Set<String> partIds,
  ) {
    final normalizedFingerprint = fingerprint.trim();
    if (normalizedFingerprint.isEmpty) return Future<void>.value();
    final normalizedPartIds = _normalizedPartIds(partIds);
    if (normalizedPartIds.isEmpty) {
      return clearScorePartSelectionForSong(normalizedFingerprint);
    }
    return _runScorePartTransaction(() {
      final updated = Map<String, Set<String>>.from(_songScorePartSelections)
        ..[normalizedFingerprint] = normalizedPartIds;
      _songScorePartSelections = _sortedSongScorePartSelections(
        updated,
        preserveKey: normalizedFingerprint,
      );
      return true;
    });
  }

  Future<void> clearScorePartSelectionForSong(String fingerprint) {
    final normalizedFingerprint = fingerprint.trim();
    return _runScorePartTransaction(() {
      if (!_songScorePartSelections.containsKey(normalizedFingerprint)) {
        return false;
      }
      _songScorePartSelections = Map<String, Set<String>>.from(
        _songScorePartSelections,
      )..remove(normalizedFingerprint);
      return true;
    });
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

  Future<void> resetToDefaults() {
    final invokedAtRevision = _settingsRevision;
    final operation = _pendingScorePartTransaction.then((_) async {
      final snapshot = _ResettableSettingsSnapshot.capture(this);
      final previousRevisions = Map<_ResettableSettingsField, int>.from(
        _resettableFieldRevisions,
      );
      final resetRevision = ++_settingsRevision;
      _applyResetDefaults(
        invokedAtRevision: invokedAtRevision,
        resetRevision: resetRevision,
      );
      notifyListeners();
      try {
        await _enqueueWrite(_toJson());
      } catch (error, stackTrace) {
        _lastPersistenceError = error;
        final restoredFields = snapshot.restoreFieldsStillAtRevision(
          this,
          resetRevision,
        );
        for (final field in restoredFields) {
          final previousRevision = previousRevisions[field];
          if (previousRevision == null) {
            _resettableFieldRevisions.remove(field);
          } else {
            _resettableFieldRevisions[field] = previousRevision;
          }
        }
        if (restoredFields.isNotEmpty) notifyListeners();
        try {
          await _enqueueWrite(_toJson());
        } catch (_) {
          // Preserve the original reset error while leaving the queue usable.
        }
        _lastPersistenceError = error;
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    _pendingScorePartTransaction = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(_pendingScorePartTransaction);
    return operation;
  }

  void _applyResetDefaults({
    required int invokedAtRevision,
    required int resetRevision,
  }) {
    void reset(_ResettableSettingsField field, VoidCallback apply) {
      final fieldRevision = _resettableFieldRevisions[field] ?? 0;
      if (fieldRevision > invokedAtRevision) return;
      apply();
      _resettableFieldRevisions[field] = resetRevision;
    }

    reset(
      _ResettableSettingsField.defaultPlaybackSpeed,
      () => _defaultPlaybackSpeed = defaultPlaybackSpeedValue,
    );
    reset(
      _ResettableSettingsField.microphoneMinPrecision,
      () => _microphoneMinPrecision = defaultMicrophoneMinPrecisionValue,
    );
    reset(
      _ResettableSettingsField.onsetVolumeThreshold,
      () => _onsetVolumeThreshold = defaultOnsetVolumeThresholdValue,
    );
    reset(
      _ResettableSettingsField.noteMatchTolerance,
      () => _noteMatchTolerance = defaultNoteMatchToleranceValue,
    );
    reset(
      _ResettableSettingsField.allowOctaveError,
      () => _allowOctaveError = defaultAllowOctaveErrorValue,
    );
    reset(
      _ResettableSettingsField.minMeasuredSpeedFactor,
      () => _minMeasuredSpeedFactor = defaultMinMeasuredSpeedFactorValue,
    );
    reset(
      _ResettableSettingsField.maxMeasuredSpeedFactor,
      () => _maxMeasuredSpeedFactor = defaultMaxMeasuredSpeedFactorValue,
    );
    reset(
      _ResettableSettingsField.restThresholdSeconds,
      () => _restThresholdSeconds = defaultRestThresholdSecondsValue,
    );
    reset(
      _ResettableSettingsField.inputLatencyCompensationMs,
      () =>
          _inputLatencyCompensationMs = defaultInputLatencyCompensationMsValue,
    );
    reset(
      _ResettableSettingsField.loopPlayback,
      () => _loopPlayback = defaultLoopPlaybackValue,
    );
    reset(
      _ResettableSettingsField.autoStopAllNotes,
      () => _autoStopAllNotes = defaultAutoStopAllNotesValue,
    );
    reset(
      _ResettableSettingsField.showDebugInfo,
      () => _showDebugInfo = defaultShowDebugInfoValue,
    );
    reset(
      _ResettableSettingsField.defaultScorePartKinds,
      () => _defaultScorePartKinds = defaultScorePartKindsValue,
    );
    reset(
      _ResettableSettingsField.songScorePartSelections,
      () => _songScorePartSelections = const {},
    );
  }

  Future<void> flush() async {
    await _pendingScorePartTransaction;
    await _pendingWrite;
  }

  void _update(
    VoidCallback updateValues, {
    Set<_ResettableSettingsField> resettableFields = const {},
  }) {
    updateValues();
    if (resettableFields.isNotEmpty) {
      final revision = ++_settingsRevision;
      for (final field in resettableFields) {
        _resettableFieldRevisions[field] = revision;
      }
    }
    notifyListeners();
    unawaited(_enqueueWrite(_toJson()).catchError((Object _) {}));
  }

  Future<void> _enqueueWrite(Map<String, Object?> values) {
    final operation = _pendingWrite.then((_) => _storage.write(values));
    _pendingWrite = operation.then<void>(
      (_) {
        _lastPersistenceError = null;
      },
      onError: (Object error, StackTrace _) {
        _lastPersistenceError = error;
      },
    );
    unawaited(_pendingWrite);
    return operation;
  }

  Future<void> _runScorePartTransaction(bool Function() updateValues) {
    final operation = _pendingScorePartTransaction.then((_) async {
      final snapshot = _ScorePartSettingsSnapshot(
        defaultKinds: _defaultScorePartKinds,
        songSelections: _songScorePartSelections,
      );
      if (!updateValues()) return;
      notifyListeners();
      try {
        await _enqueueWrite(_toJson());
      } catch (error, stackTrace) {
        _lastPersistenceError = error;
        _defaultScorePartKinds = snapshot.defaultKinds;
        _songScorePartSelections = snapshot.songSelections;
        notifyListeners();
        try {
          await _enqueueWrite(_toJson());
        } catch (_) {
          // Preserve the original transaction error while leaving the queue
          // available for a later recovery write.
        }
        _lastPersistenceError = error;
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    _pendingScorePartTransaction = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(_pendingScorePartTransaction);
    return operation;
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
    'defaultScorePartKinds':
        _defaultScorePartKinds.map((kind) => kind.name).toList()..sort(),
    'songScorePartSelections': {
      for (final entry in _sortedSongScorePartSelections(
        _songScorePartSelections,
      ).entries)
        entry.key: entry.value.toList()..sort(),
    },
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

  Set<MidiPartKind> _readDefaultScorePartKinds(Map<String, Object?> values) {
    final raw = values['defaultScorePartKinds'];
    if (raw is! List) return defaultScorePartKindsValue;
    final kinds = <MidiPartKind>{};
    for (final value in raw) {
      if (value is! String) continue;
      try {
        kinds.add(MidiPartKind.values.byName(value));
      } on ArgumentError {
        // Ignore unknown persisted enum names.
      }
    }
    return kinds.isEmpty ? defaultScorePartKindsValue : kinds;
  }

  Map<String, Set<String>> _readSongScorePartSelections(
    Map<String, Object?> values,
  ) {
    final raw = values['songScorePartSelections'];
    if (raw is! Map) return const {};
    final selections = <String, Set<String>>{};
    final entries =
        raw.entries
            .where((entry) => entry.key is String)
            .map((entry) => MapEntry((entry.key as String).trim(), entry.value))
            .where((entry) => entry.key.isNotEmpty)
            .toList()
          ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      final value = entry.value;
      if (value is! List) continue;
      final ids = _normalizedPartIds(value.whereType<String>().toSet());
      if (ids.isNotEmpty) selections[entry.key] = ids;
      if (selections.length == maxSongScorePartSelections) break;
    }
    return Map<String, Set<String>>.unmodifiable(selections);
  }

  Set<String> _normalizedPartIds(Set<String> partIds) {
    final sorted =
        partIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Set<String>.unmodifiable(sorted.take(maxScorePartIdsPerSong));
  }

  Map<String, Set<String>> _sortedSongScorePartSelections(
    Map<String, Set<String>> selections, {
    String? preserveKey,
  }) {
    final sortedKeys = selections.keys.toList()..sort();
    if (preserveKey != null && sortedKeys.length > maxSongScorePartSelections) {
      final evictedKey = sortedKeys.lastWhere((key) => key != preserveKey);
      selections.remove(evictedKey);
      return _sortedSongScorePartSelections(selections);
    }
    return Map<String, Set<String>>.unmodifiable({
      for (final key in sortedKeys.take(maxSongScorePartSelections))
        key: _normalizedPartIds(selections[key]!),
    });
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

class _ScorePartSettingsSnapshot {
  final Set<MidiPartKind> defaultKinds;
  final Map<String, Set<String>> songSelections;

  _ScorePartSettingsSnapshot({
    required Set<MidiPartKind> defaultKinds,
    required Map<String, Set<String>> songSelections,
  }) : defaultKinds = Set<MidiPartKind>.of(defaultKinds),
       songSelections = {
         for (final entry in songSelections.entries)
           entry.key: Set<String>.of(entry.value),
       };
}

enum _ResettableSettingsField {
  defaultPlaybackSpeed,
  microphoneMinPrecision,
  onsetVolumeThreshold,
  noteMatchTolerance,
  allowOctaveError,
  minMeasuredSpeedFactor,
  maxMeasuredSpeedFactor,
  restThresholdSeconds,
  inputLatencyCompensationMs,
  loopPlayback,
  autoStopAllNotes,
  showDebugInfo,
  defaultScorePartKinds,
  songScorePartSelections,
}

class _ResettableSettingsSnapshot {
  final double defaultPlaybackSpeed;
  final double microphoneMinPrecision;
  final double onsetVolumeThreshold;
  final int noteMatchTolerance;
  final bool allowOctaveError;
  final double minMeasuredSpeedFactor;
  final double maxMeasuredSpeedFactor;
  final double restThresholdSeconds;
  final int inputLatencyCompensationMs;
  final bool loopPlayback;
  final bool autoStopAllNotes;
  final bool showDebugInfo;
  final Set<MidiPartKind> defaultScorePartKinds;
  final Map<String, Set<String>> songScorePartSelections;

  _ResettableSettingsSnapshot.capture(AppSettingsController settings)
    : defaultPlaybackSpeed = settings._defaultPlaybackSpeed,
      microphoneMinPrecision = settings._microphoneMinPrecision,
      onsetVolumeThreshold = settings._onsetVolumeThreshold,
      noteMatchTolerance = settings._noteMatchTolerance,
      allowOctaveError = settings._allowOctaveError,
      minMeasuredSpeedFactor = settings._minMeasuredSpeedFactor,
      maxMeasuredSpeedFactor = settings._maxMeasuredSpeedFactor,
      restThresholdSeconds = settings._restThresholdSeconds,
      inputLatencyCompensationMs = settings._inputLatencyCompensationMs,
      loopPlayback = settings._loopPlayback,
      autoStopAllNotes = settings._autoStopAllNotes,
      showDebugInfo = settings._showDebugInfo,
      defaultScorePartKinds = Set<MidiPartKind>.of(
        settings._defaultScorePartKinds,
      ),
      songScorePartSelections = {
        for (final entry in settings._songScorePartSelections.entries)
          entry.key: Set<String>.of(entry.value),
      };

  Set<_ResettableSettingsField> restoreFieldsStillAtRevision(
    AppSettingsController settings,
    int resetRevision,
  ) {
    final restored = <_ResettableSettingsField>{};

    void restore(_ResettableSettingsField field, VoidCallback apply) {
      if (settings._resettableFieldRevisions[field] != resetRevision) return;
      apply();
      restored.add(field);
    }

    restore(
      _ResettableSettingsField.defaultPlaybackSpeed,
      () => settings._defaultPlaybackSpeed = defaultPlaybackSpeed,
    );
    restore(
      _ResettableSettingsField.microphoneMinPrecision,
      () => settings._microphoneMinPrecision = microphoneMinPrecision,
    );
    restore(
      _ResettableSettingsField.onsetVolumeThreshold,
      () => settings._onsetVolumeThreshold = onsetVolumeThreshold,
    );
    restore(
      _ResettableSettingsField.noteMatchTolerance,
      () => settings._noteMatchTolerance = noteMatchTolerance,
    );
    restore(
      _ResettableSettingsField.allowOctaveError,
      () => settings._allowOctaveError = allowOctaveError,
    );
    restore(
      _ResettableSettingsField.minMeasuredSpeedFactor,
      () => settings._minMeasuredSpeedFactor = minMeasuredSpeedFactor,
    );
    restore(
      _ResettableSettingsField.maxMeasuredSpeedFactor,
      () => settings._maxMeasuredSpeedFactor = maxMeasuredSpeedFactor,
    );
    restore(
      _ResettableSettingsField.restThresholdSeconds,
      () => settings._restThresholdSeconds = restThresholdSeconds,
    );
    restore(
      _ResettableSettingsField.inputLatencyCompensationMs,
      () => settings._inputLatencyCompensationMs = inputLatencyCompensationMs,
    );
    restore(
      _ResettableSettingsField.loopPlayback,
      () => settings._loopPlayback = loopPlayback,
    );
    restore(
      _ResettableSettingsField.autoStopAllNotes,
      () => settings._autoStopAllNotes = autoStopAllNotes,
    );
    restore(
      _ResettableSettingsField.showDebugInfo,
      () => settings._showDebugInfo = showDebugInfo,
    );
    restore(
      _ResettableSettingsField.defaultScorePartKinds,
      () => settings._defaultScorePartKinds = Set<MidiPartKind>.of(
        defaultScorePartKinds,
      ),
    );
    restore(
      _ResettableSettingsField.songScorePartSelections,
      () => settings._songScorePartSelections = {
        for (final entry in songScorePartSelections.entries)
          entry.key: Set<String>.of(entry.value),
      },
    );
    return restored;
  }
}
