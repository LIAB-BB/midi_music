import 'dart:async';

import 'package:flutter/services.dart';

import 'midi_input.dart';

abstract class MidiInputPlatformBridge {
  Stream<Object?> events();
  Future<Object?> start();
  Future<void> stop();
}

class CoreMidiPlatformBridge implements MidiInputPlatformBridge {
  static const _methodChannel = MethodChannel(
    'com.liab.midi_music/core_midi_input/methods',
  );
  static const _eventChannel = EventChannel(
    'com.liab.midi_music/core_midi_input/events',
  );

  const CoreMidiPlatformBridge();

  @override
  Stream<Object?> events() => _eventChannel.receiveBroadcastStream();

  @override
  Future<Object?> start() => _methodChannel.invokeMethod<Object?>('start');

  @override
  Future<void> stop() => _methodChannel.invokeMethod<void>('stop');
}

/// iOS 上的 USB/CoreMIDI 输入实现。
class IosMidiInput implements MidiInput {
  final MidiInputPlatformBridge _bridge;
  final _messageController = StreamController<MidiInputMessage>.broadcast();
  final _stateController = StreamController<MidiInputState>.broadcast();

  StreamSubscription<Object?>? _eventSubscription;
  MidiInputState _state = const MidiInputState();
  bool _started = false;
  bool _disposed = false;
  bool _platformStartRequested = false;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;

  IosMidiInput({MidiInputPlatformBridge? bridge})
    : _bridge = bridge ?? const CoreMidiPlatformBridge();

  @override
  Stream<MidiInputMessage> get messages => _messageController.stream;

  @override
  Stream<MidiInputState> get states => _stateController.stream;

  @override
  MidiInputState get state => _state;

  @override
  Future<void> start() {
    if (_disposed) {
      return Future<void>.error(StateError('MIDI 输入已经释放'));
    }
    if (_started) return Future<void>.value();
    final starting = _startFuture;
    if (starting != null) return starting;

    final future = _startInternal();
    _startFuture = future;
    unawaited(
      future.then<void>(
        (_) => _clearStartFuture(future),
        onError: (Object error, StackTrace stackTrace) =>
            _clearStartFuture(future),
      ),
    );
    return future;
  }

  Future<void> _startInternal() async {
    _eventSubscription = _bridge.events().listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _updateState(MidiInputState(errorMessage: 'CoreMIDI 连接中断：$error'));
        _messageController.addError(error, stackTrace);
      },
    );

    try {
      _platformStartRequested = true;
      final result = await _bridge.start();
      if (_disposed) return;
      _started = true;
      _applyDevicePayload(result);
    } catch (_) {
      if (!_disposed) {
        await _eventSubscription?.cancel();
        _eventSubscription = null;
      }
      rethrow;
    }
  }

  void _clearStartFuture(Future<void> future) {
    if (identical(_startFuture, future)) _startFuture = null;
  }

  void _handleEvent(Object? event) {
    if (_disposed) return;
    if (event is! Map) return;
    final type = event['type'];
    if (type == 'devices') {
      _applyDevicePayload(event['devices']);
      return;
    }
    if (type != 'midi') return;

    final status = event['status'];
    final data1 = event['data1'];
    final data2 = event['data2'];
    final timestampMicros = event['timestampMicros'];
    if (status is! int || data1 is! int || data2 is! int) return;

    _messageController.add(
      MidiInputMessage(
        status: status,
        data1: data1,
        data2: data2,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(
          timestampMicros is int
              ? timestampMicros
              : DateTime.now().microsecondsSinceEpoch,
        ),
      ),
    );
  }

  void _applyDevicePayload(Object? payload) {
    if (_disposed) return;
    if (payload is! List) return;
    final devices = <MidiInputDevice>[];
    for (final item in payload) {
      if (item is! Map) continue;
      final id = item['id'];
      final name = item['name'];
      if (id is String && name is String) {
        devices.add(MidiInputDevice(id: id, name: name));
      }
    }
    _updateState(MidiInputState(devices: devices));
  }

  void _updateState(MidiInputState nextState) {
    if (_disposed) return;
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }
  }

  @override
  Future<void> dispose() {
    final disposing = _disposeFuture;
    if (disposing != null) return disposing;
    if (_disposed) return Future<void>.value();
    _disposed = true;
    _started = false;
    _state = const MidiInputState();
    final future = _disposeInternal();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeInternal() async {
    final starting = _startFuture;
    if (starting != null) {
      await starting.catchError((Object _) {});
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    if (_platformStartRequested) {
      try {
        await _bridge.stop();
      } catch (_) {
        // 页面退出时平台通道可能已销毁，不影响 Dart 资源释放。
      }
      _platformStartRequested = false;
    }
    await _messageController.close();
    await _stateController.close();
  }
}
