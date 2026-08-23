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

const k478AccompanimentTrackIndexes = <int>{1, 2, 3};
const k478PerformerTrackIndexes = <int>{4, 5};

/// 只调度弦乐伴奏轨，钢琴声部由外接电子琴自己发声。
///
/// transport 操作和引擎操作分别串行化：前者保证 pause/seek/stop/play 的
/// 状态顺序，后者保证 allNotesOff 完成后才恢复 Program、CC 和 Note On。
class K478PlayerController extends ChangeNotifier {
  static const _uiNotifyInterval = Duration(milliseconds: 33);

  final MidiPlaybackEngine _engine;
  Future<void> _transportTail = Future<void>.value();
  Future<void> _engineTail = Future<void>.value();

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
  double? _pauseAtTime;
  Completer<void>? _pauseAtCompleter;
  bool _pauseTransitionPending = false;
  Timer? _ticker;
  DateTime? _lastTickAt;
  DateTime? _lastUiNotifyAt;
  bool _disposed = false;
  bool _engineDisposeScheduled = false;
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
    return tempoMap == null ? 120 : tempoMap.getBpmAtTick(currentTick);
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

  Future<void> loadSong(MidiSongData song) => _enqueueTransport(() async {
    if (_disposed) return;
    await _stopInternal(notify: false);
    if (_disposed) return;
    _song = song;
    _tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    _currentEventIndex = 0;
    _currentTime = 0;
    await _restoreChannelStateAtCurrentPosition();
    if (_disposed) return;
    _notifyListeners();
  });

  Future<void> prepareSoundfont() async {
    if (_disposed || _soundfontState == SoundfontState.loading) return;
    _soundfontState = SoundfontState.loading;
    _soundfontError = null;
    _notifyListeners();
    try {
      // 与所有音源命令共用队列：dispose 会接在本次加载之后，避免加载中
      // 释放底层 sampler；队列的错误恢复语义也让之后的重试仍可执行。
      await _enqueueEngine(
        () => _engine.loadSoundfontsFromAssets(k478SoundfontAssetsByProgram),
      );
      if (_disposed) return;
      _soundfontState = SoundfontState.ready;
      await _restoreChannelStateAtCurrentPosition();
      if (_disposed) return;
    } catch (error) {
      if (_disposed) return;
      _soundfontState = SoundfontState.failed;
      _soundfontError = '弦乐音色加载失败：$error';
    }
    _notifyListeners();
  }

  Future<void> play() => _enqueueTransport(() async {
    if (_disposed || _song == null || !_engine.isReady || isPlaying) return;
    await _restoreChannelStateAtCurrentPosition();
    if (_disposed || _song == null || !_engine.isReady || isPlaying) return;
    _startTicker();
    _notifyListeners();
  });

  Future<void> pause() {
    if (_disposed) return Future<void>.value();
    _cancelScheduledPause();
    return _enqueueTransport(() => _pauseInternal(notify: true));
  }

  Future<void> _pauseInternal({required bool notify}) async {
    if (_disposed || _state != PlaybackState.playing) return;
    _pauseTicker();
    await _silenceActiveNotes();
    if (_disposed) return;
    if (notify) _notifyListeners();
  }

  Future<void> stop() {
    if (_disposed) return Future<void>.value();
    _cancelScheduledPause();
    return _enqueueTransport(() => _stopInternal(notify: true));
  }

  Future<void> _stopInternal({required bool notify}) async {
    if (_disposed) return;
    _pauseTicker(state: PlaybackState.stopped);
    _cancelScheduledPause();
    _currentTime = 0;
    _currentEventIndex = 0;
    await _silenceActiveNotes();
    if (_disposed) return;
    if (notify) _notifyListeners();
  }

  Future<void> seekTo(double seconds) {
    if (_disposed) return Future<void>.value();
    _cancelScheduledPause();
    return _enqueueTransport(() async {
      if (_disposed) return;
      final wasPlaying = isPlaying;
      if (wasPlaying) _pauseTicker();
      await _silenceActiveNotes();
      if (_disposed) return;
      _currentTime = seconds.clamp(0, totalDuration);
      _updateEventIndex();
      await _restoreChannelStateAtCurrentPosition();
      if (_disposed) return;
      if (wasPlaying) _startTicker();
      _notifyListeners();
    });
  }

  /// 请求播放器在谱面边界暂停；用于长休止，不能在匹配上一音时立即静音。
  Future<void> pauseAt(double scoreTime) {
    if (_disposed) return Future<void>.value();
    final boundaryReached = Completer<void>();
    final scheduled = _enqueueTransport(() async {
      if (_disposed) {
        boundaryReached.complete();
        return;
      }
      _cancelScheduledPause();
      _pauseAtTime = scoreTime.clamp(0, totalDuration);
      _pauseAtCompleter = boundaryReached;
      if (!isPlaying || _currentTime >= _pauseAtTime!) {
        await _completeScheduledPauseInternal();
        if (_disposed) return;
      }
    });
    return scheduled.then((_) => boundaryReached.future);
  }

  void setSpeed(double speed) {
    if (_disposed) return;
    _playbackSpeed = speed.clamp(0.25, 2);
    _notifyListeners();
  }

  void setStringsEnabled(bool enabled) {
    if (_disposed || _stringsEnabled == enabled) return;
    _stringsEnabled = enabled;
    if (!enabled) unawaited(_silenceActiveNotes());
    _notifyListeners();
  }

  void setStringsVolume(double volume) {
    if (_disposed) return;
    _stringsVolume = volume.clamp(0, 1);
    if (_stringsVolume == 0) unawaited(_silenceActiveNotes());
    _notifyListeners();
  }

  void _startTicker() {
    if (_disposed) return;
    _state = PlaybackState.playing;
    _lastTickAt = DateTime.now();
    _lastUiNotifyAt = _lastTickAt;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 5), (_) => _onTick());
  }

  void _pauseTicker({PlaybackState state = PlaybackState.paused}) {
    _state = state;
    _ticker?.cancel();
    _ticker = null;
    _lastTickAt = null;
    _lastUiNotifyAt = null;
  }

  void _onTick() {
    final song = _song;
    final lastTickAt = _lastTickAt;
    if (_disposed || song == null || lastTickAt == null || !isPlaying) return;
    final now = DateTime.now();
    _currentTime +=
        now.difference(lastTickAt).inMicroseconds / 1000000 * _playbackSpeed;
    _lastTickAt = now;
    final pauseAt = _pauseAtTime;
    if (pauseAt != null &&
        _currentTime >= pauseAt &&
        !_pauseTransitionPending) {
      _currentTime = pauseAt;
      _pauseTransitionPending = true;
      _processEvents();
      unawaited(_completeScheduledPause());
      return;
    }
    if (_currentTime >= song.totalDuration) {
      unawaited(stop());
      return;
    }
    _processEvents();
    final lastUiNotifyAt = _lastUiNotifyAt;
    if (lastUiNotifyAt == null ||
        now.difference(lastUiNotifyAt) >= _uiNotifyInterval) {
      _lastUiNotifyAt = now;
      _notifyListeners();
    }
  }

  void _processEvents() {
    final song = _song;
    if (song == null) return;
    while (_currentEventIndex < song.timeline.length) {
      final event = song.timeline[_currentEventIndex];
      if (event.time > _currentTime) return;
      _currentEventIndex++;
      unawaited(_dispatchAccompanimentEvent(event));
    }
  }

  Future<void> _dispatchAccompanimentEvent(TimelineEvent event) {
    if (!k478AccompanimentTrackIndexes.contains(event.trackIndex)) {
      return Future<void>.value();
    }
    return _enqueueEngine(() async {
      if (_disposed) return;
      switch (event.type) {
        case MidiEventType.noteOn:
          if (_disposed || !_stringsEnabled) return;
          final velocity = (event.data2 * _stringsVolume).round().clamp(0, 127);
          if (velocity == 0) return;
          _rememberActiveNote(event);
          try {
            await _engine.noteOn(
              channel: event.channel,
              note: event.data1,
              velocity: velocity,
            );
          } catch (_) {
            if (_disposed) return;
            _releaseActiveNote(event);
          }
          break;
        case MidiEventType.noteOff:
          if (_disposed) return;
          if (_releaseActiveNote(event)) {
            await _ignoreEngineError(
              _engine.noteOff(channel: event.channel, note: event.data1),
            );
          }
          break;
        case MidiEventType.programChange:
          if (_disposed) return;
          await _ignoreEngineError(
            _engine.setInstrument(channel: event.channel, program: event.data1),
          );
          break;
        case MidiEventType.controlChange:
          // 当前 K.478 资产只使用 CC7 音量；其他控制器不扩张候选范围。
          if (!_disposed && event.data1 == 7) {
            await _ignoreEngineError(
              _engine.controlChange(
                channel: event.channel,
                controller: 7,
                value: event.data2,
              ),
            );
          }
          break;
        default:
          break;
      }
    });
  }

  Future<void> _restoreChannelStateAtCurrentPosition() =>
      _enqueueEngine(() async {
        if (_disposed) return;
        final song = _song;
        if (song == null || !_engine.isReady) return;
        final programByChannel = <int, int>{};
        final volumeByChannel = <int, int>{};
        for (final event in song.timeline) {
          if (!k478AccompanimentTrackIndexes.contains(event.trackIndex) ||
              event.time > _currentTime) {
            continue;
          }
          if (event.type == MidiEventType.programChange) {
            programByChannel[event.channel] = event.data1;
          } else if (event.type == MidiEventType.controlChange &&
              event.data1 == 7) {
            volumeByChannel[event.channel] = event.data2;
          }
        }
        for (final entry in programByChannel.entries) {
          if (_disposed) return;
          await _ignoreEngineError(
            _engine.setInstrument(channel: entry.key, program: entry.value),
          );
          if (_disposed) return;
        }
        for (final entry in volumeByChannel.entries) {
          if (_disposed) return;
          await _ignoreEngineError(
            _engine.controlChange(
              channel: entry.key,
              controller: 7,
              value: entry.value,
            ),
          );
          if (_disposed) return;
        }
      });

  Future<void> _silenceActiveNotes() {
    if (_disposed) return Future<void>.value();
    _activeNotes.clear();
    return _enqueueEngine(() => _ignoreEngineError(_engine.allNotesOff()));
  }

  /// 完成已经计划的边界暂停，并让 [pauseAt] 的 Future 只在 allNotesOff
  /// 完成后返回。该方法不等待自身所在的 transport 队列，避免死锁。
  Future<void> _completeScheduledPause() =>
      _enqueueTransport(_completeScheduledPauseInternal);

  Future<void> _completeScheduledPauseInternal() async {
    final completer = _pauseAtCompleter;
    if (completer == null) return;
    if (_disposed) {
      if (!completer.isCompleted) completer.complete();
      return;
    }
    _pauseAtTime = null;
    _pauseTransitionPending = false;
    await _pauseInternal(notify: true);
    if (_disposed) {
      if (!completer.isCompleted) completer.complete();
      return;
    }
    if (identical(_pauseAtCompleter, completer)) {
      _pauseAtCompleter = null;
    }
    if (!completer.isCompleted) completer.complete();
  }

  void _cancelScheduledPause() {
    _pauseAtTime = null;
    _pauseTransitionPending = false;
    final completer = _pauseAtCompleter;
    _pauseAtCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> _enqueueTransport(Future<void> Function() operation) {
    final next = _transportTail.catchError((Object _) {}).then<void>((_) async {
      if (_disposed) return;
      await operation();
    });
    _transportTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _enqueueEngine(Future<void> Function() operation) {
    final next = _engineTail.catchError((Object _) {}).then<void>((_) async {
      if (_disposed) return;
      await operation();
    });
    _engineTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _ignoreEngineError(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {}
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  void _updateEventIndex() {
    final song = _song;
    if (song == null) return;
    var low = 0;
    var high = song.timeline.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (song.timeline[middle].time <= _currentTime) {
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pauseTicker(state: PlaybackState.stopped);
    _cancelScheduledPause();
    _activeNotes.clear();
    if (!_engineDisposeScheduled) {
      _engineDisposeScheduled = true;
      final transportAtDispose = _transportTail;
      unawaited(_disposeEngineAfterPendingWork(transportAtDispose));
    }
    super.dispose();
  }

  Future<void> _disposeEngineAfterPendingWork(
    Future<void> transportAtDispose,
  ) async {
    await transportAtDispose.catchError((Object _) {});
    // transport continuation 可能在其末尾追加引擎操作；必须在 transport
    // 完整结束后读取最新 tail，才能保证底层 engine 最后才释放。
    final engineAtTransportCompletion = _engineTail;
    await engineAtTransportCompletion.catchError((Object _) {});
    try {
      await _engine.dispose();
    } catch (_) {
      // ChangeNotifier 已释放；底层清理失败不应产生未处理异步错误。
    }
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
