import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';

/// SoundFont 引擎封装
///
/// 封装 flutter_midi_pro，提供 SoundFont 加载和 MIDI 音符播放能力。
class MidiEngine {
  final MidiPro _midiPro;
  int? _soundfontId;
  bool _isReady = false;
  int _operationGeneration = 0;
  final Map<int, Future<void>> _channelOperations = {};

  MidiEngine({MidiPro? midiPro}) : _midiPro = midiPro ?? MidiPro();

  @visibleForTesting
  MidiEngine.readyForTesting({
    required MidiPro midiPro,
    required int soundfontId,
  }) : _midiPro = midiPro,
       _soundfontId = soundfontId,
       _isReady = true;

  bool get isReady => _isReady;
  int? get soundfontId => _soundfontId;

  /// 从 assets 加载 SoundFont 文件
  Future<void> loadSoundfontFromAsset(String assetPath) async {
    if (_soundfontId != null) {
      _resetOperationQueues();
      await _midiPro.unloadSoundfont(_soundfontId!);
      _soundfontId = null;
      _isReady = false;
    }
    _soundfontId = await _midiPro.loadSoundfontAsset(
      assetPath: assetPath,
      bank: 0,
      program: 0,
    );
    _isReady = true;
  }

  /// 从文件路径加载 SoundFont
  Future<void> loadSoundfontFromFile(String filePath) async {
    if (_soundfontId != null) {
      _resetOperationQueues();
      await _midiPro.unloadSoundfont(_soundfontId!);
      _soundfontId = null;
      _isReady = false;
    }
    _soundfontId = await _midiPro.loadSoundfontFile(
      filePath: filePath,
      bank: 0,
      program: 0,
    );
    _isReady = true;
  }

  /// 切换指定通道的乐器
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) async {
    await _enqueueChannelOperation(
      channel,
      (sfId) => _midiPro.selectInstrument(
        sfId: sfId,
        channel: channel,
        bank: bank,
        program: program,
      ),
    );
  }

  /// 发送 Note On
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) async {
    await _enqueueChannelOperation(
      channel,
      (sfId) => _midiPro.playNote(
        sfId: sfId,
        channel: channel,
        key: note,
        velocity: velocity,
      ),
    );
  }

  /// 发送 Note Off
  Future<void> noteOff({required int channel, required int note}) async {
    await _enqueueChannelOperation(
      channel,
      (sfId) => _midiPro.stopNote(sfId: sfId, channel: channel, key: note),
    );
  }

  /// 停止所有音符
  Future<void> allNotesOff() async {
    if (!_isReady || _soundfontId == null) return;
    final sfId = _soundfontId!;
    _resetOperationQueues();
    await _midiPro.stopAllNotes(sfId: sfId);
  }

  Future<void> waitForPendingOperations() async {
    await Future.wait(_channelOperations.values);
  }

  /// 释放资源
  Future<void> dispose() async {
    await allNotesOff();
    if (_soundfontId != null) {
      await _midiPro.unloadSoundfont(_soundfontId!);
    }
    await _midiPro.dispose();
    _isReady = false;
    _soundfontId = null;
  }

  Future<void> _enqueueChannelOperation(
    int channel,
    Future<void> Function(int soundfontId) operation,
  ) {
    final soundfontId = _soundfontId;
    if (!_isReady || soundfontId == null) {
      return Future<void>.value();
    }

    final generation = _operationGeneration;
    final previous = _channelOperations[channel] ?? Future<void>.value();
    final queued = previous
        .catchError((Object _) {})
        .then((_) async {
          if (generation != _operationGeneration ||
              !_isReady ||
              _soundfontId != soundfontId) {
            return;
          }
          await operation(soundfontId);
        })
        .catchError((Object _) {});

    _channelOperations[channel] = queued;
    return queued;
  }

  void _resetOperationQueues() {
    _operationGeneration++;
    _channelOperations.clear();
  }
}
