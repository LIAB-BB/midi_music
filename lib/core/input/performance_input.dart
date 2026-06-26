import 'dart:async';

enum PerformanceInputEventType { noteOn, noteOff, pitch, sustain }

class PerformanceInputEvent {
  final PerformanceInputEventType type;
  final int? midiNote;
  final double? pitchHz;
  final int velocity;
  final int channel;
  final DateTime timestamp;
  final bool? sustain;

  const PerformanceInputEvent({
    required this.type,
    this.midiNote,
    this.pitchHz,
    this.velocity = 0,
    this.channel = 0,
    required this.timestamp,
    this.sustain,
  });

  factory PerformanceInputEvent.noteOn({
    required int midiNote,
    required int velocity,
    int channel = 0,
    required DateTime timestamp,
  }) {
    return PerformanceInputEvent(
      type: PerformanceInputEventType.noteOn,
      midiNote: midiNote,
      velocity: velocity,
      channel: channel,
      timestamp: timestamp,
    );
  }

  factory PerformanceInputEvent.noteOff({
    required int midiNote,
    int velocity = 0,
    int channel = 0,
    required DateTime timestamp,
  }) {
    return PerformanceInputEvent(
      type: PerformanceInputEventType.noteOff,
      midiNote: midiNote,
      velocity: velocity,
      channel: channel,
      timestamp: timestamp,
    );
  }

  factory PerformanceInputEvent.pitch({
    required double pitchHz,
    int? midiNote,
    int channel = 0,
    required DateTime timestamp,
  }) {
    return PerformanceInputEvent(
      type: PerformanceInputEventType.pitch,
      midiNote: midiNote,
      pitchHz: pitchHz,
      channel: channel,
      timestamp: timestamp,
    );
  }

  factory PerformanceInputEvent.sustain({
    required bool isDown,
    int channel = 0,
    required DateTime timestamp,
  }) {
    return PerformanceInputEvent(
      type: PerformanceInputEventType.sustain,
      channel: channel,
      timestamp: timestamp,
      sustain: isDown,
    );
  }
}

abstract class PerformanceInput {
  Stream<PerformanceInputEvent> get events;

  Future<void> start();

  Future<void> dispose();
}
