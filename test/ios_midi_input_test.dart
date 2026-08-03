import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi_input/ios_midi_input.dart';
import 'package:midi_music/core/midi_input/midi_input.dart';

void main() {
  test('解析设备状态和 Note On/Off 消息', () async {
    final bridge = _FakeMidiInputPlatformBridge();
    final input = IosMidiInput(bridge: bridge);
    final messages = <MidiInputMessage>[];
    final subscription = input.messages.listen(messages.add);

    await input.start();

    expect(input.state.isConnected, isTrue);
    expect(input.state.primaryDeviceName, 'Digital Piano');
    expect(bridge.startCount, 1);

    bridge.emit({
      'type': 'midi',
      'status': 0x91,
      'data1': 60,
      'data2': 96,
      'timestampMicros': 123456,
    });
    bridge.emit({
      'type': 'midi',
      'status': 0x91,
      'data1': 60,
      'data2': 0,
      'timestampMicros': 223456,
    });
    await pumpEventQueue();

    final noteOn = messages[0];
    final noteOff = messages[1];
    expect(noteOn.isNoteOn, isTrue);
    expect(noteOn.channel, 1);
    expect(noteOn.noteNumber, 60);
    expect(noteOn.velocity, 96);
    expect(noteOn.timestamp.microsecondsSinceEpoch, 123456);
    expect(noteOff.isNoteOff, isTrue);

    await input.start();
    expect(bridge.startCount, 1);

    await subscription.cancel();
    await input.dispose();
    expect(bridge.stopCount, 1);
  });

  test('设备拔出后更新为未连接', () async {
    final bridge = _FakeMidiInputPlatformBridge();
    final input = IosMidiInput(bridge: bridge);
    await input.start();

    bridge.emit({'type': 'devices', 'devices': <Object>[]});
    await pumpEventQueue();

    expect(input.state.isConnected, isFalse);
    await input.dispose();
  });
}

class _FakeMidiInputPlatformBridge implements MidiInputPlatformBridge {
  final controller = StreamController<Object?>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<Object?> events() => controller.stream;

  void emit(Object? event) => controller.add(event);

  @override
  Future<Object?> start() async {
    startCount++;
    return [
      {'id': '42', 'name': 'Digital Piano'},
    ];
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await controller.close();
  }
}
