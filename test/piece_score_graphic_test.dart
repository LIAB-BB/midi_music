import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/notation/piece_score_alignment.dart';
import 'package:midi_music/core/notation/piece_score_graphic.dart';
import 'package:midi_music/core/score/piece_manifest.dart';
import 'package:midi_music/ui/widgets/piece_score_strip.dart';

void main() {
  test('曲目包 MusicXML 可抽出双手谱的小节', () {
    final song = MidiFileParser().parseBytes(
      File('assets/midi/mozart_k478_piano_quartet.mid').readAsBytesSync(),
      fileName: 'mozart_k478_piano_quartet.mid',
    );
    final manifest = PieceManifest.parse(
      File('assets/pieces/k478.json').readAsStringSync(),
    );
    final alignment = PieceScoreAlignment.compile(song, manifest);
    final graphic = PieceScoreGraphic.parse(alignment.musicXml);

    expect(graphic.measures, hasLength(360));
    expect(graphic.measures.first.ordinal, 1);
    expect(graphic.measures.first.lengthDivisions, 1536);
    expect(
      graphic.measures
          .expand((measure) => measure.notes)
          .map((note) => note.staff),
      containsAll([1, 2]),
    );
    expect(
      graphic.measures.first.notes.where((note) => !note.isRest),
      isNotEmpty,
    );
  });

  test('试谱保留音高所在的谱表和小节序号', () {
    final graphic = PieceScoreGraphic.parse(_sampleXml);

    expect(graphic.measures.map((measure) => measure.ordinal), [1, 2]);
    final first = graphic.measures.first.notes;
    expect(first.first.staff, 1);
    expect(first.first.diatonic, 35);
    expect(first.last.isRest, isFalse);
    expect(graphic.measures.last.notes.single.staff, 2);
    expect(graphic.measures.last.notes.single.diatonic, 28);
  });

  testWidgets('点试谱小节会请求跳转', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: PieceScoreStrip(
            musicXml: _sampleXml,
            currentOrdinal: 1,
            onMeasureSelected: selected.add,
          ),
        ),
      ),
    );

    expect(find.textContaining('试排的钢琴谱'), findsOneWidget);
    await tester.tap(find.byKey(const Key('piece-score-measure-2')));
    await tester.pump();

    expect(selected, [2]);
  });
}

const _sampleXml = '''
<score-partwise>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note>
        <pitch><step>C</step><octave>5</octave></pitch>
        <duration>1</duration>
        <staff>1</staff>
      </note>
      <note>
        <chord/>
        <pitch><step>E</step><octave>5</octave></pitch>
        <duration>1</duration>
        <staff>1</staff>
      </note>
    </measure>
    <measure number="2">
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
        <staff>2</staff>
      </note>
    </measure>
  </part>
</score-partwise>
''';
