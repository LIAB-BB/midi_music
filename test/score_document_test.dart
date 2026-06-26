import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score.dart';

void main() {
  test('ScoreDocument 支持按 part、measure 和 absolute beat 查询', () {
    final document = _scoreDocument();

    expect(document.partById('violin')?.name, 'Violin');
    expect(document.measuresForPart('violin'), hasLength(1));
    expect(document.measureByNumber('violin', 1)?.durationBeats, 4);

    final events = document.eventsAtAbsoluteBeat(0);

    expect(events.whereType<ScoreNote>(), hasLength(2));
    expect(events.map((event) => event.id), containsAll(['n1', 'n2']));
  });

  test('ScoreDocument 可以展开为独立 PerformanceTimeline', () {
    final document = _scoreDocument();

    final timeline = document.toPerformanceTimeline(secondsPerBeat: 0.5);

    expect(timeline.events, hasLength(5));
    expect(timeline.eventsAtBeat(0), hasLength(2));
    expect(timeline.eventsAtBeat(1).map((event) => event.type), [
      PerformanceEventType.noteOff,
      PerformanceEventType.noteOff,
      PerformanceEventType.rest,
    ]);
    expect(
      timeline.events
          .where((event) => event.type == PerformanceEventType.noteOn)
          .map((event) => event.scoreEventId),
      ['n1', 'n2'],
    );
    final noteOff = timeline.events.firstWhere((event) => event.id == 'n1:off');
    expect(noteOff.position.measureNumber, 1);
    expect(noteOff.position.beat, 2);
  });

  test('PerformanceTimeline 处理连音并默认跳过装饰音', () {
    final document = _tiedScoreDocument();

    final timeline = document.toPerformanceTimeline(secondsPerBeat: 0.5);

    expect(timeline.events.map((event) => event.id), ['t1:on', 't2:off']);
    expect(timeline.events.last.position.measureNumber, 2);
    expect(timeline.events.last.position.beat, 2);
    expect(timeline.events.last.timeSeconds, 2.5);
  });

  test('PerformanceTimeline 可以显式包含装饰音', () {
    final document = _tiedScoreDocument();

    final timeline = document.toPerformanceTimeline(
      secondsPerBeat: 0.5,
      includeGraceNotes: true,
    );

    expect(
      timeline.events.map((event) => event.id),
      ['g1:on', 'g1:off', 't1:on', 't2:off'],
    );
  });
}

ScoreDocument _scoreDocument() {
  const source = SourceReference(
    sourceId: 'manual-test',
    stableId: 'm1-v1-n1',
    sourceType: 'manual',
  );
  return ScoreDocument(
    id: 'doc-1',
    title: 'Manual Test',
    parts: [
      ScorePart(
        id: 'violin',
        name: 'Violin',
        measures: [
          ScoreMeasure(
            number: 1,
            startBeat: 0,
            durationBeats: 4,
            voices: [
              ScoreVoice(
                id: 'voice-1',
                events: [
                  const ScoreNote(
                    id: 'n1',
                    position: ScorePosition(
                      measureNumber: 1,
                      beat: 1,
                      absoluteBeat: 0,
                    ),
                    durationBeats: 1,
                    pitch: NotatedPitch(
                      step: PitchStep.c,
                      octave: 4,
                      midiPitch: 60,
                    ),
                    source: source,
                  ),
                  const ScoreNote(
                    id: 'n2',
                    position: ScorePosition(
                      measureNumber: 1,
                      beat: 1,
                      absoluteBeat: 0,
                    ),
                    durationBeats: 1,
                    pitch: NotatedPitch(
                      step: PitchStep.e,
                      octave: 4,
                      midiPitch: 64,
                    ),
                  ),
                  const ScoreRest(
                    id: 'r1',
                    position: ScorePosition(
                      measureNumber: 1,
                      beat: 2,
                      absoluteBeat: 1,
                    ),
                    durationBeats: 1,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

ScoreDocument _tiedScoreDocument() {
  return ScoreDocument(
    id: 'doc-2',
    title: 'Tie Test',
    parts: [
      ScorePart(
        id: 'piano',
        name: 'Piano',
        measures: [
          ScoreMeasure(
            number: 1,
            startBeat: 0,
            durationBeats: 4,
            voices: [
              ScoreVoice(
                id: 'voice-1',
                events: const [
                  ScoreNote(
                    id: 'g1',
                    position: ScorePosition(
                      measureNumber: 1,
                      beat: 3,
                      absoluteBeat: 2,
                    ),
                    durationBeats: 0,
                    pitch: NotatedPitch(
                      step: PitchStep.d,
                      octave: 4,
                      midiPitch: 62,
                    ),
                    isGrace: true,
                  ),
                  ScoreNote(
                    id: 't1',
                    position: ScorePosition(
                      measureNumber: 1,
                      beat: 4,
                      absoluteBeat: 3,
                    ),
                    durationBeats: 1,
                    pitch: NotatedPitch(
                      step: PitchStep.g,
                      octave: 4,
                      midiPitch: 67,
                    ),
                    tieStart: true,
                  ),
                ],
              ),
            ],
          ),
          ScoreMeasure(
            number: 2,
            startBeat: 4,
            durationBeats: 4,
            voices: [
              ScoreVoice(
                id: 'voice-1',
                events: const [
                  ScoreNote(
                    id: 't2',
                    position: ScorePosition(
                      measureNumber: 2,
                      beat: 1,
                      absoluteBeat: 4,
                    ),
                    durationBeats: 1,
                    pitch: NotatedPitch(
                      step: PitchStep.g,
                      octave: 4,
                      midiPitch: 67,
                    ),
                    tieStop: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
