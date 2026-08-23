import 'dart:async';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';

/// 伴奏 SoundFont 的最小播放边界。
abstract class MidiPlaybackEngine {
  bool get isReady;

  Future<void> loadSoundfontsFromAssets(Map<int, String> assetPathsByProgram);
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  });
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  });
  Future<void> noteOff({required int channel, required int note});
  Future<void> controlChange({
    required int channel,
    required int controller,
    required int value,
  });
  Future<void> allNotesOff();
  Future<void> dispose();
}

/// 基于 flutter_midi_pro 4.x 的 iOS SoundFont 引擎。
///
/// K.478 候选为 Program 40（小提琴）和 42（大提琴）各装入一个轻量
/// SoundFont。每个 MIDI channel 会在 Program Change 后绑定到对应的 sfId，
/// 从而保证钢琴 Program 0 永远不会落到 App 的音频链路。
class MidiEngine implements MidiPlaybackEngine {
  final MidiProBackend _backend;
  final Map<int, int> _soundfontIdsByProgram = {};
  final Map<int, int> _soundfontIdsByChannel = {};
  bool _isReady = false;
  int _operationGeneration = 0;
  int _operationPauseCount = 0;
  final Map<int, Future<void>> _channelOperations = {};

  MidiEngine({MidiProBackend? backend})
    : _backend = backend ?? MidiProBackend();

  @override
  bool get isReady => _isReady;

  Map<int, int> get soundfontIdsByProgram =>
      Map<int, int>.unmodifiable(_soundfontIdsByProgram);

  @override
  Future<void> loadSoundfontsFromAssets(
    Map<int, String> assetPathsByProgram,
  ) async {
    if (assetPathsByProgram.isEmpty) {
      throw ArgumentError.value(
        assetPathsByProgram,
        'assetPathsByProgram',
        '至少需要一个 SoundFont',
      );
    }
    await _ensureInitialized();
    await _unloadCurrentSoundfonts();
    try {
      for (final entry in assetPathsByProgram.entries) {
        final soundfontId = await _backend.loadSoundfontAsset(
          assetPath: entry.value,
          bank: 0,
          program: entry.key,
        );
        _soundfontIdsByProgram[entry.key] = soundfontId;
      }
      _isReady = _soundfontIdsByProgram.length == assetPathsByProgram.length;
    } catch (_) {
      await _unloadCurrentSoundfonts();
      rethrow;
    }
  }

  @override
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) async {
    final soundfontId = _soundfontIdsByProgram[program];
    if (!_isReady || soundfontId == null) {
      throw StateError('Program $program 的 SoundFont 尚未加载');
    }
    await _enqueueChannelOperation(channel, () async {
      await _backend.selectInstrument(
        sfId: soundfontId,
        channel: channel,
        bank: bank,
        program: program,
      );
      _soundfontIdsByChannel[channel] = soundfontId;
    });
  }

  @override
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) async {
    await _enqueueChannelOperation(channel, () async {
      final soundfontId = _soundfontIdsByChannel[channel];
      if (soundfontId == null) return;
      await _backend.playNote(
        sfId: soundfontId,
        channel: channel,
        key: note,
        velocity: velocity,
      );
    });
  }

  @override
  Future<void> noteOff({required int channel, required int note}) async {
    await _enqueueChannelOperation(channel, () async {
      final soundfontId = _soundfontIdsByChannel[channel];
      if (soundfontId == null) return;
      await _backend.stopNote(sfId: soundfontId, channel: channel, key: note);
    });
  }

  @override
  Future<void> controlChange({
    required int channel,
    required int controller,
    required int value,
  }) async {
    await _enqueueChannelOperation(channel, () async {
      final soundfontId = _soundfontIdsByChannel[channel];
      if (soundfontId == null) return;
      await _backend.controlChange(
        sfId: soundfontId,
        channel: channel,
        controller: controller,
        value: value,
      );
    });
  }

  @override
  Future<void> allNotesOff() async {
    if (!_isReady || _soundfontIdsByProgram.isEmpty) return;
    await _pauseAndDrainOperationQueues();
    try {
      await Future.wait(
        _soundfontIdsByProgram.values.map(
          (soundfontId) => _backend.stopAllNotes(sfId: soundfontId),
        ),
      );
    } finally {
      _resumeOperations();
    }
  }

  @override
  Future<void> dispose() async {
    await allNotesOff();
    await _unloadCurrentSoundfonts();
    if (_backend.isInitialized) {
      await _backend.dispose();
    }
  }

  Future<void> _ensureInitialized() async {
    if (_backend.isInitialized) return;
    await _backend.configureAudioSession(
      category: AudioSessionCategory.playback,
      mixWithOthers: true,
    );
    await _backend.init();
  }

  Future<void> _unloadCurrentSoundfonts() async {
    final soundfontIds = _soundfontIdsByProgram.values.toList(growable: false);
    await _pauseAndDrainOperationQueues(clearChannelBindings: true);
    try {
      _soundfontIdsByProgram.clear();
      _isReady = false;
      if (_backend.isInitialized) {
        for (final soundfontId in soundfontIds) {
          await _backend.unloadSoundfont(soundfontId);
        }
      }
    } finally {
      _resumeOperations();
    }
  }

  Future<void> _enqueueChannelOperation(
    int channel,
    Future<void> Function() operation,
  ) {
    if (!_isReady || _operationPauseCount > 0) {
      return Future<void>.value();
    }

    final generation = _operationGeneration;
    final previous = _channelOperations[channel] ?? Future<void>.value();
    final operationFuture = previous.catchError((Object _) {}).then((_) async {
      if (generation != _operationGeneration || !_isReady) {
        return;
      }
      await operation();
    });
    _channelOperations[channel] = operationFuture.catchError((Object _) {});
    return operationFuture;
  }

  Future<void> _pauseAndDrainOperationQueues({
    bool clearChannelBindings = false,
  }) async {
    _operationPauseCount++;
    final pendingOperations = _channelOperations.values.toSet();
    _operationGeneration++;
    _channelOperations.clear();
    if (clearChannelBindings) {
      _soundfontIdsByChannel.clear();
    }
    await Future.wait(
      pendingOperations.map((operation) => operation.catchError((Object _) {})),
    );
  }

  void _resumeOperations() {
    assert(_operationPauseCount > 0);
    _operationPauseCount--;
  }
}

/// `flutter_midi_pro` 的可替换边界，便于直接验证多 SoundFont 路由和清理顺序。
class MidiProBackend {
  final MidiPro _midiPro;

  MidiProBackend({MidiPro? midiPro}) : _midiPro = midiPro ?? MidiPro();

  bool get isInitialized => _midiPro.isInitialized;

  Future<void> configureAudioSession({
    required AudioSessionCategory category,
    required bool mixWithOthers,
  }) => _midiPro.configureAudioSession(
    category: category,
    mixWithOthers: mixWithOthers,
  );

  Future<void> init() => _midiPro.init();

  Future<int> loadSoundfontAsset({
    required String assetPath,
    required int bank,
    required int program,
  }) => _midiPro.loadSoundfontAsset(
    assetPath: assetPath,
    bank: bank,
    program: program,
  );

  Future<void> selectInstrument({
    required int sfId,
    required int channel,
    required int bank,
    required int program,
  }) => _midiPro.selectInstrument(
    sfId: sfId,
    channel: channel,
    bank: bank,
    program: program,
  );

  Future<void> playNote({
    required int sfId,
    required int channel,
    required int key,
    required int velocity,
  }) => _midiPro.playNote(
    sfId: sfId,
    channel: channel,
    key: key,
    velocity: velocity,
  );

  Future<void> stopNote({
    required int sfId,
    required int channel,
    required int key,
  }) => _midiPro.stopNote(sfId: sfId, channel: channel, key: key);

  Future<void> controlChange({
    required int sfId,
    required int channel,
    required int controller,
    required int value,
  }) => _midiPro.controlChange(
    sfId: sfId,
    channel: channel,
    controller: controller,
    value: value,
  );

  Future<void> stopAllNotes({required int sfId}) =>
      _midiPro.stopAllNotes(sfId: sfId);

  Future<void> unloadSoundfont(int sfId) => _midiPro.unloadSoundfont(sfId);

  Future<void> dispose() => _midiPro.dispose();
}
