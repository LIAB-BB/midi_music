import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/midi_track.dart';
import 'midi_engine.dart';
import 'tempo_map.dart';

/// 播放状态
enum PlaybackState { stopped, playing, paused }

enum SoundfontSetupState { idle, checking, downloading, ready, failed }

class SoundfontCacheInfo {
  final String? path;
  final bool exists;
  final int? sizeBytes;
  final bool isUsable;
  final String? errorMessage;

  const SoundfontCacheInfo({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    this.isUsable = false,
    required this.errorMessage,
  });

  const SoundfontCacheInfo.error(String message)
    : path = null,
      exists = false,
      sizeBytes = null,
      isUsable = false,
      errorMessage = message;
}

const _kDefaultSoundfontFileName = 'TimGM6mb.sf2';
const _kMinimumUsableSoundfontBytes = 1024;

/// UI 刷新节流：内部调度是 5ms（200Hz），但 ChangeNotifier 通知
/// 降到约 30Hz，避免不必要的 Widget rebuild。
const _kPlaybackUiNotifyInterval = Duration(milliseconds: 33);
const _kDefaultSoundfontUrls = [
  'https://cdn.jsdelivr.net/gh/arbruijn/TimGM6mb@master/TimGM6mb.sf2',
  'https://raw.githubusercontent.com/arbruijn/TimGM6mb/master/TimGM6mb.sf2',
  'https://sourceforge.net/projects/mscore/files/soundfont/TimGM6mb.sf2/download',
];

/// 播放异常回调：引擎操作失败时触发，UI 可据此展示轻量提示
typedef PlaybackErrorCallback = void Function(Object error, String context);

/// MIDI 播放控制器
///
/// 负责按时间线调度 MIDI 事件，驱动 MidiEngine 发声。
/// 支持播放/暂停/停止/跳转/变速。
class MidiPlayerController extends ChangeNotifier {
  final MidiPlaybackEngine _engine;
  final Future<File> Function()? _soundfontFileProvider;
  final Future<void> Function(File targetFile)? _soundfontDownloader;

  /// 播放过程中的异常回调（可选），例如引擎 noteOn 失败
  PlaybackErrorCallback? onPlaybackError;
  MidiSongData? _songData;
  TempoMap? _tempoMap;

  PlaybackState _state = PlaybackState.stopped;
  SoundfontSetupState _soundfontState = SoundfontSetupState.idle;
  double _currentTime = 0.0;
  double _playbackSpeed = 1.0;
  double _soundfontDownloadProgress = 0.0;
  int _currentEventIndex = 0;
  final Map<int, Map<_ActiveNoteKey, int>> _activeNotesByTrack = {};
  Timer? _ticker;
  DateTime? _lastTickTime;
  DateTime? _lastPlaybackUiNotifyTime;
  Future<void>? _soundfontSetupFuture;
  String? _soundfontErrorMessage;
  bool _isDisposed = false;

  MidiPlayerController({
    MidiPlaybackEngine? engine,
    Future<File> Function()? soundfontFileProvider,
    Future<void> Function(File targetFile)? soundfontDownloader,
  }) : _engine = engine ?? MidiEngine(),
       _soundfontFileProvider = soundfontFileProvider,
       _soundfontDownloader = soundfontDownloader;

  // Getters
  PlaybackState get state => _state;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isPaused => _state == PlaybackState.paused;
  bool get isStopped => _state == PlaybackState.stopped;
  double get currentTime => _currentTime;
  double get playbackSpeed => _playbackSpeed;
  MidiSongData? get songData => _songData;
  MidiPlaybackEngine get engine => _engine;
  bool get isReady => _engine.isReady && _songData != null;
  SoundfontSetupState get soundfontState => _soundfontState;
  double get soundfontDownloadProgress => _soundfontDownloadProgress;
  String? get soundfontErrorMessage => _soundfontErrorMessage;
  bool get isSoundfontReady => _engine.isReady;

  /// 总时长（秒）
  double get totalDuration => _songData?.totalDuration ?? 0.0;

  /// 播放进度 (0.0 - 1.0)
  double get progress {
    if (totalDuration <= 0) return 0.0;
    return (_currentTime / totalDuration).clamp(0.0, 1.0);
  }

  /// 当前 BPM
  double get currentBpm {
    if (_tempoMap == null || _songData == null) return 120.0;
    final tick = _tempoMap!.secondsToTick(_currentTime);
    return _tempoMap!.getBpmAtTick(tick);
  }

  /// 加载 SoundFont
  Future<void> loadSoundfont(String assetPath) async {
    if (_isDisposed) return;
    await _engine.loadSoundfontFromAsset(assetPath);
    if (_isDisposed) return;
    _soundfontState = SoundfontSetupState.ready;
    _soundfontDownloadProgress = 1.0;
    _soundfontErrorMessage = null;
    _notifyListenersIfActive();
  }

  Future<void> ensureSoundfontReady() async {
    if (_isDisposed || _engine.isReady) {
      return;
    }

    final activeSetup = _soundfontSetupFuture;
    if (activeSetup != null) {
      await activeSetup;
      return;
    }

    late final Future<void> setupFuture;
    setupFuture = _runSoundfontSetup().whenComplete(() {
      if (_soundfontSetupFuture == setupFuture) {
        _soundfontSetupFuture = null;
      }
    });
    _soundfontSetupFuture = setupFuture;
    await setupFuture;
  }

  Future<void> _runSoundfontSetup() async {
    _soundfontState = SoundfontSetupState.checking;
    _soundfontDownloadProgress = 0.0;
    _soundfontErrorMessage = null;
    _notifyListenersIfActive();

    try {
      final soundfontFile = await _resolveSoundfontFile();
      if (_isDisposed) return;

      final cacheInfo = await _inspectSoundfontCache(soundfontFile);
      if (_isDisposed) return;

      if (cacheInfo.exists && cacheInfo.isUsable) {
        try {
          await _loadDownloadedSoundfont(soundfontFile);
          return;
        } catch (_) {
          await soundfontFile.delete();
        }
      } else if (cacheInfo.exists) {
        await soundfontFile.delete();
      }

      await _downloadConfiguredSoundfont(soundfontFile);
      if (_isDisposed) return;
      _verifySoundfontFile(await _inspectSoundfontCache(soundfontFile));
      await _loadDownloadedSoundfont(soundfontFile);
    } catch (e) {
      if (_isDisposed) return;
      _soundfontState = SoundfontSetupState.failed;
      _soundfontErrorMessage = _describeSoundfontError(e);
      _notifyListenersIfActive();
    }
  }

  Future<void> retrySoundfontSetup() async {
    await ensureSoundfontReady();
  }

  Future<SoundfontCacheInfo> inspectSoundfontCache() async {
    try {
      final soundfontFile = await _resolveSoundfontFile();
      return _inspectSoundfontCache(soundfontFile);
    } catch (error) {
      return SoundfontCacheInfo.error('无法读取音色缓存信息：$error');
    }
  }

  Future<SoundfontCacheInfo> _inspectSoundfontCache(File soundfontFile) async {
    final exists = await soundfontFile.exists();
    if (!exists) {
      return SoundfontCacheInfo(
        path: soundfontFile.path,
        exists: false,
        sizeBytes: null,
        errorMessage: null,
      );
    }

    final sizeBytes = await soundfontFile.length();
    final tooSmall = sizeBytes < _kMinimumUsableSoundfontBytes;
    return SoundfontCacheInfo(
      path: soundfontFile.path,
      exists: true,
      sizeBytes: sizeBytes,
      isUsable: !tooSmall,
      errorMessage: tooSmall ? '音色缓存文件过小，可能已损坏。' : null,
    );
  }

  void _verifySoundfontFile(SoundfontCacheInfo cacheInfo) {
    if (!cacheInfo.exists) {
      throw const FileSystemException('SoundFont file was not created');
    }
    if (!cacheInfo.isUsable) {
      throw FileSystemException(
        cacheInfo.errorMessage ?? 'SoundFont file is not usable',
        cacheInfo.path,
      );
    }
  }

  Future<void> clearSoundfontCache() async {
    try {
      final soundfontFile = await _resolveSoundfontFile();
      if (await soundfontFile.exists()) {
        await soundfontFile.delete();
      }
      final tempFile = File('${soundfontFile.path}.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (_isDisposed) return;
      if (!_engine.isReady) {
        _soundfontState = SoundfontSetupState.idle;
        _soundfontDownloadProgress = 0.0;
        _soundfontErrorMessage = null;
        _notifyListenersIfActive();
      }
    } catch (error) {
      if (_isDisposed) return;
      _soundfontState = SoundfontSetupState.failed;
      _soundfontErrorMessage = '音色缓存清理失败：$error';
      _notifyListenersIfActive();
    }
  }

  /// 加载歌曲数据
  void loadSong(MidiSongData song) {
    if (_isDisposed) return;
    stop();
    _songData = song;
    _tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    _applyProgramStateAtCurrentPosition();
    _notifyListenersIfActive();
  }

  /// 播放
  void play() {
    if (_isDisposed) return;
    if (_songData == null || !_engine.isReady) return;
    if (_state == PlaybackState.playing) return;

    _state = PlaybackState.playing;
    _lastTickTime = DateTime.now();
    _lastPlaybackUiNotifyTime = _lastTickTime;

    // 启动定时器，约 5ms 精度
    _ticker = Timer.periodic(const Duration(milliseconds: 5), (_) => _onTick());
    _notifyListenersIfActive();
  }

  /// 暂停
  void pause() {
    if (_isDisposed) return;
    if (_state != PlaybackState.playing) return;
    _state = PlaybackState.paused;
    _ticker?.cancel();
    _ticker = null;
    _lastPlaybackUiNotifyTime = null;
    unawaited(_engine.allNotesOff());
    _clearActiveNotes();
    _notifyListenersIfActive();
  }

  /// 停止
  void stop() {
    if (_isDisposed) return;
    _state = PlaybackState.stopped;
    _ticker?.cancel();
    _ticker = null;
    _lastPlaybackUiNotifyTime = null;
    _currentTime = 0.0;
    _currentEventIndex = 0;
    unawaited(_engine.allNotesOff());
    _clearActiveNotes();
    _notifyListenersIfActive();
  }

  /// 跳转到指定时间（秒）
  void seekTo(double seconds) {
    if (_isDisposed) return;
    final wasPlaying = isPlaying;
    if (wasPlaying) pause();

    _currentTime = seconds.clamp(0.0, totalDuration);
    unawaited(_engine.allNotesOff());
    _clearActiveNotes();
    _updateEventIndex();
    _applyProgramStateAtCurrentPosition();

    if (wasPlaying) play();
    _notifyListenersIfActive();
  }

  /// 设置播放速度 (0.25 - 4.0)
  void setSpeed(double speed) {
    if (_isDisposed) return;
    _playbackSpeed = speed.clamp(0.25, 4.0);
    _notifyListenersIfActive();
  }

  /// 设置轨道音量 (0.0 - 1.0)
  void setTrackVolume(int trackIndex, double volume) {
    if (_isDisposed) return;
    final track = _trackByIndex(trackIndex);
    if (track == null) return;
    track.volume = volume.clamp(0.0, 1.0);
    if (track.volume == 0.0) {
      _stopActiveNotesForTrack(trackIndex);
    }
    _notifyListenersIfActive();
  }

  /// 切换轨道静音
  void toggleTrackMute(int trackIndex) {
    if (_isDisposed) return;
    final track = _trackByIndex(trackIndex);
    if (track == null) return;
    track.isMuted = !track.isMuted;
    if (track.isMuted) {
      _stopActiveNotesForTrack(trackIndex);
    }
    _notifyListenersIfActive();
  }

  /// 定时器回调：推进时间并触发事件
  void _onTick() {
    if (_songData == null || _state != PlaybackState.playing) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastTickTime!).inMicroseconds / 1000000.0;
    _lastTickTime = now;

    _currentTime += elapsed * _playbackSpeed;

    // 播放结束
    if (_currentTime >= totalDuration) {
      stop();
      return;
    }

    // 触发当前时间之前的所有事件
    try {
      _processEvents();
    } catch (error) {
      _reportError(error, '调度事件时发生异常');
      // 即使单个事件出错，播放继续推进
    }
    _notifyPlaybackUiIfNeeded(now);
  }

  /// 处理当前时间点之前的所有未触发事件
  void _processEvents() {
    final timeline = _songData!.timeline;
    while (_currentEventIndex < timeline.length) {
      final event = timeline[_currentEventIndex];
      if (event.time > _currentTime) break;

      _dispatchEvent(event);
      _currentEventIndex++;
    }
  }

  void _notifyPlaybackUiIfNeeded(DateTime now) {
    final lastNotifyTime = _lastPlaybackUiNotifyTime;
    if (lastNotifyTime != null &&
        now.difference(lastNotifyTime) < _kPlaybackUiNotifyInterval) {
      return;
    }

    _lastPlaybackUiNotifyTime = now;
    _notifyListenersIfActive();
  }

  /// 分发单个 MIDI 事件到引擎
  void _dispatchEvent(TimelineEvent event) {
    switch (event.type) {
      case MidiEventType.noteOn:
        if (_isTrackMuted(event.trackIndex)) return;
        final vol = _getTrackVolume(event.trackIndex);
        final adjustedVelocity = (event.data2 * vol).round().clamp(0, 127);
        if (adjustedVelocity == 0) return;
        final noteOnStarted = _fireAndForget(
          () => _engine.noteOn(
            channel: event.channel,
            note: event.data1,
            velocity: adjustedVelocity,
          ),
          'NoteOn ch:${event.channel} note:${event.data1}',
          onAsyncError: () => _releaseActiveNote(event),
        );
        if (noteOnStarted) {
          _rememberActiveNote(event);
        }
      case MidiEventType.noteOff:
        if (_releaseActiveNote(event)) {
          _fireAndForget(
            () => _engine.noteOff(channel: event.channel, note: event.data1),
            'NoteOff ch:${event.channel} note:${event.data1}',
          );
        }
      case MidiEventType.programChange:
        _fireAndForget(
          () => _engine.setInstrument(
            channel: event.channel,
            program: event.data1,
          ),
          'ProgramChange ch:${event.channel} prog:${event.data1}',
        );
      default:
        break;
    }
  }

  /// 不阻塞播放线程但失败时上报异常
  bool _fireAndForget(
    Future<void> Function() operation,
    String context, {
    VoidCallback? onAsyncError,
  }) {
    try {
      unawaited(
        operation().catchError((Object error) {
          onAsyncError?.call();
          _reportError(error, context);
        }),
      );
      return true;
    } catch (error) {
      _reportError(error, context);
      return false;
    }
  }

  /// 报告异常到外部回调
  void _reportError(Object error, String context) {
    onPlaybackError?.call(error, context);
  }

  /// 检查轨道是否被静音（按 trackIndex 而非 channel）
  bool _isTrackMuted(int trackIndex) {
    return _trackByIndex(trackIndex)?.isMuted ?? false;
  }

  /// 获取轨道音量（按 trackIndex 而非 channel）
  double _getTrackVolume(int trackIndex) {
    return _trackByIndex(trackIndex)?.volume ?? 1.0;
  }

  MidiTrackInfo? _trackByIndex(int trackIndex) {
    if (_songData == null || trackIndex < 0) return null;
    for (final track in _songData!.tracks) {
      if (track.index == trackIndex) {
        return track;
      }
    }
    return null;
  }

  /// seek 后更新事件索引（二分查找）
  void _updateEventIndex() {
    if (_songData == null) return;
    final timeline = _songData!.timeline;
    int low = 0;
    int high = timeline.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (timeline[mid].time <= _currentTime) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    _currentEventIndex = low;
  }

  /// 初始化各轨道乐器
  void _setupInstruments() {
    if (_songData == null) return;
    for (final track in _songData!.tracks) {
      for (final entry in track.programByChannel.entries) {
        _fireAndForget(
          () => _engine.setInstrument(channel: entry.key, program: entry.value),
          'InitInstrument ch:${entry.key} prog:${entry.value}',
        );
      }
    }
  }

  void _applyProgramStateAtCurrentPosition() {
    final songData = _songData;
    if (songData == null) return;

    final programByChannel = <int, int>{};
    var hasProgramChangeEvents = false;
    for (final event in songData.timeline) {
      if (event.type != MidiEventType.programChange) {
        continue;
      }
      hasProgramChangeEvents = true;
      programByChannel.putIfAbsent(event.channel, () => 0);
      if (event.time > _currentTime) {
        continue;
      }
      programByChannel[event.channel] = event.data1;
    }

    if (!hasProgramChangeEvents) {
      _setupInstruments();
      return;
    }

    for (final entry in programByChannel.entries) {
      _fireAndForget(
        () => _engine.setInstrument(channel: entry.key, program: entry.value),
        'ProgramApply ch:${entry.key} prog:${entry.value}',
      );
    }
  }

  void _rememberActiveNote(TimelineEvent event) {
    final notesForTrack = _activeNotesByTrack.putIfAbsent(
      event.trackIndex,
      () => {},
    );
    final key = _ActiveNoteKey(channel: event.channel, note: event.data1);
    notesForTrack[key] = (notesForTrack[key] ?? 0) + 1;
  }

  bool _releaseActiveNote(TimelineEvent event) {
    final notesForTrack = _activeNotesByTrack[event.trackIndex];
    if (notesForTrack == null) return false;

    final key = _ActiveNoteKey(channel: event.channel, note: event.data1);
    final count = notesForTrack[key];
    if (count == null) return false;

    if (count <= 1) {
      notesForTrack.remove(key);
    } else {
      notesForTrack[key] = count - 1;
    }

    if (notesForTrack.isEmpty) {
      _activeNotesByTrack.remove(event.trackIndex);
    }

    return true;
  }

  void _stopActiveNotesForTrack(int trackIndex) {
    final notesForTrack = _activeNotesByTrack.remove(trackIndex);
    if (notesForTrack == null) return;

    for (final entry in notesForTrack.entries) {
      for (var i = 0; i < entry.value; i++) {
        _fireAndForget(
          () =>
              _engine.noteOff(channel: entry.key.channel, note: entry.key.note),
          'StopNote trk:$trackIndex ch:${entry.key.channel}'
          ' note:${entry.key.note}',
        );
      }
    }
  }

  void _clearActiveNotes() {
    _activeNotesByTrack.clear();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _state = PlaybackState.stopped;
    _ticker?.cancel();
    _ticker = null;
    _lastPlaybackUiNotifyTime = null;
    _currentTime = 0.0;
    _currentEventIndex = 0;
    _clearActiveNotes();
    unawaited(_engine.allNotesOff());
    unawaited(_engine.dispose());
    super.dispose();
  }

  Future<File> _resolveSoundfontFile() async {
    final provider = _soundfontFileProvider;
    if (provider != null) {
      return provider();
    }
    return _getSoundfontFile();
  }

  Future<File> _getSoundfontFile() async {
    final appSupportDirectory = await getApplicationSupportDirectory();
    final soundfontDirectory = Directory(
      '${appSupportDirectory.path}/soundfonts',
    );
    await soundfontDirectory.create(recursive: true);
    return File('${soundfontDirectory.path}/$_kDefaultSoundfontFileName');
  }

  Future<void> _downloadConfiguredSoundfont(File targetFile) async {
    final downloader = _soundfontDownloader;
    if (downloader == null) {
      await _downloadSoundfont(targetFile);
      return;
    }

    _soundfontState = SoundfontSetupState.downloading;
    _soundfontDownloadProgress = 0.0;
    _notifyListenersIfActive();
    await downloader(targetFile);
  }

  Future<void> _downloadSoundfont(File targetFile) async {
    _soundfontState = SoundfontSetupState.downloading;
    _soundfontDownloadProgress = 0.0;
    _notifyListenersIfActive();

    final tempFile = File('${targetFile.path}.download');
    Object? lastError;

    for (final downloadUrl in _kDefaultSoundfontUrls) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20);

      try {
        final request = await httpClient.getUrl(Uri.parse(downloadUrl));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(
            'SoundFont download failed (${response.statusCode})',
            uri: Uri.parse(downloadUrl),
          );
        }

        final output = tempFile.openWrite();
        var receivedBytes = 0;
        final totalBytes = response.contentLength;

        try {
          await for (final chunk in response) {
            output.add(chunk);
            receivedBytes += chunk.length;
            if (totalBytes > 0) {
              _soundfontDownloadProgress = receivedBytes / totalBytes;
              _notifyListenersIfActive();
            }
          }
        } finally {
          await output.close();
        }

        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);
        _soundfontDownloadProgress = 1.0;
        return;
      } catch (error) {
        lastError = error;
      } finally {
        httpClient.close(force: true);
      }
    }

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    throw lastError ?? const HttpException('SoundFont download failed');
  }

  Future<void> _loadDownloadedSoundfont(File soundfontFile) async {
    await _engine.loadSoundfontFromFile(soundfontFile.path);
    if (_isDisposed) return;
    _soundfontState = SoundfontSetupState.ready;
    _soundfontDownloadProgress = 1.0;
    _soundfontErrorMessage = null;
    if (_songData != null) {
      _applyProgramStateAtCurrentPosition();
    }
    _notifyListenersIfActive();
  }

  void _notifyListenersIfActive() {
    if (_isDisposed) return;
    notifyListeners();
  }

  String _describeSoundfontError(Object error) {
    if (error is SocketException) {
      return '无法连接到音色库下载源，请检查网络。';
    }
    if (error is HttpException) {
      return '音色库下载失败，请稍后重试。';
    }
    return '音色库准备失败，请重试。';
  }
}

class _ActiveNoteKey {
  final int channel;
  final int note;

  const _ActiveNoteKey({required this.channel, required this.note});

  @override
  bool operator ==(Object other) {
    return other is _ActiveNoteKey &&
        other.channel == channel &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(channel, note);
}
