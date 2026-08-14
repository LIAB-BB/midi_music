import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/notation/midi_score_selection.dart';
import 'package:midi_music/models/midi_score_part.dart';

void main() {
  test('曲目默认优先于全局类别且失效 ID 被忽略', () {
    final result = MidiScoreSelectionResolver().resolve(
      _catalog(),
      songDefaultPartIds: {'missing', 'source:2:0'},
      globalDefaultKinds: {MidiPartKind.piano},
    );

    expect(result.partIds, {'source:2:0'});
    expect(result.origin, MidiSelectionOrigin.songDefault);
  });

  test('空曲目默认回退为全局、钢琴、非打击乐、打击乐', () {
    expect(
      MidiScoreSelectionResolver()
          .resolve(_catalog(), globalDefaultKinds: {MidiPartKind.strings})
          .origin,
      MidiSelectionOrigin.globalDefault,
    );
    expect(
      MidiScoreSelectionResolver()
          .resolve(_catalog(), globalDefaultKinds: {})
          .origin,
      MidiSelectionOrigin.automaticPiano,
    );
    expect(
      MidiScoreSelectionResolver()
          .resolve(_ensembleCatalog(), globalDefaultKinds: {})
          .origin,
      MidiSelectionOrigin.automaticEnsemble,
    );
    expect(
      MidiScoreSelectionResolver()
          .resolve(_percussionCatalog(), globalDefaultKinds: {})
          .origin,
      MidiSelectionOrigin.percussionFallback,
    );
  });

  test('选择结果防御复制且只保留有音符的目录 ID', () {
    final defaults = <String>{'source:2:0', 'empty'};
    final result = MidiScoreSelectionResolver().resolve(
      _catalog(),
      songDefaultPartIds: defaults,
      globalDefaultKinds: {},
    );

    defaults.clear();
    expect(result.partIds, {'source:2:0'});
    expect(() => result.partIds.add('other'), throwsUnsupportedError);
  });

  test('没有可记谱音符时抛出明确错误', () {
    final emptyCatalog = MidiScoreCatalog(
      fingerprint: 'empty',
      parts: [_part('empty', MidiPartKind.piano, noteCount: 0)],
      recommendedPartIds: {'empty'},
      recommendedOrigin: MidiSelectionOrigin.automaticPiano,
    );

    expect(
      () => MidiScoreSelectionResolver().resolve(
        emptyCatalog,
        globalDefaultKinds: {},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'MIDI 中没有可记谱音符',
        ),
      ),
    );
  });
}

MidiScoreCatalog _catalog() => MidiScoreCatalog(
  fingerprint: 'fixture',
  parts: [
    _part('piano:0:0', MidiPartKind.piano),
    _part('source:2:0', MidiPartKind.strings),
    _part('empty', MidiPartKind.woodwind, noteCount: 0),
  ],
  recommendedPartIds: {'piano:0:0', 'empty'},
  recommendedOrigin: MidiSelectionOrigin.automaticPiano,
);

MidiScoreCatalog _ensembleCatalog() => MidiScoreCatalog(
  fingerprint: 'ensemble',
  parts: [_part('source:1:1', MidiPartKind.strings)],
  recommendedPartIds: {'source:1:1'},
  recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
);

MidiScoreCatalog _percussionCatalog() => MidiScoreCatalog(
  fingerprint: 'percussion',
  parts: [_part('source:1:9', MidiPartKind.percussion)],
  recommendedPartIds: {'source:1:9'},
  recommendedOrigin: MidiSelectionOrigin.percussionFallback,
);

MidiScorePart _part(String id, MidiPartKind kind, {int noteCount = 1}) =>
    MidiScorePart(
      id: id,
      label: id,
      kind: kind,
      sources: [
        MidiPartSource(trackIndex: 0, channels: {0}),
      ],
      noteCount: noteCount,
      staffMode: MidiStaffMode.singleStaff,
    );
