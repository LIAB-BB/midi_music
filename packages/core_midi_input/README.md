# core_midi_input

仅供本仓库使用的 iOS CoreMIDI 输入插件。它将系统 CoreMIDI source 的设备列表
和通道 MIDI 消息映射为 Dart 的 `MidiInput` 流，供 K.478 USB 跟随候选使用。

## 行为边界

- 只使用 CoreMIDI；不打开麦克风、不申请本地网络或蓝牙权限；
- `start()` 会订阅当前全部系统 source，并在 source 变化时刷新列表；
- 每个 source 分别维护 running-status 解析状态，避免多个端点的字节流互串；
- 目前不强行判断 source 是否为物理 USB 端点，因此真机验收须确认显示的
  source 确为目标电子琴。

## 使用方式

```dart
final input = IosMidiInput();
await input.start();
input.messages.where((message) => message.isNoteOn).listen(handleNoteOn);
```

`dispose()` 会断开 source、取消 Dart 流并释放对应资源。该包不是独立发布物；
变更需要同时运行 `flutter analyze` 与 `flutter test`。
