/// iOS CoreMIDI 输入桥接。
///
/// 这个包只负责接收系统已暴露的 CoreMIDI source，不申请麦克风、
/// 本地网络或蓝牙权限。调用 [IosMidiInput.start] 后会自动刷新可用 source。
library;

export 'src/ios_midi_input.dart';
export 'src/midi_input.dart';
