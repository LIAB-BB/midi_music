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

  final events = <PerformanceInputEvent>[];
  var index = 0;
  while (index < data.length) {
    final status = data[index];
    if (status < 0x80) {
      // Running status is intentionally not supported yet. Skip stray data
      // bytes so a malformed packet does not block later status bytes.
      index += 1;
      continue;
    }

    final length = _messageLength(status);
    if (length == null || index + length > data.length) break;

    final message = Uint8List.sublistView(data, index, index + length);
    final command = status & 0xF0;
    final channel = status & 0x0F;
    events.addAll(
      switch (command) {
        _noteOffCommand => _parseNoteOff(message, channel, timestamp),
        _noteOnCommand => _parseNoteOn(message, channel, timestamp),
        _controlChangeCommand => _parseControlChange(
          message,
          channel,
          timestamp,
        ),
        _ => const [],
      },
    );
    index += length;
  }

  return events;
}

int? _messageLength(int status) {
  if (status >= 0x80 && status <= 0xEF) {
    final command = status & 0xF0;
    return switch (command) {
      0xC0 || 0xD0 => 2,
      _ => 3,
    };
  }
  if (status >= 0xF8) return 1;
  return null;
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
