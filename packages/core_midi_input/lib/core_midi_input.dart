/// iOS CoreMIDI 输入桥接。
///
/// 这个包接收系统已暴露的 CoreMIDI source，不申请麦克风或本地网络权限。
/// 调用 [IosMidiInput.start] 后会自动刷新可用 source。
///
/// [CoreMidiBluetoothPairing] 打开系统蓝牙 MIDI 配对界面；首次打开时 iOS 会
/// 申请蓝牙权限，宿主 App 必须在 Info.plist 中声明
/// `NSBluetoothAlwaysUsageDescription`。
library;

export 'src/bluetooth_midi_pairing.dart';
export 'src/ios_midi_input.dart';
export 'src/midi_input.dart';
