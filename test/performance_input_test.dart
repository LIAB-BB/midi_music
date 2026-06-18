import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/input/fake_midi_input.dart';
import 'package:midi_music/core/input/performance_input.dart';

void main() {
  test('FakeMidiInput 输出 note 和 sustain 事件', () async {
    final input = FakeMidiInput();
    final events = <PerformanceInputEvent>[];
    final subscription = input.events.listen(events.add);
    final start = DateTime(2026);

    await input.start();
    input.emitNoteOn(midiNote: 60, velocity: 90, channel: 1, timestamp: start);
    input.emitNoteOff(
      midiNote: 60,
      channel: 1,
      timestamp: start.add(const Duration(milliseconds: 300)),
    );
    input.emitSustain(
      isDown: true,
      channel: 1,
      timestamp: start.add(const Duration(milliseconds: 350)),
    );
    await pumpEventQueue();

    expect(events.map((event) => event.type), [
      PerformanceInputEventType.noteOn,
      PerformanceInputEventType.noteOff,
      PerformanceInputEventType.sustain,
    ]);
    expect(events.first.midiNote, 60);
    expect(events.first.velocity, 90);
    expect(events.last.sustain, isTrue);

    await subscription.cancel();
    await input.dispose();
  });

  test('FakeMidiInput 未启动时拒绝发事件', () {
    final input = FakeMidiInput();

    expect(
      () => input.emitNoteOn(midiNote: 60, velocity: 80),
      throwsStateError,
    );
  });
}
