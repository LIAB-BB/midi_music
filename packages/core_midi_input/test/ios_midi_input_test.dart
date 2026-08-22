import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBridge implements MidiInputPlatformBridge {
  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast();
  final Object? startResult;
  var stopped = false;

  _FakeBridge({this.startResult = const []});

  @override
  Stream<Object?> events() => controller.stream;

  @override
  Future<Object?> start() async => startResult;

  @override
  Future<void> stop() async {
    stopped = true;
  }

  Future<void> close() => controller.close();
}

void main() {
  test('将设备和 MIDI Note On 从平台事件转换为强类型流', () async {
    final bridge = _FakeBridge(
      startResult: const [
        {'id': 'usb-1', 'name': 'Digital Piano'},
      ],
    );
    final input = IosMidiInput(bridge: bridge);
    final messages = <MidiInputMessage>[];
    final subscription = input.messages.listen(messages.add);

    await input.start();
    expect(input.state.primaryDeviceName, 'Digital Piano');

    bridge.controller.add({
      'type': 'midi',
      'status': 0x91,
      'data1': 60,
      'data2': 96,
      'timestampMicros': 123456,
    });
    await Future<void>.delayed(Duration.zero);

    expect(messages, hasLength(1));
    expect(messages.single.channel, 1);
    expect(messages.single.noteNumber, 60);
    expect(messages.single.isNoteOn, isTrue);

    await input.dispose();
    await subscription.cancel();
    expect(bridge.stopped, isTrue);
    await bridge.close();
  });

  test('设备列表能表达 USB 拔出和重连', () async {
    final bridge = _FakeBridge(
      startResult: const [
        {'id': 'usb-1', 'name': 'Digital Piano'},
      ],
    );
    final input = IosMidiInput(bridge: bridge);
    final states = <MidiInputState>[];
    final subscription = input.states.listen(states.add);

    await input.start();
    bridge.controller.add({'type': 'devices', 'devices': const []});
    await Future<void>.delayed(Duration.zero);
    bridge.controller.add({
      'type': 'devices',
      'devices': const [
        {'id': 'usb-2', 'name': 'Digital Piano 2'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(states.map((state) => state.isConnected), [isTrue, isFalse, isTrue]);
    expect(input.state.primaryDeviceName, 'Digital Piano 2');

    await input.dispose();
    await subscription.cancel();
    await bridge.close();
  });
}
