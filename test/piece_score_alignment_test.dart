import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/piece_score_alignment.dart';
import 'package:midi_music/core/score/piece_manifest.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  late PieceManifest manifest;

  setUpAll(() {
    manifest = PieceManifest.parse(
      File('assets/pieces/k478.json').readAsStringSync(),
    );
  });

  test('K.478 曲目包声明演奏者和伴奏轨道', () {
    expect(manifest.id, 'mozart-k478');
    expect(manifest.performanceFile, 'mozart_k478_piano_quartet.mid');
    expect(manifest.performerTrackIndexes, {4, 5});
    expect(manifest.accompanimentTrackIndexes, {1, 2, 3});
  });

  test('曲目包把演奏者声部按 MIDI 小节对齐，且不替换播放数据', () {
    final song = _k478Song();
    final alignment = PieceScoreAlignment.compile(song, manifest);
    final session = alignment.toSession();

    expect(identical(session.songData, song), isTrue);
    expect(session.sourceFingerprint, 'piece:mozart-k478');
    expect(session.sourceType, ScoreSourceType.midiNotation);
    expect(session.mappingStatus, ScoreMappingStatus.complete);
    expect(session.hasInteractiveScore, isTrue);
    expect(session.selectedPartIds, alignment.notationPartIds);
    expect(alignment.notationPartIds, hasLength(1));
    expect(alignment.musicXml, contains('<measure'));
    expect(alignment.measures, hasLength(360));
    expect(alignment.measures.first.ordinal, 1);
    expect(alignment.measures.first.startTick, 0);
    expect(alignment.measures.last.endTick, 552576);

    final performerNoteCount = song.tracks
        .where((track) => manifest.performerTrackIndexes.contains(track.index))
        .fold<int>(0, (total, track) => total + track.notes.length);
    expect(alignment.performerNotes, hasLength(performerNoteCount));
    expect(
      alignment.performerNotes.map((note) => note.trackIndex).toSet(),
      manifest.performerTrackIndexes,
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
    }
  });

  test('轨道合同不符的曲目不能按该曲目包编译', () {
    final song = MidiSongData(
      fileName: manifest.performanceFile,
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

    expect(() => PieceScoreAlignment.compile(song, manifest), throwsStateError);
  });

  test('查询不存在的小节会拒绝', () {
    final alignment = PieceScoreAlignment.compile(_k478Song(), manifest);

    expect(() => alignment.measureStartTick(0), throwsArgumentError);
    expect(() => alignment.measureOrdinalAtTick(-1), throwsArgumentError);
    expect(
      () => alignment.measureOrdinalAtTick(alignment.measures.last.endTick + 1),
      throwsStateError,
    );
  });

  test('曲目包拒绝重复轨道和缺少演奏者', () {
    expect(
      () => PieceManifest.parse(
        '{"id":"x","title":"x","performanceFile":"x.mid","ticksPerBeat":384,"tracks":[{"index":1,"role":"performer","program":0},{"index":1,"role":"accompaniment","program":40}]}',
      ),
      throwsFormatException,
    );
    expect(
      () => PieceManifest.parse(
        '{"id":"x","title":"x","performanceFile":"x.mid","ticksPerBeat":384,"tracks":[{"index":1,"role":"accompaniment","program":40}]}',
      ),
      throwsFormatException,
    );
  });
}

MidiSongData _k478Song() {
  final bytes = File(
    'assets/midi/mozart_k478_piano_quartet.mid',
  ).readAsBytesSync();
  return MidiFileParser().parseBytes(
    bytes,
    fileName: 'mozart_k478_piano_quartet.mid',
  );
}
