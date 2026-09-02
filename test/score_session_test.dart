import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('仅 MIDI 会话不宣称存在可交互谱面', () {
    final session = ScoreSession.midiOnly(_song());

    expect(session.musicXml, isNull);
    expect(session.mappingStatus, ScoreMappingStatus.unavailable);
    expect(session.hasInteractiveScore, isFalse);
  });

  test('记谱会话防御性复制显示元数据并识别可点击小节', () {
    final partIds = <String>{'piano:0:0'};
    final warnings = <MidiNotationWarning>{MidiNotationWarning.rhythmQuantized};
    final session = ScoreSession(
      songData: _song(),
      musicXml: '<score-partwise/>',
      sourceType: ScoreSourceType.midiNotation,
      measures: const [
        ScoreMeasureBoundary(
          ordinal: 1,
          label: '1',
          startTick: 0,
          endTick: 1920,
        ),
        ScoreMeasureBoundary(
          ordinal: 2,
          label: '2',
          startTick: 1920,
          endTick: 3840,
          isInteractive: false,
        ),
      ],
      mappingStatus: ScoreMappingStatus.partial,
      selectedPartIds: partIds,
      notationWarnings: warnings,
    );
    partIds.clear();
    warnings.clear();

    expect(session.hasInteractiveScore, isTrue);
    expect(session.isMeasureInteractive(1), isTrue);
    expect(session.isMeasureInteractive(2), isFalse);
    expect(session.selectedPartIds, {'piano:0:0'});
    expect(session.notationWarnings, {MidiNotationWarning.rhythmQuantized});
    expect(() => session.selectedPartIds.add('other'), throwsUnsupportedError);
    expect(
      () => session.notationWarnings.add(MidiNotationWarning.densePassage),
      throwsUnsupportedError,
    );
  });
}

MidiSongData _song() => MidiSongData(
  fileName: 'fixture.mid',
  format: 0,
  ticksPerBeat: 480,
  tracks: const [],
  timeline: const [],
  tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
  timeSignatureChanges: [
    TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
  ],
  totalTicks: 0,
  totalDuration: 0,
);
