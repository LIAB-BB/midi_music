import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/k478_score_alignment.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('K.478 钢琴声部按 MIDI 小节对齐，且不替换播放数据', () {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final song = MidiFileParser().parseBytes(
      bytes,
      fileName: 'mozart_k478_piano_quartet.mid',
    );

    final alignment = K478ScoreAlignment.compile(song);
    final session = alignment.toSession();

    expect(identical(session.songData, song), isTrue);
    expect(session.sourceType, ScoreSourceType.midiNotation);
    expect(session.mappingStatus, ScoreMappingStatus.complete);
    expect(session.hasInteractiveScore, isTrue);
    expect(session.selectedPartIds, {alignment.pianoPartId});
    expect(alignment.musicXml, contains('<measure'));
    expect(alignment.measures, hasLength(360));
    expect(alignment.measures.first.ordinal, 1);
    expect(alignment.measures.first.startTick, 0);
    expect(alignment.measures.last.endTick, 552576);

    final performerNoteCount = song.tracks
        .where((track) => k478PerformerTrackIndexes.contains(track.index))
        .fold<int>(0, (total, track) => total + track.notes.length);
    expect(alignment.performerNotes, hasLength(performerNoteCount));
    expect(
      alignment.performerNotes.map((note) => note.trackIndex).toSet(),
      k478PerformerTrackIndexes,
    );

    const measureLength = 1536;
    for (final measure in alignment.measures) {
      final isLast = measure.ordinal == alignment.measures.length;
      expect(
        measure.endTick - measure.startTick,
        isLast ? lessThanOrEqualTo(measureLength) : measureLength,
      );
      expect(measure.startTick, (measure.ordinal - 1) * measureLength);
    }

    for (final note in alignment.performerNotes) {
      expect(
        alignment.measureOrdinalAtTick(note.startTick),
        note.measureOrdinal,
      );
      expect(note.measureOrdinal, (note.startTick ~/ measureLength) + 1);
      expect(
        alignment.measureStartTick(note.measureOrdinal),
        lessThanOrEqualTo(note.startTick),
      );
    }
    expect(
      alignment.performerNoteCountInMeasure(1),
      alignment.performerNotes.where((note) => note.measureOrdinal == 1).length,
    );
  });

  test('缺少固定弦乐和钢琴轨道的曲目不能编译成 K.478 对齐', () {
    final song = MidiSongData(
      fileName: 'other.mid',
      format: 1,
      ticksPerBeat: 384,
      tracks: [
        MidiTrackInfo(
          index: 4,
          name: 'upper',
          channels: const {0},
          programByChannel: const {0: 0},
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 80,
              channel: 0,
              startTick: 0,
              endTick: 384,
            ),
          ],
        ),
      ],
      timeline: const [],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 333333)],
      timeSignatureChanges: [
        TimeSignatureChange(tick: 0, numerator: 2, denominator: 2),
      ],
      totalTicks: 1536,
      totalDuration: 1,
    );

    expect(() => K478ScoreAlignment.compile(song), throwsStateError);
  });

  test('查询不存在的小节会拒绝', () {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final song = MidiFileParser().parseBytes(
      bytes,
      fileName: 'mozart_k478_piano_quartet.mid',
    );
    final alignment = K478ScoreAlignment.compile(song);

    expect(() => alignment.measureStartTick(0), throwsArgumentError);
    expect(() => alignment.measureOrdinalAtTick(-1), throwsArgumentError);
    expect(
      () => alignment.measureOrdinalAtTick(alignment.measures.last.endTick + 1),
      throwsStateError,
    );
  });
}
