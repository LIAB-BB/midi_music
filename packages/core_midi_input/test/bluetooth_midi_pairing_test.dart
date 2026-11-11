import 'package:core_midi_input/core_midi_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.liab.midi_music/core_midi_input/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('通过 CoreMIDI 方法通道打开蓝牙配对界面并等待关闭', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });

    await const CoreMidiBluetoothPairing().showPairingSheet();

    expect(calls, ['showBluetoothPairing']);
  });

  test('原生错误转换为可展示的配对异常', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'pairing_in_progress',
        message: '蓝牙 MIDI 配对界面已经打开',
      );
    });

    await expectLater(
      const CoreMidiBluetoothPairing().showPairingSheet(),
      throwsA(
        isA<BluetoothMidiPairingException>().having(
          (error) => error.toString(),
          'message',
          '蓝牙 MIDI 配对界面已经打开',
        ),
      ),
    );
  });

  test('没有原生实现的平台给出明确提示', () async {
    await expectLater(
      const CoreMidiBluetoothPairing().showPairingSheet(),
      throwsA(
        isA<BluetoothMidiPairingException>().having(
          (error) => error.message,
          'message',
          '当前平台不支持蓝牙 MIDI 配对',
        ),
      ),
    );
  });
}
