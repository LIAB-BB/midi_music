import 'dart:typed_data';

import 'performance_input.dart';

const int _noteOffCommand = 0x80;
const int _noteOnCommand = 0x90;
const int _controlChangeCommand = 0xB0;
const int _sustainController = 64;
const int _sustainOnThreshold = 64;

List<PerformanceInputEvent> parseMidiMessageBytes(
  Uint8List data, {
  required DateTime timestamp,
}) {
  if (data.isEmpty) return const [];

  final status = data[0];
  if (status < 0x80) return const [];

  final command = status & 0xF0;
  final channel = status & 0x0F;

  return switch (command) {
    _noteOffCommand => _parseNoteOff(data, channel, timestamp),
    _noteOnCommand => _parseNoteOn(data, channel, timestamp),
    _controlChangeCommand => _parseControlChange(data, channel, timestamp),
    _ => const [],
  };
}

List<PerformanceInputEvent> _parseNoteOff(
  Uint8List data,
  int channel,
  DateTime timestamp,
) {
  if (data.length < 3) return const [];
  return [
    PerformanceInputEvent.noteOff(
      midiNote: data[1],
      velocity: data[2],
      channel: channel,
      timestamp: timestamp,
    ),
  ];
}

List<PerformanceInputEvent> _parseNoteOn(
  Uint8List data,
  int channel,
  DateTime timestamp,
) {
  if (data.length < 3) return const [];
  final midiNote = data[1];
  final velocity = data[2];
  if (velocity == 0) {
    return [
      PerformanceInputEvent.noteOff(
        midiNote: midiNote,
        channel: channel,
        timestamp: timestamp,
      ),
    ];
  }
  return [
    PerformanceInputEvent.noteOn(
      midiNote: midiNote,
      velocity: velocity,
      channel: channel,
      timestamp: timestamp,
    ),
  ];
}

List<PerformanceInputEvent> _parseControlChange(
  Uint8List data,
  int channel,
  DateTime timestamp,
) {
  if (data.length < 3) return const [];
  if (data[1] != _sustainController) return const [];
  return [
    PerformanceInputEvent.sustain(
      isDown: data[2] >= _sustainOnThreshold,
      channel: channel,
      timestamp: timestamp,
    ),
  ];
}
