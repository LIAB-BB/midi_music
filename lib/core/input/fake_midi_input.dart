import 'dart:async';

import 'performance_input.dart';

class FakeMidiInput implements PerformanceInput {
  final _controller = StreamController<PerformanceInputEvent>.broadcast();
  bool _started = false;
  bool _disposed = false;

  bool get isStarted => _started;

  @override
  Stream<PerformanceInputEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('FakeMidiInput has been disposed');
    }
    _started = true;
  }

  void emit(PerformanceInputEvent event) {
    if (_disposed) {
      throw StateError('FakeMidiInput has been disposed');
    }
    if (!_started) {
      throw StateError('FakeMidiInput must be started before emitting events');
    }
    _controller.add(event);
  }

  void emitNoteOn({
    required int midiNote,
    required int velocity,
    int channel = 0,
    DateTime? timestamp,
  }) {
    emit(
      PerformanceInputEvent.noteOn(
        midiNote: midiNote,
        velocity: velocity,
        channel: channel,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  void emitNoteOff({
    required int midiNote,
    int velocity = 0,
    int channel = 0,
    DateTime? timestamp,
  }) {
    emit(
      PerformanceInputEvent.noteOff(
        midiNote: midiNote,
        velocity: velocity,
        channel: channel,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  void emitSustain({
    required bool isDown,
    int channel = 0,
    DateTime? timestamp,
  }) {
    emit(
      PerformanceInputEvent.sustain(
        isDown: isDown,
        channel: channel,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    await _controller.close();
  }
}
