import 'dart:async';

/// CoreMIDI source 的可展示信息。
class MidiInputDevice {
  final String id;
  final String name;

  const MidiInputDevice({required this.id, required this.name});
}

/// 当前输入设备状态。
class MidiInputState {
  final List<MidiInputDevice> devices;
  final String? errorMessage;

  const MidiInputState({this.devices = const [], this.errorMessage});

  bool get isConnected => devices.isNotEmpty;
  String? get primaryDeviceName => devices.firstOrNull?.name;
}

/// 单条通道 MIDI 消息；通道编号遵循 MIDI 的 0–15 约定。
class MidiInputMessage {
  final int status;
  final int data1;
  final int data2;
  final DateTime timestamp;

  const MidiInputMessage({
    required this.status,
    required this.data1,
    required this.data2,
    required this.timestamp,
  });

  int get command => status & 0xF0;
  int get channel => status & 0x0F;
  bool get isNoteOn => command == 0x90 && data2 > 0;
  bool get isNoteOff => command == 0x80 || (command == 0x90 && data2 == 0);
  int get noteNumber => data1;
  int get velocity => data2;
}

/// 可替换的输入边界，便于上层把 CoreMIDI 换成测试输入。
abstract class MidiInput {
  Stream<MidiInputMessage> get messages;
  Stream<MidiInputState> get states;
  MidiInputState get state;

  Future<void> start();
  Future<void> dispose();
}
