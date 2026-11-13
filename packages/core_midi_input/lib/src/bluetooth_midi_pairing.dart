import 'package:flutter/services.dart';

import 'core_midi_channels.dart';

/// 蓝牙 MIDI 配对失败时的可展示错误。
class BluetoothMidiPairingException implements Exception {
  final String message;

  const BluetoothMidiPairingException(this.message);

  @override
  String toString() => message;
}

/// 蓝牙 MIDI（BLE MIDI）配对入口。
///
/// 蓝牙 MIDI 不能在系统设置里连接，只能由 App 内的系统配对界面发起。
/// 连接成功后设备作为普通 CoreMIDI source 出现，[IosMidiInput] 无需区分
/// USB 与蓝牙。
abstract class BluetoothMidiPairing {
  /// 弹出系统配对界面，用户关闭界面后完成。
  ///
  /// 失败时抛出 [BluetoothMidiPairingException]。
  Future<void> showPairingSheet();
}

/// 基于 iOS `CABTMIDICentralViewController` 的配对实现。
class CoreMidiBluetoothPairing implements BluetoothMidiPairing {
  final MethodChannel _channel;

  const CoreMidiBluetoothPairing({
    MethodChannel channel = coreMidiMethodChannel,
  }) : _channel = channel;

  @override
  Future<void> showPairingSheet() async {
    try {
      await _channel.invokeMethod<void>('showBluetoothPairing');
    } on MissingPluginException {
      throw const BluetoothMidiPairingException('当前平台不支持蓝牙 MIDI 配对');
    } on PlatformException catch (error) {
      throw BluetoothMidiPairingException(error.message ?? '无法打开蓝牙 MIDI 配对界面');
    }
  }
}
