import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/import/musicxml_parser.dart';
import 'package:midi_music/core/import/score_import_service.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('MusicXML 会话保留原文、真实弱起边界和复杂反复警告', () async {
    final xml = File(
      'test/fixtures/interactive_score.musicxml',
    ).readAsStringSync();
    final result = MusicXmlParser().parseDocumentString(
      xml,
      fileName: 'interactive_score.musicxml',
    );

    expect(result.musicXml, xml);
    expect(result.measures, [
      const ScoreMeasureBoundary(
        ordinal: 1,
        label: '0',
        startTick: 0,
        endTick: 480,
      ),
      const ScoreMeasureBoundary(
        ordinal: 2,
        label: '1',
        startTick: 480,
        endTick: 1920,
      ),
    ]);
    expect(result.warnings, contains(ScoreWarning.complexRepetition));
  });

  test('MIDI 导入产生仅伴奏会话', () async {
    final session = await ScoreImportService().importFile(
      'assets/midi/mozart_k545.mid',
    );
    expect(session.sourceType, ScoreSourceType.midiOnly);
    expect(session.musicXml, isNull);
    expect(session.mappingStatus, ScoreMappingStatus.unavailable);
    expect(session.hasInteractiveScore, isFalse);
  });

  test('backup 不会让下一书写小节退回前一小节', () {
    final result = MusicXmlParser().parseDocumentString(_backupMusicXml);

    expect(result.measures, [
      const ScoreMeasureBoundary(
        ordinal: 1,
        label: '1',
        startTick: 0,
        endTick: 960,
      ),
      const ScoreMeasureBoundary(
        ordinal: 2,
        label: '2',
        startTick: 960,
        endTick: 1440,
      ),
    ]);
  });

  test('多 part 小节起止不一致时仅禁用对应书写小节', () {
    final result = MusicXmlParser().parseDocumentString(
      _inconsistentPartsMusicXml,
    );

    expect(result.mappingStatus, ScoreMappingStatus.partial);
    expect(result.warnings, contains(ScoreWarning.inconsistentPartMeasures));
    expect(result.measures.map((measure) => measure.isInteractive), [
      true,
      false,
    ]);
  });
}

const _backupMusicXml = '''
<score-partwise>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>
      <backup><duration>4</duration></backup>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
    </measure>
    <measure number="2">
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
    </measure>
  </part>
</score-partwise>
''';

const _inconsistentPartsMusicXml = '''
<score-partwise>
  <part-list>
    <score-part id="P1"><part-name>One</part-name></score-part>
    <score-part id="P2"><part-name>Two</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1"><attributes><divisions>1</divisions></attributes><note><rest/><duration>1</duration></note></measure>
    <measure number="2"><note><rest/><duration>1</duration></note></measure>
  </part>
  <part id="P2">
    <measure number="1"><attributes><divisions>1</divisions></attributes><note><rest/><duration>1</duration></note></measure>
    <measure number="2"><note><rest/><duration>2</duration></note></measure>
  </part>
</score-partwise>
''';
