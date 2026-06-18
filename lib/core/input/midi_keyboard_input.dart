import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'midi_message_parser.dart';
import 'performance_input.dart';

class MidiInputDeviceInfo {
  final String id;
  final String name;
  final String type;
  final bool connected;

  const MidiInputDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    required this.connected,
  });

  factory MidiInputDeviceInfo.fromDevice(MidiDevice device) {
    return MidiInputDeviceInfo(
      id: device.id,
      name: device.name,
      type: device.type,
      connected: device.connected,
    );
  }
}

class MidiInputSnapshot {
  final List<MidiInputDeviceInfo> devices;
  final String? connectedDeviceName;
  final PerformanceInputEvent? lastEvent;
  final String? lastError;
  final bool isListening;

  const MidiInputSnapshot({
    this.devices = const [],
    this.connectedDeviceName,
    this.lastEvent,
    this.lastError,
    this.isListening = false,
  });

  MidiInputSnapshot copyWith({
    List<MidiInputDeviceInfo>? devices,
    String? connectedDeviceName,
    PerformanceInputEvent? lastEvent,
    String? lastError,
    bool? isListening,
    bool clearError = false,
  }) {
    return MidiInputSnapshot(
      devices: devices ?? this.devices,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      lastEvent: lastEvent ?? this.lastEvent,
      lastError: clearError ? null : lastError ?? this.lastError,
      isListening: isListening ?? this.isListening,
    );
  }
}

class MidiKeyboardInput implements PerformanceInput {
  final MidiCommand _midiCommand;
  final _eventController = StreamController<PerformanceInputEvent>.broadcast();
  final _snapshotController = StreamController<MidiInputSnapshot>.broadcast();

  StreamSubscription<MidiPacket>? _midiSubscription;
  StreamSubscription<String>? _setupSubscription;
  MidiInputSnapshot _snapshot = const MidiInputSnapshot();
  bool _isStarted = false;
  bool _isDisposed = false;

  MidiKeyboardInput({MidiCommand? midiCommand})
    : _midiCommand = midiCommand ?? MidiCommand();

  @override
  Stream<PerformanceInputEvent> get events => _eventController.stream;

  Stream<MidiInputSnapshot> get snapshots => _snapshotController.stream;

  MidiInputSnapshot get currentSnapshot => _snapshot;

  @override
  Future<void> start() async {
    if (_isDisposed) {
      throw StateError('MidiKeyboardInput has been disposed');
    }
    if (_isStarted) return;

    _isStarted = true;
    _emitSnapshot(_snapshot.copyWith(isListening: true, clearError: true));

    _midiSubscription = _midiCommand.onMidiDataReceived?.listen(
      _handleMidiPacket,
      onError: (Object error, StackTrace stackTrace) {
        _emitSnapshot(_snapshot.copyWith(lastError: error.toString()));
      },
    );
    _setupSubscription = _midiCommand.onMidiSetupChanged?.listen((_) {
      unawaited(refreshDevices(connectFirstAvailable: true));
    });

    await refreshDevices(connectFirstAvailable: true);
  }

  Future<void> refreshDevices({bool connectFirstAvailable = false}) async {
    if (_isDisposed) return;

    try {
      final devices = await _midiCommand.devices ?? const <MidiDevice>[];
      if (_isDisposed) return;

      MidiDevice? connectedDevice = _firstConnectedDevice(devices);
      if (connectFirstAvailable &&
          connectedDevice == null &&
          devices.isNotEmpty) {
        final firstDevice = devices.first;
        await _midiCommand.connectToDevice(firstDevice);
        if (_isDisposed) return;
        connectedDevice = firstDevice;
      }

      _emitSnapshot(
        _snapshot.copyWith(
          devices: devices.map(MidiInputDeviceInfo.fromDevice).toList(),
          connectedDeviceName: connectedDevice?.name,
          clearError: true,
        ),
      );
    } on Object catch (error) {
      if (_isDisposed) return;
      _emitSnapshot(_snapshot.copyWith(lastError: error.toString()));
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isStarted = false;
    await _midiSubscription?.cancel();
    await _setupSubscription?.cancel();
    await _eventController.close();
    await _snapshotController.close();
  }

  void _handleMidiPacket(MidiPacket packet) {
    final timestamp = DateTime.now();
    final events = parseMidiMessageBytes(packet.data, timestamp: timestamp);
    for (final event in events) {
      _eventController.add(event);
      _emitSnapshot(
        _snapshot.copyWith(
          connectedDeviceName: packet.device.name,
          lastEvent: event,
          clearError: true,
        ),
      );
    }
  }

  void _emitSnapshot(MidiInputSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }
}

MidiDevice? _firstConnectedDevice(List<MidiDevice> devices) {
  for (final device in devices) {
    if (device.connected) return device;
  }
  return null;
}
