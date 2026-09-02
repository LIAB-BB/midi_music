import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/midi_part_analyzer.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('名为 Piano 的单轨多 channel 仍按 channel 和 GM program 分源', () {
    final song = _songWithTracks([
      _track(
        0,
        name: 'Piano',
        notes: [_note(0, 60), _note(1, 67), _note(9, 36)],
        programs: const {0: 0, 1: 40, 9: 0},
      ),
    ]);

    final parts = MidiPartAnalyzer()
        .analyze(song, fingerprint: 'fixture')
        .parts;

    expect(
      {
        for (final part in parts)
          for (final source in part.sources) source.channels.single: part.kind,
      },
      {
        0: MidiPartKind.piano,
        1: MidiPartKind.strings,
        9: MidiPartKind.percussion,
      },
    );
  });

  test('多个钢琴轨道合并为稳定的钢琴双谱表', () {
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
    expect(piano.staffMode, MidiStaffMode.grandStaff);
    expect(piano.sources.length, greaterThan(1));
    expect(
      piano.id,
      'piano:${piano.sources.map((source) => '${source.trackIndex}:${source.channels.single}').join(',')}',
    );
    expect(catalog.recommendedPartIds, {piano.id});
  });

  test('乱序钢琴轨道仍生成固定排序的稳定 ID', () {
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(8, name: 'Piano', notes: [_note(3, 72)], programs: const {3: 0}),
        _track(2, name: 'upper', notes: [_note(5, 48)], programs: const {5: 0}),
      ]),
      fingerprint: 'unordered-piano',
    );

    expect(catalog.parts.single.id, 'piano:2:5,8:3');
  });

  test('模型对构造时输入的集合进行防御性复制', () {
    final channels = <int>{0};
    final sources = <MidiPartSource>[
      MidiPartSource(trackIndex: 1, channels: channels),
    ];
    final recommendedIds = <String>{'piano:1:0'};
    final part = MidiScorePart(
      id: 'piano:1:0',
      label: '钢琴',
      kind: MidiPartKind.piano,
      sources: sources,
      noteCount: 1,
      staffMode: MidiStaffMode.singleStaff,
    );
    final catalog = MidiScoreCatalog(
      fingerprint: 'fixture',
      parts: [part],
      recommendedPartIds: recommendedIds,
      recommendedOrigin: MidiSelectionOrigin.songDefault,
    );

    channels.add(1);
    sources.clear();
    recommendedIds.add('source:2:2');

    expect(part.sources.single.channels, {0});
    expect(catalog.parts, [part]);
    expect(catalog.recommendedPartIds, {'piano:1:0'});
    expect(() => catalog.parts.add(part), throwsUnsupportedError);
    expect(
      () => catalog.recommendedPartIds.add('other'),
      throwsUnsupportedError,
    );
  });

  test('单 channel 明确轨道名优先于 GM program，并稳定去重标签', () {
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(
          0,
          name: 'Flute',
          notes: [_note(2, 72)],
          programs: const {2: 40},
        ),
        _track(
          1,
          name: 'Flute',
          notes: [_note(3, 74)],
          programs: const {3: 40},
        ),
      ]),
      fingerprint: 'fixture',
    );

    expect(catalog.parts.map((part) => part.kind), [
      MidiPartKind.woodwind,
      MidiPartKind.woodwind,
    ]);
    expect(catalog.parts.map((part) => part.label), ['Flute', 'Flute（2）']);
    expect(catalog.recommendedPartIds, {'source:0:2', 'source:1:3'});
    expect(catalog.recommendedOrigin, MidiSelectionOrigin.automaticEnsemble);
  });

  test('音符起点前最后一个 program change 决定分类，再回退 programByChannel', () {
    final programEvents = [
      TimelineEvent(
        type: MidiEventType.programChange,
        tick: 0,
        trackIndex: 0,
        channel: 1,
        data1: 40,
      ),
      TimelineEvent(
        type: MidiEventType.programChange,
        tick: 80,
        trackIndex: 0,
        channel: 1,
        data1: 56,
      ),
      TimelineEvent(
        type: MidiEventType.programChange,
        tick: 200,
        trackIndex: 0,
        channel: 1,
        data1: 0,
      ),
    ];
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(
          0,
          notes: [_note(1, 60, startTick: 100)],
          programs: const {1: 24},
          events: programEvents,
        ),
        _track(1, notes: [_note(2, 48)], programs: const {2: 32}),
        _track(2, notes: [_note(3, 60)], programs: const {3: 52}),
      ]),
      fingerprint: 'fixture',
    );

    expect(catalog.parts.map((part) => part.kind), [
      MidiPartKind.brass,
      MidiPartKind.bass,
      MidiPartKind.voice,
    ]);
  });

  test('无钢琴时选全部非打击乐，仅有打击乐时回退为打击乐', () {
    final ensemble = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(0, notes: [_note(1, 60)], programs: const {1: 40}),
        _track(1, notes: [_note(9, 36)], programs: const {9: 0}),
      ]),
      fingerprint: 'ensemble',
    );
    final percussionOnly = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(0, notes: [_note(9, 36)], programs: const {9: 0}),
      ]),
      fingerprint: 'percussion',
    );

    expect(ensemble.recommendedPartIds, {'source:0:1'});
    expect(ensemble.recommendedOrigin, MidiSelectionOrigin.automaticEnsemble);
    expect(percussionOnly.recommendedPartIds, {'source:0:9'});
    expect(
      percussionOnly.recommendedOrigin,
      MidiSelectionOrigin.percussionFallback,
    );
  });

  test('空名打击乐 channel 不使用旋律 GM program 作为标签', () {
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(0, notes: [_note(9, 36)], programs: const {9: 0}),
      ]),
      fingerprint: 'unnamed-percussion',
    );

    final percussion = catalog.parts.single;
    expect(percussion.kind, MidiPartKind.percussion);
    expect(percussion.label, '打击乐');
  });

  test('upper、lower 和中英文左右手单声道轨道识别为钢琴', () {
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(
          0,
          name: 'upper',
          notes: [_note(1, 72)],
          programs: const {1: 40},
        ),
        _track(
          1,
          name: 'lower',
          notes: [_note(2, 48)],
          programs: const {2: 40},
        ),
        _track(
          3,
          name: 'Right Hand',
          notes: [_note(3, 76)],
          programs: const {3: 40},
        ),
        _track(4, name: '左手', notes: [_note(4, 43)], programs: const {4: 40}),
      ]),
      fingerprint: 'piano-hands',
    );

    final piano = catalog.parts.single;
    expect(piano.kind, MidiPartKind.piano);
    expect(piano.sources.map((source) => source.trackIndex), [0, 1, 3, 4]);
  });

  test('非钢琴标签依次使用具体轨道名、GM 具体名和类别', () {
    final catalog = MidiPartAnalyzer().analyze(
      _songWithTracks([
        _track(
          0,
          name: 'Violin I',
          notes: [_note(1, 72)],
          programs: const {1: 40},
        ),
        _track(1, notes: [_note(2, 74)], programs: const {2: 40}),
        _track(2, notes: [_note(3, 76)], programs: const {3: 48}),
      ]),
      fingerprint: 'labels',
    );

    expect(catalog.parts.map((part) => part.label), [
      'Violin I',
      '小提琴',
      '弦乐合奏1',
    ]);
  });

  test('分析前拒绝超过 64 个有音符轨道', () {
    final tracks = List<MidiTrackInfo>.generate(
      65,
      (index) => _track(index, notes: [_note(index % 16, 60)]),
    );

    expect(
      () => MidiPartAnalyzer().analyze(
        _songWithTracks(tracks),
        fingerprint: 'too-many-tracks',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('64'),
        ),
      ),
    );
  });

  test('分析前拒绝超过 500000 个音符', () {
    final note = _note(1, 60);
    final song = _songWithTracks([
      _track(0, notes: List<MidiNote>.filled(500001, note)),
    ]);

    expect(
      () => MidiPartAnalyzer().analyze(song, fingerprint: 'too-many-notes'),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('500000'),
        ),
      ),
    );
  });
}

MidiSongData _songWithTracks(List<MidiTrackInfo> tracks) => MidiSongData(
  fileName: 'fixture.mid',
  format: 1,
  ticksPerBeat: 480,
  tracks: tracks,
  timeline: const [],
  tempoChanges: const [],
  timeSignatureChanges: const [],
  totalTicks: 480,
  totalDuration: 0.5,
);

MidiTrackInfo _track(
  int index, {
  String name = '',
  required List<MidiNote> notes,
  Map<int, int> programs = const {},
  List<TimelineEvent> events = const [],
}) => MidiTrackInfo(
  index: index,
  name: name,
  channels: notes.map((note) => note.channel).toSet(),
  programByChannel: programs,
  notes: notes,
  events: events,
);

MidiNote _note(int channel, int number, {int startTick = 0}) => MidiNote(
  noteNumber: number,
  velocity: 80,
  channel: channel,
  startTick: startTick,
  endTick: startTick + 120,
);
