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

const _kDefaultSoundfontFileName = 'TimGM6mb.sf2';
const _kPlaybackUiNotifyInterval = Duration(milliseconds: 33);
const _kDefaultSoundfontUrls = [
  'https://cdn.jsdelivr.net/gh/arbruijn/TimGM6mb@master/TimGM6mb.sf2',
  'https://raw.githubusercontent.com/arbruijn/TimGM6mb/master/TimGM6mb.sf2',
  'https://sourceforge.net/projects/mscore/files/soundfont/TimGM6mb.sf2/download',
];

/// MIDI 播放控制器
///
/// 负责按时间线调度 MIDI 事件，驱动 MidiEngine 发声。
/// 支持播放/暂停/停止/跳转/变速。
class MidiPlayerController extends ChangeNotifier {
  final MidiEngine _engine = MidiEngine();
  MidiSongData? _songData;
  TempoMap? _tempoMap;

  PlaybackState _state = PlaybackState.stopped;
  SoundfontSetupState _soundfontState = SoundfontSetupState.idle;
  double _currentTime = 0.0;
  double _playbackSpeed = 1.0;
  double _soundfontDownloadProgress = 0.0;
  int _currentEventIndex = 0;
  Timer? _ticker;
  DateTime? _lastTickTime;
  DateTime? _lastPlaybackUiNotifyTime;
  String? _soundfontErrorMessage;

  // Getters
  PlaybackState get state => _state;
  bool get isPlaying => _state == PlaybackState.playing;
  bool get isPaused => _state == PlaybackState.paused;
  bool get isStopped => _state == PlaybackState.stopped;
  double get currentTime => _currentTime;
  double get playbackSpeed => _playbackSpeed;
  MidiSongData? get songData => _songData;
  MidiEngine get engine => _engine;
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
    await _engine.loadSoundfontFromAsset(assetPath);
    _soundfontState = SoundfontSetupState.ready;
    _soundfontDownloadProgress = 1.0;
    _soundfontErrorMessage = null;
    notifyListeners();
  }

  Future<void> ensureSoundfontReady() async {
    if (_engine.isReady ||
        _soundfontState == SoundfontSetupState.checking ||
        _soundfontState == SoundfontSetupState.downloading) {
      return;
    }

    _soundfontState = SoundfontSetupState.checking;
    _soundfontDownloadProgress = 0.0;
    _soundfontErrorMessage = null;
    notifyListeners();

    try {
      final soundfontFile = await _getSoundfontFile();
      final cachedFileIsUsable =
          await soundfontFile.exists() && await soundfontFile.length() > 0;

      if (cachedFileIsUsable) {
        try {
          await _loadDownloadedSoundfont(soundfontFile);
          return;
        } catch (_) {
          await soundfontFile.delete();
        }
      }

      await _downloadSoundfont(soundfontFile);
      await _loadDownloadedSoundfont(soundfontFile);
    } catch (e) {
      _soundfontState = SoundfontSetupState.failed;
      _soundfontErrorMessage = _describeSoundfontError(e);
      notifyListeners();
    }
  }

  Future<void> retrySoundfontSetup() async {
    await ensureSoundfontReady();
  }

  /// 加载歌曲数据
  void loadSong(MidiSongData song) {
    stop();
    _songData = song;
    _tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    // 为每个轨道的乐器设置 program change
    _setupInstruments();
    notifyListeners();
  }

  /// 播放
  void play() {
    if (_songData == null || !_engine.isReady) return;
    if (_state == PlaybackState.playing) return;

    _state = PlaybackState.playing;
    _lastTickTime = DateTime.now();
    _lastPlaybackUiNotifyTime = _lastTickTime;

    // 启动定时器，约 5ms 精度
    _ticker = Timer.periodic(const Duration(milliseconds: 5), (_) => _onTick());
    notifyListeners();
  }

  /// 暂停
  void pause() {
    if (_state != PlaybackState.playing) return;
    _state = PlaybackState.paused;
    _ticker?.cancel();
    _ticker = null;
    _lastPlaybackUiNotifyTime = null;
    unawaited(_engine.allNotesOff());
    notifyListeners();
  }

  /// 停止
  void stop() {
    _state = PlaybackState.stopped;
    _ticker?.cancel();
    _ticker = null;
    _lastPlaybackUiNotifyTime = null;
    _currentTime = 0.0;
    _currentEventIndex = 0;
    unawaited(_engine.allNotesOff());
    notifyListeners();
  }

  /// 跳转到指定时间（秒）
  void seekTo(double seconds) {
    final wasPlaying = isPlaying;
    if (wasPlaying) pause();

    _currentTime = seconds.clamp(0.0, totalDuration);
    unawaited(_engine.allNotesOff());
    _updateEventIndex();

    if (wasPlaying) play();
    notifyListeners();
  }

  /// 设置播放速度 (0.25 - 4.0)
  void setSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.25, 4.0);
    notifyListeners();
  }

  /// 设置轨道音量 (0.0 - 1.0)
  void setTrackVolume(int trackIndex, double volume) {
    if (_songData == null) return;
    if (trackIndex >= _songData!.tracks.length) return;
    _songData!.tracks[trackIndex].volume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 切换轨道静音
  void toggleTrackMute(int trackIndex) {
    if (_songData == null) return;
    if (trackIndex >= _songData!.tracks.length) return;
    final track = _songData!.tracks[trackIndex];
    track.isMuted = !track.isMuted;
    if (track.isMuted) {
      // 静音时停止该轨道所有通道上的所有音符
      for (final ch in track.channels) {
        for (int note = 0; note < 128; note++) {
          unawaited(_engine.noteOff(channel: ch, note: note));
        }
      }
    }
    notifyListeners();
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
    _processEvents();
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
    notifyListeners();
  }

  /// 分发单个 MIDI 事件到引擎
  void _dispatchEvent(TimelineEvent event) {
    // 按 trackIndex 检查静音（支持多轨道共享同一 channel）
    if (_isTrackMuted(event.trackIndex)) return;

    switch (event.type) {
      case MidiEventType.noteOn:
        final vol = _getTrackVolume(event.trackIndex);
        final adjustedVelocity = (event.data2 * vol).round().clamp(0, 127);
        unawaited(
          _engine.noteOn(
            channel: event.channel,
            note: event.data1,
            velocity: adjustedVelocity,
          ),
        );
      case MidiEventType.noteOff:
        unawaited(_engine.noteOff(channel: event.channel, note: event.data1));
      case MidiEventType.programChange:
        unawaited(
          _engine.setInstrument(channel: event.channel, program: event.data1),
        );
      default:
        break;
    }
  }

  /// 检查轨道是否被静音（按 trackIndex 而非 channel）
  bool _isTrackMuted(int trackIndex) {
    if (_songData == null || trackIndex < 0) return false;
    if (trackIndex >= _songData!.tracks.length) return false;
    return _songData!.tracks[trackIndex].isMuted;
  }

  /// 获取轨道音量（按 trackIndex 而非 channel）
  double _getTrackVolume(int trackIndex) {
    if (_songData == null || trackIndex < 0) return 1.0;
    if (trackIndex >= _songData!.tracks.length) return 1.0;
    return _songData!.tracks[trackIndex].volume;
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
        unawaited(
          _engine.setInstrument(channel: entry.key, program: entry.value),
        );
      }
    }
  }

  @override
  void dispose() {
    stop();
    unawaited(_engine.dispose());
    super.dispose();
  }

  Future<File> _getSoundfontFile() async {
    final appSupportDirectory = await getApplicationSupportDirectory();
    final soundfontDirectory = Directory(
      '${appSupportDirectory.path}/soundfonts',
    );
    await soundfontDirectory.create(recursive: true);
    return File('${soundfontDirectory.path}/$_kDefaultSoundfontFileName');
  }

  Future<void> _downloadSoundfont(File targetFile) async {
    _soundfontState = SoundfontSetupState.downloading;
    _soundfontDownloadProgress = 0.0;
    notifyListeners();

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
              notifyListeners();
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
    _soundfontState = SoundfontSetupState.ready;
    _soundfontDownloadProgress = 1.0;
    _soundfontErrorMessage = null;
    if (_songData != null) {
      _setupInstruments();
    }
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
