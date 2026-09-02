import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/measure_map.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/midi/tempo_map.dart';
import 'package:midi_music/core/notation/midi_part_analyzer.dart';
import 'package:midi_music/core/notation/midi_to_musicxml_converter.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';

typedef _MeasureAudit = ({
  Map<int, List<(int, int)>> intervalsByVoice,
  Map<int, int> durationByVoice,
  List<int> backups,
  List<int> forwards,
});

void main() {
  test('钢琴输出双谱表、和弦、休止和跨小节 tie', () {
    final fixture = _pianoFixture();

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<staves>2</staves>'));
    expect(result.musicXml, contains('<clef number="1">'));
    expect(result.musicXml, contains('<clef number="2">'));
    expect(result.musicXml, contains('<chord/>'));
    expect(result.musicXml, contains('<rest/>'));
    expect(result.musicXml, contains('<tie type="start"/>'));
    expect(result.musicXml, contains('<tie type="stop"/>'));
    expect(result.musicXml, startsWith('<?xml'));
    final expected = MeasureMap(
      song: fixture.song,
      tempoMap: TempoMap(
        ticksPerBeat: fixture.song.ticksPerBeat,
        tempoChanges: fixture.song.tempoChanges,
      ),
    ).measures;
    expect(
      result.measures.map((measure) => (measure.startTick, measure.endTick)),
      expected.map((measure) => (measure.startTick, measure.endTick)),
    );
  });

  test('K.478 默认钢琴谱不把超过十度的同时音塞给同一只手', () {
    final bytes = File(
      'assets/midi/mozart_k478_piano_quartet.mid',
    ).readAsBytesSync();
    final song = MidiFileParser().parseBytes(
      bytes,
      fileName: 'mozart_k478_piano_quartet.mid',
    );
    final catalog = MidiPartAnalyzer().analyze(
      song,
      fingerprint: 'asset:assets/midi/mozart_k478_piano_quartet.mid',
    );
    final piano = catalog.parts.singleWhere(
      (part) => part.kind == MidiPartKind.piano,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      song,
      catalog: catalog,
      selectedPartIds: {piano.id},
    );

    expect(
      _wideSameStaffChords(result.musicXml, maxSemitones: 16),
      isEmpty,
      reason: '同一 staff 内同时音超过十度，不符合普通钢琴左右手分谱',
    );
  });

  test('upper 和 lower 轨道同时音保留原左右手谱表', () {
    final upper = _track(0, 'upper', 0, [
      _note(72, 0, 0, 480),
      _note(76, 0, 0, 480),
      _note(81, 0, 0, 480),
    ]);
    final lower = _track(1, 'lower', 1, [_note(60, 1, 0, 480)]);
    final song = _song(
      fileName: 'explicit-hands.mid',
      tracks: [upper, lower],
      totalTicks: 1920,
    );
    final piano = MidiScorePart(
      id: 'piano:0:0,1:1',
      label: '钢琴',
      kind: MidiPartKind.piano,
      sources: [
        MidiPartSource(trackIndex: 0, channels: {0}),
        MidiPartSource(trackIndex: 1, channels: {1}),
      ],
      noteCount: 4,
      staffMode: MidiStaffMode.grandStaff,
    );
    final catalog = MidiScoreCatalog(
      fingerprint: 'explicit-hands',
      parts: [piano],
      recommendedPartIds: {piano.id},
      recommendedOrigin: MidiSelectionOrigin.automaticPiano,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      song,
      catalog: catalog,
      selectedPartIds: {piano.id},
    );
    final firstMeasureNotes = _pitchedNotesByMeasure(result.musicXml).first;

    expect(
      _notesAtPitch(firstMeasureNotes, step: 'C', octave: 4).single,
      contains('<staff>2</staff>'),
    );
    for (final pitch in [('C', 5), ('E', 5), ('A', 5)]) {
      expect(
        _notesAtPitch(
          firstMeasureNotes,
          step: pitch.$1,
          octave: pitch.$2,
        ).single,
        contains('<staff>1</staff>'),
      );
    }
  });

  test('附点、三连音和超阈值误差使用候选时值并发出量化警告', () {
    final track = _track(0, 'Violin', 0, [
      _note(60, 0, 0, 720),
      _note(62, 0, 960, 1280),
      _note(64, 0, 1440, 1460),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<dot/>'));
    expect(result.musicXml, contains('<time-modification>'));
    expect(result.musicXml, contains('<actual-notes>3</actual-notes>'));
    expect(result.warnings, contains(MidiNotationWarning.rhythmQuantized));
  });

  test('前置校验拒绝空选择、失效 ID、无音符声部和超限 MIDI', () {
    final valid = _singlePartFixture(
      track: _track(0, 'Violin', 0, [_note(60, 0, 0, 480)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );
    final converter = MidiToMusicXmlConverter();

    expect(
      () => converter.convertSync(
        valid.song,
        catalog: valid.catalog,
        selectedPartIds: const {},
      ),
      throwsArgumentError,
    );
    expect(
      () => converter.convertSync(
        valid.song,
        catalog: valid.catalog,
        selectedPartIds: const {'missing'},
      ),
      throwsArgumentError,
    );

    final empty = _singlePartFixture(
      track: _track(0, 'Silent', 0, const []),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );
    expect(
      () => converter.convertSync(
        empty.song,
        catalog: empty.catalog,
        selectedPartIds: empty.catalog.recommendedPartIds,
      ),
      throwsA(isA<StateError>()),
    );

    final tooManyTracks = _song(
      fileName: '65-tracks.mid',
      tracks: List<MidiTrackInfo>.generate(
        65,
        (index) => _track(index, 'Track $index', index % 16, [
          _note(60, index % 16, 0, 480),
        ]),
      ),
      totalTicks: 1920,
    );
    expect(
      () => converter.convertSync(
        tooManyTracks,
        catalog: valid.catalog,
        selectedPartIds: valid.catalog.recommendedPartIds,
      ),
      throwsA(isA<StateError>()),
    );

    final sourceTracks = List<MidiTrackInfo>.generate(5, (trackIndex) {
      final notes = List<MidiNote>.generate(
        16,
        (channel) => _note(60, channel, 0, 480),
      );
      return MidiTrackInfo(
        index: trackIndex,
        name: 'Format 0 slice $trackIndex',
        channels: Set<int>.from(List<int>.generate(16, (index) => index)),
        programByChannel: const {},
        notes: notes,
      );
    });
    final sourceParts = List<MidiScorePart>.generate(65, (index) {
      final trackIndex = index ~/ 16;
      final channel = index % 16;
      return MidiScorePart(
        id: 'source:$trackIndex:$channel',
        label: 'Source $index',
        kind: MidiPartKind.strings,
        sources: [
          MidiPartSource(trackIndex: trackIndex, channels: {channel}),
        ],
        noteCount: 1,
        staffMode: MidiStaffMode.singleStaff,
      );
    });
    final tooManySourcesCatalog = MidiScoreCatalog(
      fingerprint: '65-sources',
      parts: sourceParts,
      recommendedPartIds: {sourceParts.first.id},
      recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
    );
    expect(
      () => converter.convertSync(
        _song(
          fileName: '65-sources.mid',
          tracks: sourceTracks,
          totalTicks: 1920,
        ),
        catalog: tooManySourcesCatalog,
        selectedPartIds: {sourceParts.first.id},
      ),
      throwsA(isA<StateError>()),
    );

    final repeated = List<MidiNote>.filled(
      500001,
      _note(60, 0, 0, 480),
      growable: false,
    );
    final tooManyNotes = _song(
      fileName: 'too-many-notes.mid',
      tracks: [_track(0, 'Huge', 0, repeated)],
      totalTicks: 1920,
    );
    expect(
      () => converter.convertSync(
        tooManyNotes,
        catalog: valid.catalog,
        selectedPartIds: valid.catalog.recommendedPartIds,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('多选声部生成等长总谱且 Format 0 严格按 track 和 channel 过滤', () {
    final sharedTrack = MidiTrackInfo(
      index: 0,
      name: 'Shared',
      channels: {0, 1},
      programByChannel: const {0: 0, 1: 40},
      notes: [_note(60, 0, 0, 480), _note(61, 1, 0, 480)],
    );
    final lower = _track(1, 'Lower', 2, [_note(48, 2, 0, 960)]);
    final violin = _track(2, '<Violin & "Lead">', 3, [_note(67, 3, 480, 1200)]);
    final pianoPart = MidiScorePart(
      id: 'piano:0:0,1:2',
      label: 'Piano & Keys',
      kind: MidiPartKind.piano,
      sources: [
        MidiPartSource(trackIndex: 0, channels: {0}),
        MidiPartSource(trackIndex: 1, channels: {2}),
      ],
      noteCount: 2,
      staffMode: MidiStaffMode.grandStaff,
    );
    final violinPart = MidiScorePart(
      id: 'source:2:3',
      label: '<Violin & "Lead">',
      kind: MidiPartKind.strings,
      sources: [
        MidiPartSource(trackIndex: 2, channels: {3}),
      ],
      noteCount: 1,
      staffMode: MidiStaffMode.singleStaff,
    );
    final song = _song(
      fileName: '<Suite & "Finale">.mid',
      tracks: [sharedTrack, lower, violin],
      totalTicks: 3840,
    );
    final catalog = MidiScoreCatalog(
      fingerprint: 'ensemble',
      parts: [pianoPart, violinPart],
      recommendedPartIds: {pianoPart.id, violinPart.id},
      recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      song,
      catalog: catalog,
      selectedPartIds: {pianoPart.id, violinPart.id},
    );

    expect(
      RegExp(r'<score-part id=').allMatches(result.musicXml),
      hasLength(2),
    );
    expect(_measureCountsByPart(result.musicXml).toSet(), {
      result.measures.length,
    });
    expect(result.musicXml, contains('&lt;Suite &amp; &quot;Finale&quot;&gt;'));
    expect(result.musicXml, contains('&lt;Violin &amp; &quot;Lead&quot;&gt;'));
    expect(result.musicXml, isNot(contains('<alter>1</alter>')));
    expect(result.musicXml, startsWith('<?xml'));
    expect(() => result.selectedPartIds.add('x'), throwsUnsupportedError);
  });

  test('自然小节边界的拍号变化不警告且各声部边界可解析', () {
    final bass = _track(0, '低音提琴', 0, [_note(43, 0, 0, 960)]);
    final drums = _track(1, 'Drums', 9, [_note(36, 9, 1920, 2160)]);
    final mystery = _track(2, '???', 2, [_note(72, 2, 2400, 2720)]);
    final parts = [
      _partForTrack(bass, MidiPartKind.strings),
      _partForTrack(
        drums,
        MidiPartKind.percussion,
        staffMode: MidiStaffMode.percussionStaff,
      ),
      _partForTrack(mystery, MidiPartKind.other),
    ];
    final song = _song(
      fileName: 'meter-change.mid',
      tracks: [bass, drums, mystery],
      totalTicks: 3360,
      timeSignatures: [
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
        TimeSignatureChange(tick: 1920, numerator: 3, denominator: 4),
      ],
    );
    final catalog = MidiScoreCatalog(
      fingerprint: 'meter',
      parts: parts,
      recommendedPartIds: parts.map((part) => part.id).toSet(),
      recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      song,
      catalog: catalog,
      selectedPartIds: catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<sign>F</sign><line>4</line>'));
    expect(result.musicXml, contains('<sign>percussion</sign>'));
    expect(result.musicXml, contains('<unpitched>'));
    expect(result.musicXml, contains('<beats>3</beats>'));
    expect(result.warnings, contains(MidiNotationWarning.unknownInstrument));
    expect(
      result.warnings,
      isNot(contains(MidiNotationWarning.irregularTimeSignature)),
    );
    expect(_measureCountsByPart(result.musicXml).toSet(), {
      result.measures.length,
    });
    expect(result.musicXml, startsWith('<?xml'));
  });

  test('五路交错重叠明确降级且每个 voice 不重叠、时值守恒', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Dense', 0, [
        _note(60, 0, 0, 1000),
        _note(62, 0, 120, 1120),
        _note(64, 0, 240, 1240),
        _note(65, 0, 360, 1360),
        _note(67, 0, 480, 1480),
        _note(60, 0, 1920, 2920),
        _note(62, 0, 2040, 3040),
        _note(64, 0, 2160, 3160),
        _note(65, 0, 2280, 3280),
        _note(67, 0, 2400, 3400),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 3840,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.warnings, contains(MidiNotationWarning.densePassage));
    for (final audit in _auditMeasures(result.musicXml)) {
      expect(audit.intervalsByVoice.length, lessThanOrEqualTo(4));
      for (final intervals in audit.intervalsByVoice.values) {
        for (var index = 1; index < intervals.length; index++) {
          expect(
            intervals[index].$1,
            greaterThanOrEqualTo(intervals[index - 1].$2),
          );
        }
      }
      expect(audit.durationByVoice.values.toSet(), {1920});
      expect(
        audit.backups,
        List<int>.filled(audit.durationByVoice.length - 1, 1920),
      );
    }
  });

  test('四个 voice 占满小节时第五路只从谱面丢弃并警告', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Full', 0, [
        _note(60, 0, 0, 2500),
        _note(62, 0, 120, 2500),
        _note(64, 0, 240, 2500),
        _note(65, 0, 360, 2500),
        _note(67, 0, 960, 1200),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.warnings, contains(MidiNotationWarning.densePassage));
    expect(result.musicXml, isNot(contains('<step>G</step>')));
    expect(fixture.song.tracks.single.notes, hasLength(5));
    final audit = _auditFirstMeasure(result.musicXml);
    expect(audit.durationByVoice.values.toSet(), {1920});
  });

  test('第五路跨小节被 relocate 后成对清除 bar tie 并保留小节内 tie', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Relocated bar tie', 0, [
        _note(55, 0, 0, 1440),
        _note(57, 0, 120, 1560),
        _note(59, 0, 240, 1680),
        _note(61, 0, 360, 1800),
        _note(72, 0, 480, 2400),
        _note(74, 0, 2880, 3660),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 3840,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final notesByMeasure = _pitchedNotesByMeasure(result.musicXml);
    final relocated = notesByMeasure
        .map((notes) => _notesAtPitch(notes, step: 'C', octave: 5))
        .toList(growable: false);
    expect(relocated[0], hasLength(1));
    expect(relocated[0].single, contains('<duration>40</duration>'));
    expect(relocated[0].single, isNot(contains('<tie ')));
    expect(relocated[1], hasLength(1));
    expect(relocated[1].single, isNot(contains('<tie ')));

    final internal = _notesAtPitch(notesByMeasure[1], step: 'D', octave: 5);
    expect(internal, hasLength(2));
    expect(internal.first, contains('<tie type="start"/>'));
    expect(internal.last, contains('<tie type="stop"/>'));
    expect(
      result.warnings,
      containsAll({
        MidiNotationWarning.densePassage,
        MidiNotationWarning.rhythmQuantized,
      }),
    );
    _expectMeasureConservation(result.musicXml);
  });

  test('第五路跨小节一侧被 drop 后清除另一侧 orphan bar tie', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Dropped bar tie', 0, [
        _note(55, 0, 0, 1920),
        _note(57, 0, 120, 1920),
        _note(59, 0, 240, 1920),
        _note(61, 0, 360, 1920),
        _note(72, 0, 480, 2400),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 3840,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final notesByMeasure = _pitchedNotesByMeasure(result.musicXml);
    final target = notesByMeasure
        .map((notes) => _notesAtPitch(notes, step: 'C', octave: 5))
        .toList(growable: false);
    expect(target[0], isEmpty);
    expect(target[1], hasLength(1));
    expect(target[1].single, isNot(contains('<tie ')));
    expect(
      result.warnings,
      containsAll({
        MidiNotationWarning.densePassage,
        MidiNotationWarning.rhythmQuantized,
      }),
    );
    _expectMeasureConservation(result.musicXml);
  });

  test('钢琴 voice 首个中间音没有前继 staff 时仍以 middle C 分谱表', () {
    final track = _track(0, 'Piano', 0, [_note(59, 0, 0, 480)]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 1920,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(
      result.musicXml,
      contains(
        '<step>B</step>\n'
        '          <octave>3</octave>\n'
        '        </pitch>\n'
        '        <duration>480</duration>\n'
        '        <voice>1</voice>\n'
        '        <type>quarter</type>\n'
        '        <staff>2</staff>',
      ),
    );
  });

  test('钢琴同 onset 音符先合成和弦再按平均音高分 staff', () {
    final track = _track(0, 'Piano', 0, [
      _note(59, 0, 0, 480),
      _note(61, 0, 0, 480),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 1920,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<chord/>'));
    expect(RegExp(r'<voice>1</voice>').allMatches(result.musicXml).length, 3);
    expect(RegExp(r'<staff>1</staff>').allMatches(result.musicXml).length, 3);
    expect(result.musicXml, isNot(contains('<backup>')));
  });

  test('钢琴同 onset 和弦明显跨越中央 C 时按音高拆分至双谱表', () {
    final track = _track(0, 'Piano', 0, [
      _note(54, 0, 0, 2400),
      _note(66, 0, 0, 2400),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 3840,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final firstMeasureNotes = _pitchedNotesByMeasure(result.musicXml).first;
    expect(
      _notesAtPitch(firstMeasureNotes, step: 'F', octave: 3).single,
      allOf(
        contains('<duration>1920</duration>'),
        contains('<tie type="start"/>'),
        contains('<staff>2</staff>'),
      ),
    );
    expect(
      _notesAtPitch(firstMeasureNotes, step: 'F', octave: 4).single,
      allOf(
        contains('<duration>1920</duration>'),
        contains('<tie type="start"/>'),
        contains('<staff>1</staff>'),
      ),
    );
    expect(result.musicXml, startsWith('<?xml'));
  });

  test('跨谱表和弦上下音时值不同时仍只占一个 voice 且小节守恒', () {
    final track = _track(0, 'Piano', 0, [
      _note(54, 0, 0, 960),
      _note(66, 0, 0, 480),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 1920,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<chord/>'));
    final firstMeasureNotes = _pitchedNotesByMeasure(result.musicXml).first;
    final lowerNotes = _notesAtPitch(firstMeasureNotes, step: 'F', octave: 3);
    final upperNotes = _notesAtPitch(firstMeasureNotes, step: 'F', octave: 4);
    expect(lowerNotes, everyElement(contains('<staff>2</staff>')));
    expect(upperNotes, everyElement(contains('<staff>1</staff>')));
    expect(_totalNoteDuration(lowerNotes), 960);
    expect(_totalNoteDuration(upperNotes), 480);
    expect(_auditFirstMeasure(result.musicXml).durationByVoice, {1: 1920});
  });

  test('跨谱表和弦的多记谱片段在单 voice 内单调输出', () {
    final track = _track(0, 'Piano', 0, [
      _note(48, 0, 0, 600),
      _note(72, 0, 0, 400),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 1920,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<chord/>'));
    final firstMeasureNotes = _pitchedNotesByMeasure(result.musicXml).first;
    final lowerNotes = _notesAtPitch(firstMeasureNotes, step: 'C', octave: 3);
    expect(lowerNotes, hasLength(greaterThan(2)));
    expect(lowerNotes.first, contains('<tie type="start"/>'));
    expect(lowerNotes.first, isNot(contains('<tie type="stop"/>')));
    for (final note in lowerNotes.skip(1).take(lowerNotes.length - 2)) {
      expect(note, contains('<tie type="stop"/>'));
      expect(note, contains('<tie type="start"/>'));
    }
    expect(lowerNotes.last, contains('<tie type="stop"/>'));
    expect(lowerNotes.last, isNot(contains('<tie type="start"/>')));
    final audit = _auditFirstMeasure(result.musicXml);
    expect(audit.backups, isEmpty);
    expect(audit.forwards, isEmpty);
    for (final intervals in audit.intervalsByVoice.values) {
      for (var index = 1; index < intervals.length; index++) {
        expect(
          intervals[index].$1,
          greaterThanOrEqualTo(intervals[index - 1].$2),
        );
      }
    }
    expect(audit.durationByVoice, {1: 1920});
  });

  test('上一小节高音后宽和弦的 B3 不被 staff 历史覆盖', () {
    final track = _track(0, 'Piano', 0, [
      _note(72, 0, 1440, 1920),
      _note(59, 0, 1920, 2400),
      _note(60, 0, 1920, 2400),
      _note(71, 0, 1920, 2400),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 3840,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final secondMeasureNotes = _pitchedNotesByMeasure(result.musicXml)[1];
    expect(
      _notesAtPitch(secondMeasureNotes, step: 'B', octave: 3).single,
      contains('<staff>2</staff>'),
    );
    expect(_auditMeasures(result.musicXml)[1].durationByVoice, {1: 1920});
  });

  test('跨小节 tie 的中央 C 在宽和弦拆分后保持同一 staff', () {
    final track = _track(0, 'Piano', 0, [
      _note(48, 0, 1440, 1920),
      _note(60, 0, 1440, 2400),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 3840,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final notesByMeasure = _pitchedNotesByMeasure(result.musicXml);
    final tieStart = _notesAtPitch(
      notesByMeasure[0],
      step: 'C',
      octave: 4,
    ).single;
    final tieStop = _notesAtPitch(
      notesByMeasure[1],
      step: 'C',
      octave: 4,
    ).single;
    expect(tieStart, contains('<tie type="start"/>'));
    expect(tieStart, contains('<staff>1</staff>'));
    expect(tieStop, contains('<tie type="stop"/>'));
    expect(tieStop, contains('<staff>1</staff>'));
  });

  test('tie map 覆盖聚合 staff 后中央音沿用实际谱表', () {
    final track = _track(0, 'Piano', 0, [
      _note(48, 0, 0, 1920),
      _note(60, 0, 1440, 2400),
      _note(62, 0, 2400, 2880),
    ]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.piano,
      totalTicks: 3840,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final secondMeasureNotes = _pitchedNotesByMeasure(result.musicXml)[1];
    final tieStop = _notesAtPitch(
      secondMeasureNotes,
      step: 'C',
      octave: 4,
    ).single;
    final followingMiddleNote = _notesAtPitch(
      secondMeasureNotes,
      step: 'D',
      octave: 4,
    ).single;
    expect(tieStop, contains('<tie type="stop"/>'));
    expect(tieStop, contains('<staff>1</staff>'));
    expect(followingMiddleNote, contains('<staff>1</staff>'));
  });

  test('小节尾不足最短时值的普通音符不会让转换崩溃', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Tail', 0, [_note(71, 0, 1900, 1910)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.warnings, contains(MidiNotationWarning.rhythmQuantized));
    expect(result.musicXml, startsWith('<?xml'));
  });

  test('拍号变化切出小于 1/32 的短小节时仍保持边界可解析', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Irregular', 0, [_note(71, 0, 0, 10)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
      timeSignatures: [
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
        TimeSignatureChange(tick: 20, numerator: 4, denominator: 4),
      ],
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.measures.first.endTick, 20);
    expect(
      result.warnings,
      contains(MidiNotationWarning.irregularTimeSignature),
    );
    expect(result.musicXml, startsWith('<?xml'));
  });

  test('同 onset 不同时值的和弦音按公共区间保持各自总时值', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Split durations', 0, [
        _note(60, 0, 0, 720),
        _note(64, 0, 0, 320),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<chord/>'));
    final notes = _pitchedNotesByMeasure(result.musicXml).first;
    final longerNotes = _notesAtPitch(notes, step: 'C', octave: 4);
    final shorterNotes = _notesAtPitch(notes, step: 'E', octave: 4);
    expect(_totalNoteDuration(longerNotes), 720);
    expect(_totalNoteDuration(shorterNotes), 320);
    for (final note in [...longerNotes, ...shorterNotes]) {
      final duration = int.parse(
        RegExp(r'<duration>(\d+)</duration>').firstMatch(note)!.group(1)!,
      );
      expect(_notatedDurationTicks(note, ticksPerBeat: 480), duration);
    }
    expect(_auditFirstMeasure(result.musicXml).durationByVoice.values, [1920]);
  });

  test('公共端点差不可记谱时受控量化且输出稳定', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Short chord', 0, [
        _note(60, 0, 0, 40),
        _note(64, 0, 0, 60),
      ]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );
    final converter = MidiToMusicXmlConverter();

    final first = converter.convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );
    final second = converter.convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(first.musicXml, second.musicXml);
    expect(first.warnings, contains(MidiNotationWarning.rhythmQuantized));
    expect(first.musicXml, contains('<chord/>'));
    final pitchedNotes = _pitchedNotesByMeasure(first.musicXml).first;
    expect(
      _totalNoteDuration(_notesAtPitch(pitchedNotes, step: 'C', octave: 4)),
      40,
    );
    expect(
      _totalNoteDuration(_notesAtPitch(pitchedNotes, step: 'E', octave: 4)),
      40,
    );
    final audit = _auditFirstMeasure(first.musicXml);
    expect(audit.backups, isEmpty);
    expect(audit.forwards, isEmpty);
    expect(audit.durationByVoice, {1: 1920});
    expect(first.musicXml, startsWith('<?xml'));
  });

  test('钢琴中间音在跨小节相邻和弦中沿用前一 staff', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Piano', 0, [
        _note(55, 0, 1440, 1920),
        _note(61, 0, 1920, 2400),
      ]),
      kind: MidiPartKind.piano,
      totalTicks: 3840,
      staffMode: MidiStaffMode.grandStaff,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final cSharp = RegExp(
      r'<note>\s*<pitch>\s*<step>C</step>\s*<alter>1</alter>'
      r'[\s\S]*?</pitch>[\s\S]*?<staff>(\d+)</staff>',
    ).firstMatch(result.musicXml);
    expect(cSharp?.group(1), '2');
  });

  test('小节中途 tempo 变化以 offset 保留在 MusicXML 中', () {
    final track = _track(0, 'Tempo', 0, [_note(60, 0, 0, 1920)]);
    final fixture = _singlePartFixture(
      track: track,
      kind: MidiPartKind.strings,
      totalTicks: 1920,
      tempoChanges: [
        TempoChange(tick: 0, microsecondsPerBeat: 500000),
        TempoChange(tick: 960, microsecondsPerBeat: 400000),
      ],
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    expect(result.musicXml, contains('<sound tempo="120"/>'));
    expect(result.musicXml, contains('<offset>960</offset>'));
    expect(result.musicXml, contains('<sound tempo="150"/>'));
  });

  test('跨小节片段分解后 duration 与记谱类型一致', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Long tie', 0, [_note(60, 0, 120, 2620)]),
      kind: MidiPartKind.strings,
      totalTicks: 3840,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final tiedNotes = RegExp(r'<note>([\s\S]*?)</note>')
        .allMatches(result.musicXml)
        .map((match) => match.group(1)!)
        .where(
          (note) => note.contains('<tie type=') && !note.contains('<rest/>'),
        )
        .toList();
    expect(tiedNotes.length, greaterThan(2));
    for (final note in tiedNotes) {
      final duration = int.parse(
        RegExp(r'<duration>(\d+)</duration>').firstMatch(note)!.group(1)!,
      );
      expect(duration, _notatedDurationTicks(note, ticksPerBeat: 480));
    }
    expect(
      result.warnings,
      isNot(contains(MidiNotationWarning.rhythmQuantized)),
    );
    expect(
      _auditMeasures(
        result.musicXml,
      ).map((audit) => audit.durationByVoice.values.toSet()),
      everyElement({1920}),
    );
  });

  test('超过生成小节安全上限时快速拒绝', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Extreme', 0, [_note(60, 0, 0, 480)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920 * 10001,
    );

    expect(
      () => MidiToMusicXmlConverter().convertSync(
        fixture.song,
        catalog: fixture.catalog,
        selectedPartIds: fixture.catalog.recommendedPartIds,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('小节超过'),
        ),
      ),
    );
  });

  test('构建期间超过可注入的 MusicXML 移动端安全上限时快速拒绝', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Small', 0, [_note(60, 0, 0, 480)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
    );

    expect(
      () => MidiToMusicXmlConverter(maxMusicXmlBytes: 128).convertSync(
        fixture.song,
        catalog: fixture.catalog,
        selectedPartIds: fixture.catalog.recommendedPartIds,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('MusicXML 输出超过 128 字节'),
        ),
      ),
    );
  });

  test('最终 MusicXML 以 UTF-8 字节数校验移动端安全上限', () {
    final fixture = _singlePartFixture(
      track: _track(0, '中文钢琴', 0, [_note(60, 0, 0, 480)]),
      kind: MidiPartKind.piano,
      totalTicks: 1920,
    );
    final baseline = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );
    final characterLength = baseline.musicXml.length;
    expect(utf8.encode(baseline.musicXml).length, greaterThan(characterLength));

    expect(
      () => MidiToMusicXmlConverter(maxMusicXmlBytes: characterLength)
          .convertSync(
            fixture.song,
            catalog: fixture.catalog,
            selectedPartIds: fixture.catalog.recommendedPartIds,
          ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('MusicXML 输出超过 $characterLength 字节'),
        ),
      ),
    );
  });

  test('不规则边界两侧实际输出有 gap 时不跨小节 tie', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Gap tie', 0, [_note(60, 0, 0, 200)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
      timeSignatures: [
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
        TimeSignatureChange(tick: 101, numerator: 4, denominator: 4),
      ],
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final notesByMeasure = _pitchedNotesByMeasure(result.musicXml);
    expect(notesByMeasure[0].last, isNot(contains('<tie type="start"/>')));
    expect(notesByMeasure[1].first, isNot(contains('<tie type="stop"/>')));
    expect(result.warnings, contains(MidiNotationWarning.rhythmQuantized));
  });

  test('完全跳过中间片段时不连接非相邻小节', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Skipped fragment', 0, [_note(60, 0, 0, 220)]),
      kind: MidiPartKind.strings,
      totalTicks: 1920,
      timeSignatures: [
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
        TimeSignatureChange(tick: 120, numerator: 4, denominator: 4),
        TimeSignatureChange(tick: 140, numerator: 4, denominator: 4),
      ],
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );

    final notesByMeasure = _pitchedNotesByMeasure(result.musicXml);
    expect(notesByMeasure[0].last, isNot(contains('<tie type="start"/>')));
    expect(notesByMeasure[1], isEmpty);
    expect(notesByMeasure[2].first, isNot(contains('<tie type="stop"/>')));
    expect(result.warnings, contains(MidiNotationWarning.rhythmQuantized));
  });

  test('等误差时按元素数与 complexity 选普通 32nd', () {
    final fixture = _singlePartFixture(
      track: _track(0, 'Tie break', 0, [_note(60, 0, 0, 20)]),
      kind: MidiPartKind.strings,
      totalTicks: 768,
      ticksPerBeat: 192,
    );

    final result = MidiToMusicXmlConverter().convertSync(
      fixture.song,
      catalog: fixture.catalog,
      selectedPartIds: fixture.catalog.recommendedPartIds,
    );
    final note = _pitchedNotesByMeasure(result.musicXml).first.single;

    expect(note, contains('<duration>24</duration>'));
    expect(note, contains('<type>32nd</type>'));
    expect(note, isNot(contains('<time-modification>')));
  });

  test('多个不同 duration 的 DP cache miss 共享累计状态上限', () {
    final fixture = _singlePartFixture(
      track: _track(
        0,
        'DP budget',
        0,
        List<MidiNote>.generate(
          120,
          (index) => _note(60 + index % 12, 0, 0, 10000 + index * 5),
        ),
      ),
      kind: MidiPartKind.strings,
      totalTicks: 20000,
      timeSignatures: [
        TimeSignatureChange(tick: 0, numerator: 100, denominator: 4),
      ],
    );

    expect(
      () => MidiToMusicXmlConverter().convertSync(
        fixture.song,
        catalog: fixture.catalog,
        selectedPartIds: fixture.catalog.recommendedPartIds,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('时值分解累计状态'),
        ),
      ),
    );
  });
}

({MidiSongData song, MidiScoreCatalog catalog}) _pianoFixture() {
  final upper = _track(0, 'Piano Upper', 0, [
    _note(60, 0, 480, 960),
    _note(64, 0, 480, 960),
    _note(67, 0, 1800, 2100),
  ]);
  final lower = _track(1, 'Piano Lower', 1, [_note(48, 1, 0, 960)]);
  final song = _song(
    fileName: 'Piano & Friends.mid',
    tracks: [upper, lower],
    totalTicks: 3840,
  );
  final part = MidiScorePart(
    id: 'piano:0:0,1:1',
    label: 'Grand Piano',
    kind: MidiPartKind.piano,
    sources: [
      MidiPartSource(trackIndex: 0, channels: {0}),
      MidiPartSource(trackIndex: 1, channels: {1}),
    ],
    noteCount: 4,
    staffMode: MidiStaffMode.grandStaff,
  );
  return (
    song: song,
    catalog: MidiScoreCatalog(
      fingerprint: 'piano',
      parts: [part],
      recommendedPartIds: {part.id},
      recommendedOrigin: MidiSelectionOrigin.automaticPiano,
    ),
  );
}

MidiSongData _song({
  required String fileName,
  required List<MidiTrackInfo> tracks,
  required int totalTicks,
  List<TempoChange>? tempoChanges,
  List<TimeSignatureChange>? timeSignatures,
  int ticksPerBeat = 480,
}) => MidiSongData(
  fileName: fileName,
  format: 1,
  ticksPerBeat: ticksPerBeat,
  tracks: tracks,
  timeline: const [],
  tempoChanges:
      tempoChanges ?? [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
  timeSignatureChanges:
      timeSignatures ??
      [TimeSignatureChange(tick: 0, numerator: 4, denominator: 4)],
  totalTicks: totalTicks,
  totalDuration: totalTicks / (ticksPerBeat * 2),
);

MidiTrackInfo _track(
  int index,
  String name,
  int channel,
  List<MidiNote> notes,
) => MidiTrackInfo(
  index: index,
  name: name,
  channels: {channel},
  programByChannel: {channel: 0},
  notes: notes,
);

MidiNote _note(int noteNumber, int channel, int startTick, int endTick) =>
    MidiNote(
      noteNumber: noteNumber,
      velocity: 96,
      channel: channel,
      startTick: startTick,
      endTick: endTick,
    );

({MidiSongData song, MidiScoreCatalog catalog}) _singlePartFixture({
  required MidiTrackInfo track,
  required MidiPartKind kind,
  required int totalTicks,
  MidiStaffMode staffMode = MidiStaffMode.singleStaff,
  String? label,
  List<TimeSignatureChange>? timeSignatures,
  List<TempoChange>? tempoChanges,
  int ticksPerBeat = 480,
}) {
  final part = MidiScorePart(
    id: 'source:${track.index}:${track.channels.first}',
    label: label ?? track.name,
    kind: kind,
    sources: [
      MidiPartSource(trackIndex: track.index, channels: track.channels),
    ],
    noteCount: track.noteCount,
    staffMode: staffMode,
  );
  return (
    song: _song(
      fileName: 'fixture.mid',
      tracks: [track],
      totalTicks: totalTicks,
      timeSignatures: timeSignatures,
      tempoChanges: tempoChanges,
      ticksPerBeat: ticksPerBeat,
    ),
    catalog: MidiScoreCatalog(
      fingerprint: 'fixture',
      parts: [part],
      recommendedPartIds: {part.id},
      recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
    ),
  );
}

MidiScorePart _partForTrack(
  MidiTrackInfo track,
  MidiPartKind kind, {
  MidiStaffMode staffMode = MidiStaffMode.singleStaff,
}) => MidiScorePart(
  id: 'source:${track.index}:${track.channels.first}',
  label: track.name,
  kind: kind,
  sources: [MidiPartSource(trackIndex: track.index, channels: track.channels)],
  noteCount: track.noteCount,
  staffMode: staffMode,
);

List<int> _measureCountsByPart(String xml) =>
    RegExp(r'<part id="[^"]+">([\s\S]*?)</part>')
        .allMatches(xml)
        .map((match) {
          final body = match.group(1)!;
          return RegExp(r'<measure\b').allMatches(body).length;
        })
        .toList(growable: false);

List<String> _wideSameStaffChords(String xml, {required int maxSemitones}) {
  final issues = <String>[];
  final measures = RegExp(
    r'<measure\b[^>]*number="([^"]+)"[^>]*>([\s\S]*?)</measure>',
  ).allMatches(xml);
  for (final measure in measures) {
    final measureNumber = measure.group(1)!;
    final notes = RegExp(
      r'<note>([\s\S]*?)</note>',
    ).allMatches(measure.group(2)!).map((match) => match.group(1)!).toList();
    var chord = <String>[];

    void inspectChord() {
      final pitchesByStaff = <int, List<int>>{};
      for (final note in chord) {
        final pitch = _midiPitchFromMusicXmlNote(note);
        final staffMatch = RegExp(r'<staff>(\d+)</staff>').firstMatch(note);
        if (pitch == null || staffMatch == null) {
          continue;
        }
        final staff = int.parse(staffMatch.group(1)!);
        pitchesByStaff.putIfAbsent(staff, () => []).add(pitch);
      }
      for (final entry in pitchesByStaff.entries) {
        if (entry.value.length < 2) {
          continue;
        }
        final sorted = List<int>.of(entry.value)..sort();
        final span = sorted.last - sorted.first;
        if (span > maxSemitones) {
          issues.add(
            'measure=$measureNumber staff=${entry.key} '
            'pitches=$sorted span=$span',
          );
        }
      }
    }

    for (final note in notes) {
      if (!note.contains('<chord/>')) {
        inspectChord();
        chord = <String>[note];
      } else {
        chord.add(note);
      }
    }
    inspectChord();
  }
  return issues;
}

int? _midiPitchFromMusicXmlNote(String note) {
  final step = RegExp(r'<step>([A-G])</step>').firstMatch(note)?.group(1);
  final octaveText = RegExp(
    r'<octave>(-?\d+)</octave>',
  ).firstMatch(note)?.group(1);
  if (step == null || octaveText == null) {
    return null;
  }
  final alterText = RegExp(
    r'<alter>(-?\d+)</alter>',
  ).firstMatch(note)?.group(1);
  final pitchClass = switch (step) {
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
    _ => throw StateError('unexpected MusicXML pitch step: $step'),
  };
  return (int.parse(octaveText) + 1) * 12 +
      pitchClass +
      int.parse(alterText ?? '0');
}

_MeasureAudit _auditFirstMeasure(String xml) => _auditMeasures(xml).first;

List<_MeasureAudit> _auditMeasures(String xml) => RegExp(
  r'<measure\b[^>]*>([\s\S]*?)</measure>',
).allMatches(xml).map((match) => _auditMeasureBody(match.group(1)!)).toList();

_MeasureAudit _auditMeasureBody(String measure) {
  final tokens = RegExp(
    r'<note>([\s\S]*?)</note>|<backup>([\s\S]*?)</backup>|<forward>([\s\S]*?)</forward>',
  ).allMatches(measure);
  final intervals = <int, List<(int, int)>>{};
  final totals = <int, int>{};
  final backups = <int>[];
  final forwards = <int>[];
  var cursor = 0;
  for (final token in tokens) {
    final backup = token.group(2);
    if (backup != null) {
      final duration = int.parse(
        RegExp(r'<duration>(\d+)</duration>').firstMatch(backup)!.group(1)!,
      );
      backups.add(duration);
      cursor -= duration;
      continue;
    }
    final forward = token.group(3);
    if (forward != null) {
      final duration = int.parse(
        RegExp(r'<duration>(\d+)</duration>').firstMatch(forward)!.group(1)!,
      );
      forwards.add(duration);
      cursor += duration;
      continue;
    }
    final note = token.group(1)!;
    final duration = int.parse(
      RegExp(r'<duration>(\d+)</duration>').firstMatch(note)!.group(1)!,
    );
    final voice = int.parse(
      RegExp(r'<voice>(\d+)</voice>').firstMatch(note)!.group(1)!,
    );
    if (!note.contains('<chord/>')) {
      totals[voice] = (totals[voice] ?? 0) + duration;
      if (!note.contains('<rest/>')) {
        intervals.putIfAbsent(voice, () => []).add((cursor, cursor + duration));
      }
      cursor += duration;
    }
  }
  return (
    intervalsByVoice: intervals,
    durationByVoice: totals,
    backups: backups,
    forwards: forwards,
  );
}

int _notatedDurationTicks(String note, {required int ticksPerBeat}) {
  final type = RegExp(r'<type>([^<]+)</type>').firstMatch(note)!.group(1)!;
  final base = switch (type) {
    'whole' => ticksPerBeat * 4,
    'half' => ticksPerBeat * 2,
    'quarter' => ticksPerBeat,
    'eighth' => ticksPerBeat ~/ 2,
    '16th' => ticksPerBeat ~/ 4,
    '32nd' => ticksPerBeat ~/ 8,
    _ => throw StateError('未知时值类型: $type'),
  };
  final dots = RegExp(r'<dot/>').allMatches(note).length;
  final dotted = switch (dots) {
    0 => base,
    1 => base * 3 ~/ 2,
    2 => base * 7 ~/ 4,
    _ => throw StateError('不支持的附点数: $dots'),
  };
  return note.contains('<time-modification>') ? dotted * 2 ~/ 3 : dotted;
}

List<List<String>> _pitchedNotesByMeasure(String xml) =>
    RegExp(r'<measure\b[^>]*>([\s\S]*?)</measure>')
        .allMatches(xml)
        .map((measureMatch) {
          return RegExp(r'<note>([\s\S]*?)</note>')
              .allMatches(measureMatch.group(1)!)
              .map((noteMatch) => noteMatch.group(1)!)
              .where((note) => !note.contains('<rest/>'))
              .toList(growable: false);
        })
        .toList(growable: false);

List<String> _notesAtPitch(
  List<String> notes, {
  required String step,
  required int octave,
}) => notes
    .where(
      (note) =>
          note.contains('<step>$step</step>') &&
          note.contains('<octave>$octave</octave>'),
    )
    .toList(growable: false);

int _totalNoteDuration(List<String> notes) => notes.fold<int>(
  0,
  (total, note) =>
      total +
      int.parse(
        RegExp(r'<duration>(\d+)</duration>').firstMatch(note)!.group(1)!,
      ),
);

void _expectMeasureConservation(String xml) {
  for (final audit in _auditMeasures(xml)) {
    expect(audit.durationByVoice.values.toSet(), {1920});
    expect(
      audit.backups,
      List<int>.filled(audit.durationByVoice.length - 1, 1920),
    );
  }
}
