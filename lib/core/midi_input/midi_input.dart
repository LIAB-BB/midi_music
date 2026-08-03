import 'dart:async';

class MidiInputDevice {
  final String id;
  final String name;

  const MidiInputDevice({required this.id, required this.name});
}

class MidiInputState {
  final List<MidiInputDevice> devices;
  final String? errorMessage;

  const MidiInputState({this.devices = const [], this.errorMessage});

  bool get isConnected => devices.isNotEmpty;
  String? get primaryDeviceName => devices.firstOrNull?.name;
}

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

abstract class MidiInput {
  Stream<MidiInputMessage> get messages;
  Stream<MidiInputState> get states;
  MidiInputState get state;

  Future<void> start();
  Future<void> dispose();
}
