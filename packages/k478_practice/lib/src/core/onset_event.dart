/// 由 USB MIDI Note On 转换出的起拍事件。
class OnsetEvent {
  final int midiNote;
  final double frequency;
  final double volume;
  final DateTime timestamp;

  OnsetEvent({
    required this.midiNote,
    required this.frequency,
    required this.volume,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
