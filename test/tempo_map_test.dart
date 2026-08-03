import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/tempo_map.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('首个 tempo 晚于 tick 0 时先使用默认 120 BPM', () {
    final tempoMap = TempoMap(
      ticksPerBeat: 480,
      tempoChanges: [TempoChange(tick: 480, microsecondsPerBeat: 1000000)],
    );

    expect(tempoMap.tempoChanges.map((change) => change.tick), [0, 480]);
    expect(tempoMap.tickToSeconds(0), 0);
    expect(tempoMap.tickToSeconds(480), closeTo(0.5, 0.000001));
    expect(tempoMap.tickToSeconds(960), closeTo(1.5, 0.000001));
  });

  test('tempo 变化会排序且同 tick 采用最后一个值', () {
    final tempoMap = TempoMap(
      ticksPerBeat: 480,
      tempoChanges: [
        TempoChange(tick: 960, microsecondsPerBeat: 750000),
        TempoChange(tick: 0, microsecondsPerBeat: 500000),
        TempoChange(tick: 960, microsecondsPerBeat: 1000000),
      ],
    );

    expect(tempoMap.tempoChanges.map((change) => change.tick), [0, 960]);
    expect(tempoMap.getMicrosecondsPerBeatAtTick(960), 1000000);
  });

  test('TempoMap 拒绝非法 PPQ、tick 和 tempo', () {
    expect(
      () => TempoMap(ticksPerBeat: 0, tempoChanges: const []),
      throwsArgumentError,
    );
    expect(
      () => TempoMap(
        ticksPerBeat: 480,
        tempoChanges: [TempoChange(tick: -1, microsecondsPerBeat: 500000)],
      ),
      throwsArgumentError,
    );
    expect(
      () => TempoMap(
        ticksPerBeat: 480,
        tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 0)],
      ),
      throwsArgumentError,
    );
  });

  test('轨道时长取所有音符的最大结束位置', () {
    final track = MidiTrackInfo(
      index: 0,
      notes: [
        MidiNote(
          noteNumber: 60,
          velocity: 80,
          channel: 0,
          startTick: 0,
          endTick: 960,
          endTime: 1,
        ),
        MidiNote(
          noteNumber: 64,
          velocity: 80,
          channel: 0,
          startTick: 480,
          endTick: 720,
          startTime: 0.5,
          endTime: 0.75,
        ),
      ],
    );

    expect(track.durationTick, 960);
    expect(track.duration, 1);
  });
}
