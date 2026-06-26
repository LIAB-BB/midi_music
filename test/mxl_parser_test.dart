import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score.dart';

void main() {
  test('MxlScoreParser 从 container rootfile 解析 MusicXML', () {
    final bytes = _mxlBytes({
      'META-INF/container.xml': _containerXml('scores/main.musicxml'),
      'scores/main.musicxml': _sampleMusicXml,
    });

    final document = const MxlScoreParser().parse(
      bytes,
      sourceId: 'mxl-sample',
      path: '/tmp/sample.mxl',
    );

    expect(document.id, 'mxl-sample');
    expect(document.title, 'MXL Test');
    expect(document.parts.single.name, 'Piano');
    expect(
      document.eventsAtAbsoluteBeat(0).whereType<ScoreNote>(),
      hasLength(1),
    );
  });

  test('MxlScoreParser 处理 rootfile full-path XML entity', () {
    final bytes = _mxlBytes({
      'META-INF/container.xml': _containerXml('scores/main&amp;part.musicxml'),
      'scores/main&part.musicxml': _sampleMusicXml,
    });

    final document = const MxlScoreParser().parse(bytes);

    expect(document.title, 'MXL Test');
  });

  test('MxlScoreParser 拒绝缺失 container 的 MXL', () {
    final bytes = _mxlBytes({'score.musicxml': _sampleMusicXml});

    expect(
      () => const MxlScoreParser().parse(bytes),
      throwsA(isA<MxlParseException>()),
    );
  });

  test('MxlScoreParser 拒绝损坏的 zip 内容', () {
    expect(
      () => const MxlScoreParser().parse(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<MxlParseException>()),
    );
  });

  test('MxlScoreParser 拒绝 rootfile 指向不存在的 MXL', () {
    final bytes = _mxlBytes({
      'META-INF/container.xml': _containerXml('missing.musicxml'),
      'score.musicxml': _sampleMusicXml,
    });

    expect(
      () => const MxlScoreParser().parse(bytes),
      throwsA(isA<MxlParseException>()),
    );
  });
}

Uint8List _mxlBytes(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

String _containerXml(String rootfilePath) {
  return '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0">
  <rootfiles>
    <rootfile full-path="$rootfilePath" media-type="application/vnd.recordare.musicxml+xml" />
  </rootfiles>
</container>
''';
}

const _sampleMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <movement-title>MXL Test</movement-title>
  <part-list>
    <score-part id="P1">
      <part-name>Piano</part-name>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
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
        <duration>1</duration>
        <voice>1</voice>
      </note>
    </measure>
  </part>
</score-partwise>
''';
