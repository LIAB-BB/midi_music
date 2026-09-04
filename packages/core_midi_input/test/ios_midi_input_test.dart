import 'dart:async';

import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBridge implements MidiInputPlatformBridge {
  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast();
  final Object? startResult;
  var stopped = false;
  var stopCalls = 0;
  Completer<void>? startGate;
  Completer<void>? startStarted;

  _FakeBridge({this.startResult = const []});

  @override
  Stream<Object?> events() => controller.stream;

  @override
  Future<Object?> start() async {
    startStarted?.complete();
    await startGate?.future;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCalls++;
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
    bridge.controller.add({'type': 'devices', 'devices': const <Object?>[]});
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

  test('dispose 会等待进行中的平台 start，并最终 stop', () async {
    final bridge =
        _FakeBridge(
            startResult: const [
              {'id': 'usb-1', 'name': 'Digital Piano'},
            ],
          )
          ..startGate = Completer<void>()
          ..startStarted = Completer<void>();
    final input = IosMidiInput(bridge: bridge);

    final starting = input.start();
    await bridge.startStarted!.future;
    final disposing = input.dispose();
    expect(bridge.stopped, isFalse);

    bridge.startGate!.complete();
    await starting;
    await disposing;

    expect(bridge.stopCalls, 1);
    expect(input.state.isConnected, isFalse);
    await expectLater(input.start(), throwsStateError);
    await bridge.close();
  });

  test('dispose 后排队的平台错误不会再写入消息流', () async {
    final bridge = _FakeBridge()
      ..startGate = Completer<void>()
      ..startStarted = Completer<void>();
    final input = IosMidiInput(bridge: bridge);
    final errors = <Object>[];
    final subscription = input.messages.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) => errors.add(error),
    );

    final starting = input.start();
    await bridge.startStarted!.future;
    final disposing = input.dispose();
    bridge.controller.addError(StateError('late platform error'));
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
    bridge.startGate!.complete();
    await starting;
    await disposing;
    await subscription.cancel();
    await bridge.close();
  });
}
