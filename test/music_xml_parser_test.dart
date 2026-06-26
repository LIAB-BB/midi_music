import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score.dart';

void main() {
  test('MusicXmlScoreParser 解析 part、measure、note、rest 和 tie', () {
    final document = MusicXmlScoreParser().parse(
      _sampleMusicXml,
      sourceId: 'sample',
      path: '/tmp/sample.musicxml',
    );

    expect(document.id, 'sample');
    expect(document.title, 'Prelude Test');
    expect(document.parts.single.id, 'P1');
    expect(document.parts.single.name, 'Piano');
    expect(document.measuresForPart('P1'), hasLength(2));

    final firstMeasure = document.measureByNumber('P1', 1)!;
    expect(firstMeasure.durationBeats, 4);
    expect(firstMeasure.voices, hasLength(2));

    final beatZeroEvents = document.eventsAtAbsoluteBeat(0);
    expect(
      beatZeroEvents.whereType<ScoreNote>().map((note) => note.pitch.midiPitch),
      containsAll([60, 64, 67]),
    );

    final rest = document.eventsAtAbsoluteBeat(1).whereType<ScoreRest>().single;
    expect(rest.durationBeats, 1);

    final tiedStart = document
        .eventsAtAbsoluteBeat(2)
        .whereType<ScoreNote>()
        .singleWhere((note) => note.pitch.midiPitch == 67);
    expect(tiedStart.tieStart, isTrue);

    final tiedStop = document
        .eventsAtAbsoluteBeat(4)
        .whereType<ScoreNote>()
        .singleWhere((note) => note.pitch.midiPitch == 67);
    expect(tiedStop.tieStop, isTrue);
  });

  test('MusicXmlScoreParser 展开的 PerformanceTimeline 保留连音语义', () {
    final document = MusicXmlScoreParser().parse(_sampleMusicXml);

    final timeline = document.toPerformanceTimeline(secondsPerBeat: 0.5);
    final tiedEvents = timeline.events
        .where(
          (event) =>
              event.scoreEventId == 'P1:m1:n3' ||
              event.scoreEventId == 'P1:m2:n1',
        )
        .map((event) => event.type)
        .toList();

    expect(tiedEvents, [
      PerformanceEventType.noteOn,
      PerformanceEventType.noteOff,
    ]);
    expect(timeline.events.last.position.measureNumber, 2);
  });

  test('MusicXmlScoreParser 拒绝非 score-partwise XML', () {
    expect(
      () => MusicXmlScoreParser().parse('<score-timewise />'),
      throwsA(isA<MusicXmlParseException>()),
    );
  });
}

const _sampleMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC
  "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise version="4.0">
  <movement-title>Prelude Test</movement-title>
  <part-list>
    <score-part id="P1">
      <part-name>Piano</part-name>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <time>
          <beats>4</beats>
          <beat-type>4</beat-type>
        </time>
      </attributes>
      <note>
        <pitch>
          <step>C</step>
          <octave>4</octave>
        </pitch>
        <duration>2</duration>
        <voice>1</voice>
      </note>
      <note>
        <rest />
        <duration>2</duration>
        <voice>1</voice>
      </note>
      <note>
        <pitch>
          <step>G</step>
          <octave>4</octave>
        </pitch>
        <duration>4</duration>
        <voice>1</voice>
        <tie type="start" />
      </note>
      <backup>
        <duration>8</duration>
      </backup>
      <note>
        <pitch>
          <step>E</step>
          <octave>4</octave>
        </pitch>
        <duration>4</duration>
        <voice>2</voice>
      </note>
      <note>
        <chord />
        <pitch>
          <step>G</step>
          <octave>4</octave>
        </pitch>
        <duration>4</duration>
        <voice>2</voice>
      </note>
    </measure>
    <measure number="2">
      <note>
        <pitch>
          <step>G</step>
          <octave>4</octave>
        </pitch>
        <duration>2</duration>
        <voice>1</voice>
        <tie type="stop" />
      </note>
      <note>
        <grace />
        <pitch>
          <step>D</step>
          <octave>4</octave>
        </pitch>
        <voice>1</voice>
      </note>
    </measure>
  </part>
</score-partwise>
''';
