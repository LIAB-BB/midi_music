import 'package:flutter/services.dart';

/// 与 `CoreMidiInputPlugin.swift` 约定的平台通道；仅供本包内部使用。
const coreMidiMethodChannel = MethodChannel(
  'com.liab.midi_music/core_midi_input/methods',
);

const coreMidiEventChannel = EventChannel(
  'com.liab.midi_music/core_midi_input/events',
);
