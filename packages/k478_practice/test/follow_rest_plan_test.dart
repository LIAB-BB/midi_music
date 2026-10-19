import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/follow_rest_plan.dart';
import 'package:k478_practice/src/models/midi_track.dart';

MidiSongData _song(List<List<MidiNote>> trackNotes) => MidiSongData(
  fileName: 'rests.mid',
  format: 1,
  ticksPerBeat: 480,
  tracks: [
    for (var index = 0; index < trackNotes.length; index++)
      MidiTrackInfo(index: index, notes: trackNotes[index]),
  ],
  timeline: const [],
  tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
  timeSignatureChanges: const [],
  totalTicks: 9600,
  totalDuration: 10,
);

MidiNote _note(double start, double end) => MidiNote(
  noteNumber: 60,
  velocity: 100,
  channel: 0,
  startTick: (start * 480).round(),
  endTick: (end * 480).round(),
  startTime: start,
  endTime: end,
);

void main() {
  test('所有声部都沉默超过阈值时生成一段全局休止', () {
    final plan = RestPlan.fromSong(
      _song([
        [_note(0, 0.5), _note(2, 2.5)],
      ]),
    );

    expect(plan.rests, hasLength(1));
    expect(plan.rests.single.start, 0.5);
    expect(plan.rests.single.end, 2.0);
    expect(plan.nextAfter(0.2)?.start, 0.5);
  });

  test('其他轨道仍在发声时不算全局休止', () {
    final plan = RestPlan.fromSong(
      _song([
        [_note(0, 0.5)],
        [_note(0.4, 1.0)],
      ]),
    );

    expect(plan.rests, isEmpty);
  });

  test('短于阈值的空隙不生成休止，降低阈值后才生成', () {
    final song = _song([
      [_note(0, 0.5), _note(1.0, 1.5)],
    ]);
    expect(RestPlan.fromSong(song).rests, isEmpty);
    expect(RestPlan.fromSong(song, minSilenceSeconds: 0.4).rests, hasLength(1));
  });

  test('空曲目不生成休止', () {
    final plan = RestPlan.fromSong(_song([]));
    expect(plan.rests, isEmpty);
    expect(plan.nextAfter(0), isNull);
  });

  test('nextAfter 跳过已经过去的休止', () {
    final plan = RestPlan.fromSong(
      _song([
        [_note(0, 0.5), _note(2, 2.5), _note(4, 4.5)],
      ]),
    );

    expect(plan.rests, hasLength(2));
    expect(plan.nextAfter(0.5)?.start, 2.5);
    expect(plan.nextAfter(2.0)?.start, 2.5);
    expect(plan.nextAfter(2.5), isNull);
  });
}
