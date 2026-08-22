import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/midi_track.dart';
import 'midi_engine.dart';
import 'tempo_map.dart';

enum PlaybackState { stopped, playing, paused }

enum SoundfontState { idle, loading, ready, failed }

/// TestFlight 候选中的两个内置伴奏音色；钢琴 Program 0 不在此映射中。
const k478SoundfontAssetsByProgram = <int, String>{
  40: 'packages/k478_practice/assets/soundfonts/k478_violin.sf2',
  42: 'packages/k478_practice/assets/soundfonts/k478_cello.sf2',
};

/// K.478 MIDI 中的真实轨道编号（0 为元数据轨）。
const k478AccompanimentTrackIndexes = <int>{1, 2, 3};
const k478PerformerTrackIndexes = <int>{4, 5};

/// 只调度弦乐伴奏轨，钢琴声部由外接电子琴自己发声。
///
/// 这个过滤发生在 Program Change、Note On 和 Note Off 之前，确保只含
/// Program 40/42 的轻量 SoundFont 永远不会被要求加载钢琴 Program 0。
class K478PlayerController extends ChangeNotifier {
  static const _uiNotifyInterval = Duration(milliseconds: 33);

  final MidiPlaybackEngine _engine;

  MidiSongData? _song;
  TempoMap? _tempoMap;
  PlaybackState _state = PlaybackState.stopped;
  SoundfontState _soundfontState = SoundfontState.idle;
  String? _soundfontError;
  double _currentTime = 0;
  double _playbackSpeed = 1;
  double _stringsVolume = 0.82;
  bool _stringsEnabled = true;
  int _currentEventIndex = 0;
  Timer? _ticker;
  DateTime? _lastTickAt;
  DateTime? _lastUiNotifyAt;
  bool _disposed = false;
  final Map<_ActiveNoteKey, int> _activeNotes = {};

  K478PlayerController({MidiPlaybackEngine? engine})
    : _engine = engine ?? MidiEngine();

  MidiSongData? get song => _song;
  PlaybackState get state => _state;
  SoundfontState get soundfontState => _soundfontState;
  String? get soundfontError => _soundfontError;
  double get currentTime => _currentTime;
  double get playbackSpeed => _playbackSpeed;
  double get stringsVolume => _stringsVolume;
  bool get stringsEnabled => _stringsEnabled;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isSoundfontReady => _engine.isReady;
  double get totalDuration => _song?.totalDuration ?? 0;
  double get progress =>
      totalDuration <= 0 ? 0 : (_currentTime / totalDuration).clamp(0, 1);
  double get currentBpm {
    final tempoMap = _tempoMap;
    if (tempoMap == null) return 120;
    return tempoMap.getBpmAtTick(currentTick);
  }

  int get currentTick {
    final tempoMap = _tempoMap;
    final song = _song;
    if (tempoMap == null || song == null) return 0;
    return tempoMap.secondsToTick(_currentTime).clamp(0, song.totalTicks);
  }

  List<MidiTrackInfo> get performerTracks {
    final song = _song;
    if (song == null) return const [];
    return song.tracks
        .where((track) => k478PerformerTrackIndexes.contains(track.index))
        .toList(growable: false);
  }

  void loadSong(MidiSongData song) {
    if (_disposed) return;
    stop();
    _song = song;
    _tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    _currentEventIndex = 0;
    _currentTime = 0;
    _applyProgramStateAtCurrentPosition();
    notifyListeners();
  }

  Future<void> prepareSoundfont() async {
    if (_disposed || _soundfontState == SoundfontState.loading) return;
    _soundfontState = SoundfontState.loading;
    _soundfontError = null;
    notifyListeners();
    try {
      await _engine.loadSoundfontsFromAssets(k478SoundfontAssetsByProgram);
      if (_disposed) return;
      _soundfontState = SoundfontState.ready;
      _applyProgramStateAtCurrentPosition();
    } catch (error) {
      if (_disposed) return;
      _soundfontState = SoundfontState.failed;
      _soundfontError = '弦乐音色加载失败：$error';
    }
    if (!_disposed) notifyListeners();
  }

  void play() {
    if (_disposed || _song == null || !_engine.isReady) return;
    if (_state == PlaybackState.playing) return;
    _state = PlaybackState.playing;
    _lastTickAt = DateTime.now();
    _lastUiNotifyAt = _lastTickAt;
    _ticker = Timer.periodic(const Duration(milliseconds: 5), (_) => _onTick());
    notifyListeners();
  }

  void pause() {
    if (_disposed || _state != PlaybackState.playing) return;
    _state = PlaybackState.paused;
    _ticker?.cancel();
    _ticker = null;
    _lastTickAt = null;
    _lastUiNotifyAt = null;
    _silenceActiveNotes();
    notifyListeners();
  }

  void stop() {
    if (_disposed) return;
    _state = PlaybackState.stopped;
    _ticker?.cancel();
    _ticker = null;
    _lastTickAt = null;
    _lastUiNotifyAt = null;
    _currentTime = 0;
    _currentEventIndex = 0;
    _silenceActiveNotes();
    notifyListeners();
  }

  void seekTo(double seconds) {
    if (_disposed) return;
    final wasPlaying = isPlaying;
    if (wasPlaying) pause();
    _currentTime = seconds.clamp(0, totalDuration);
    _silenceActiveNotes();
    _updateEventIndex();
    _applyProgramStateAtCurrentPosition();
    if (wasPlaying) play();
    notifyListeners();
  }

  void setSpeed(double speed) {
    if (_disposed) return;
    _playbackSpeed = speed.clamp(0.25, 2);
    notifyListeners();
  }

  void setStringsEnabled(bool enabled) {
    if (_disposed || _stringsEnabled == enabled) return;
    _stringsEnabled = enabled;
    if (!enabled) _silenceActiveNotes();
    notifyListeners();
  }

  void setStringsVolume(double volume) {
    if (_disposed) return;
    _stringsVolume = volume.clamp(0, 1);
    if (_stringsVolume == 0) _silenceActiveNotes();
    notifyListeners();
  }

  void _onTick() {
    final song = _song;
    final lastTickAt = _lastTickAt;
    if (_disposed || song == null || lastTickAt == null || !isPlaying) return;

    final now = DateTime.now();
    _currentTime +=
        now.difference(lastTickAt).inMicroseconds / 1000000 * _playbackSpeed;
    _lastTickAt = now;
    if (_currentTime >= song.totalDuration) {
      stop();
      return;
    }
    _processEvents();
    final lastUiNotifyAt = _lastUiNotifyAt;
    if (lastUiNotifyAt == null ||
        now.difference(lastUiNotifyAt) >= _uiNotifyInterval) {
      _lastUiNotifyAt = now;
      notifyListeners();
    }
  }

  void _processEvents() {
    final song = _song;
    if (song == null) return;
    final timeline = song.timeline;
    while (_currentEventIndex < timeline.length) {
      final event = timeline[_currentEventIndex];
      if (event.time > _currentTime) return;
      _dispatchAccompanimentEvent(event);
      _currentEventIndex++;
    }
  }

  void _dispatchAccompanimentEvent(TimelineEvent event) {
    if (!k478AccompanimentTrackIndexes.contains(event.trackIndex)) return;
    switch (event.type) {
      case MidiEventType.noteOn:
        if (!_stringsEnabled) return;
        final velocity = (event.data2 * _stringsVolume).round().clamp(0, 127);
        if (velocity == 0) return;
        _rememberActiveNote(event);
        unawaited(
          _engine
              .noteOn(
                channel: event.channel,
                note: event.data1,
                velocity: velocity,
              )
              .catchError((Object _) => _releaseActiveNote(event)),
        );
        break;
      case MidiEventType.noteOff:
        if (_releaseActiveNote(event)) {
          unawaited(
            _engine
                .noteOff(channel: event.channel, note: event.data1)
                .catchError((Object _) {}),
          );
        }
        break;
      case MidiEventType.programChange:
        // 钢琴轨已经在入口处过滤；这里只会选择 40/42。
        unawaited(
          _engine
              .setInstrument(channel: event.channel, program: event.data1)
              .catchError((Object _) {}),
        );
        break;
      default:
        break;
    }
  }

  void _applyProgramStateAtCurrentPosition() {
    final song = _song;
    if (song == null || !_engine.isReady) return;
    final programByChannel = <int, int>{};
    for (final event in song.timeline) {
      if (event.type != MidiEventType.programChange ||
          !k478AccompanimentTrackIndexes.contains(event.trackIndex) ||
          event.time > _currentTime) {
        continue;
      }
      programByChannel[event.channel] = event.data1;
    }
    for (final entry in programByChannel.entries) {
      unawaited(
        _engine
            .setInstrument(channel: entry.key, program: entry.value)
            .catchError((Object _) {}),
      );
    }
  }

  void _updateEventIndex() {
    final song = _song;
    if (song == null) return;
    final timeline = song.timeline;
    var low = 0;
    var high = timeline.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (timeline[middle].time <= _currentTime) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    _currentEventIndex = low;
  }

  void _rememberActiveNote(TimelineEvent event) {
    final key = _ActiveNoteKey(
      trackIndex: event.trackIndex,
      channel: event.channel,
      note: event.data1,
    );
    _activeNotes[key] = (_activeNotes[key] ?? 0) + 1;
  }

  bool _releaseActiveNote(TimelineEvent event) {
    final key = _ActiveNoteKey(
      trackIndex: event.trackIndex,
      channel: event.channel,
      note: event.data1,
    );
    final count = _activeNotes[key];
    if (count == null) return false;
    if (count == 1) {
      _activeNotes.remove(key);
    } else {
      _activeNotes[key] = count - 1;
    }
    return true;
  }

  void _silenceActiveNotes() {
    _activeNotes.clear();
    unawaited(_engine.allNotesOff().catchError((Object _) {}));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _activeNotes.clear();
    unawaited(_engine.dispose().catchError((Object _) {}));
    super.dispose();
  }
}

class _ActiveNoteKey {
  final int trackIndex;
  final int channel;
  final int note;

  const _ActiveNoteKey({
    required this.trackIndex,
    required this.channel,
    required this.note,
  });

  @override
  bool operator ==(Object other) =>
      other is _ActiveNoteKey &&
      other.trackIndex == trackIndex &&
      other.channel == channel &&
      other.note == note;

  @override
  int get hashCode => Object.hash(trackIndex, channel, note);
}
