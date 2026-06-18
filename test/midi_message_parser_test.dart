import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/input/midi_message_parser.dart';
import 'package:midi_music/core/input/performance_input.dart';

void main() {
  final timestamp = DateTime(2026, 1, 1);

  test('解析 note-on 事件', () {
    final events = parseMidiMessageBytes(
      Uint8List.fromList([0x91, 60, 96]),
      timestamp: timestamp,
    );

    expect(events, hasLength(1));
    expect(events.single.type, PerformanceInputEventType.noteOn);
    expect(events.single.midiNote, 60);
    expect(events.single.velocity, 96);
    expect(events.single.channel, 1);
    expect(events.single.timestamp, timestamp);
  });

  test('解析 note-off 事件', () {
    final events = parseMidiMessageBytes(
      Uint8List.fromList([0x82, 64, 32]),
      timestamp: timestamp,
    );

    expect(events, hasLength(1));
    expect(events.single.type, PerformanceInputEventType.noteOff);
    expect(events.single.midiNote, 64);
    expect(events.single.velocity, 32);
    expect(events.single.channel, 2);
  });

  test('note-on velocity 0 视为 note-off', () {
    final events = parseMidiMessageBytes(
      Uint8List.fromList([0x90, 67, 0]),
      timestamp: timestamp,
    );

    expect(events, hasLength(1));
    expect(events.single.type, PerformanceInputEventType.noteOff);
    expect(events.single.midiNote, 67);
    expect(events.single.velocity, 0);
  });

  test('解析 sustain pedal 控制器', () {
    final down = parseMidiMessageBytes(
      Uint8List.fromList([0xB0, 64, 127]),
      timestamp: timestamp,
    );
    final up = parseMidiMessageBytes(
      Uint8List.fromList([0xB0, 64, 0]),
      timestamp: timestamp,
    );

    expect(down.single.type, PerformanceInputEventType.sustain);
    expect(down.single.sustain, isTrue);
    expect(up.single.type, PerformanceInputEventType.sustain);
    expect(up.single.sustain, isFalse);
  });

  test('忽略短消息、实时消息和暂未支持的消息', () {
    expect(
      parseMidiMessageBytes(
        Uint8List.fromList([0x90, 60]),
        timestamp: timestamp,
      ),
      isEmpty,
    );
    expect(
      parseMidiMessageBytes(Uint8List.fromList([0xFE]), timestamp: timestamp),
      isEmpty,
    );
    expect(
      parseMidiMessageBytes(
        Uint8List.fromList([0xE0, 0, 64]),
        timestamp: timestamp,
      ),
      isEmpty,
    );
  });
}
