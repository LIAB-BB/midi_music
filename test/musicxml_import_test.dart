import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/import/musicxml_parser.dart';
import 'package:midi_music/core/import/pdf_omr_client.dart';
import 'package:midi_music/core/import/pdf_to_musicxml_converter.dart';
import 'package:midi_music/core/import/score_import_service.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('MusicXML 转换为播放器可用的 MIDI 数据', () {
    final song = MusicXmlParser().parseString(
      _simpleMusicXml,
      fileName: 'simple.musicxml',
    );

    expect(song.fileName, 'simple.musicxml');
    expect(song.format, 1);
    expect(song.ticksPerBeat, 480);
    expect(song.noteTracks, hasLength(1));
    expect(song.totalTicks, 1920);
    expect(song.totalDuration, closeTo(2.0, 0.0001));
    expect(song.timeSignatureChanges.single.numerator, 4);
    expect(song.timeSignatureChanges.single.denominator, 4);
    expect(song.initialBpm, 120);

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(3));
    expect(notes.map((note) => note.noteNumber), [60, 64, 67]);
    expect(notes.map((note) => note.startTick), [0, 480, 480]);
    expect(notes.map((note) => note.endTick), [480, 960, 960]);

    expect(
      song.timeline.where((event) => event.type == MidiEventType.noteOn),
      hasLength(3),
    );
  });

  test('ScoreImportService 可通过 PDF OMR 接口导入 PDF', () async {
    final pdf = File('${Directory.systemTemp.path}/score_import_test.pdf');
    await pdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    addTearDown(() {
      if (pdf.existsSync()) {
        pdf.deleteSync();
      }
    });

    final service = ScoreImportService(pdfConverter: _FakePdfConverter());
    final song = await service.importFile(pdf.path);

    expect(song.fileName, 'score_import_test.musicxml');
    expect(song.noteTracks.single.notes.first.noteNumber, 60);
  });

  test('HttpPdfToMusicXmlConverter 按任务协议获取 MusicXML', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/v1/omr/jobs') {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write('{"jobId":"job-1"}');
        await request.response.close();
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/v1/omr/jobs/job-1') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'status': 'succeeded', 'musicXml': _simpleMusicXml}),
          );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final pdf = File('${Directory.systemTemp.path}/omr_client_test.pdf');
    await pdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    addTearDown(() {
      if (pdf.existsSync()) {
        pdf.deleteSync();
      }
    });

    final converter = HttpPdfToMusicXmlConverter(
      baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
      pollInterval: Duration.zero,
    );

    expect(await converter.convert(pdf), _simpleMusicXml);
  });

  test('HttpPdfToMusicXmlConverter 将请求超时转为 OMR 业务错误', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });
    server.listen((request) async {
      await request.drain<void>();
      await Future<void>.delayed(const Duration(seconds: 1));
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"jobId":"job-1"}');
      await request.response.close();
    });

    final pdf = File('${Directory.systemTemp.path}/omr_client_timeout.pdf');
    await pdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    addTearDown(() {
      if (pdf.existsSync()) {
        pdf.deleteSync();
      }
    });

    final converter = HttpPdfToMusicXmlConverter(
      baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
      timeout: const Duration(milliseconds: 10),
      pollInterval: Duration.zero,
    );

    await expectLater(
      converter.convert(pdf),
      throwsA(
        isA<OmrServiceException>().having(
          (error) => error.message,
          'message',
          contains('PDF 识谱服务响应超时'),
        ),
      ),
    );
  });

  test('钢琴二重奏 MusicXML 会转换为两个可播放轨道', () {
    final song = MusicXmlParser().parseString(
      _pianoDuoMusicXml,
      fileName: 'duo.musicxml',
    );

    expect(song.noteTracks, hasLength(2));
    expect(song.noteTracks.map((track) => track.name), ['Primo', 'Secondo']);
    expect(song.noteTracks.map((track) => track.channels.single), [0, 1]);
    expect(song.noteTracks.first.notes.single.noteNumber, 72);
    expect(song.noteTracks.last.notes.single.noteNumber, 48);
  });

  test('和弦附加音更长时总时长包含最长音符', () {
    final song = MusicXmlParser().parseString(_longChordMusicXml);

    expect(song.noteTracks.single.notes.map((note) => note.endTick), [
      480,
      960,
    ]);
    expect(song.totalTicks, 960);
    expect(song.totalDuration, closeTo(1.0, 0.0001));
  });

  test('未配置 OMR 时 PDF 导入明确失败', () async {
    final service = ScoreImportService();

    expect(
      service.importFile('/tmp/unconfigured.pdf'),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class _FakePdfConverter implements PdfToMusicXmlConverter {
  @override
  Future<String> convert(File pdfFile) async => _simpleMusicXml;
}

const _simpleMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1">
      <part-name>Piano</part-name>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <time>
          <beats>4</beats>
          <beat-type>4</beat-type>
        </time>
        <clef>
          <sign>G</sign>
          <line>2</line>
        </clef>
      </attributes>
      <direction placement="above">
        <sound tempo="120"/>
      </direction>
      <note>
        <pitch>
          <step>C</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <type>quarter</type>
      </note>
      <note>
        <pitch>
          <step>E</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <type>quarter</type>
      </note>
      <note>
        <chord/>
        <pitch>
          <step>G</step>
          <octave>4</octave>
        </pitch>
        <duration>1</duration>
        <type>quarter</type>
      </note>
      <note>
        <rest/>
        <duration>2</duration>
        <type>half</type>
      </note>
    </measure>
  </part>
</score-partwise>
''';

const _pianoDuoMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Primo</part-name></score-part>
    <score-part id="P2"><part-name>Secondo</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note>
        <pitch><step>C</step><octave>5</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
  <part id="P2">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note>
        <pitch><step>C</step><octave>3</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

const _longChordMusicXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>1</divisions></attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>1</duration>
      </note>
      <note>
        <chord/>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>2</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';
