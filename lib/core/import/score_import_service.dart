import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import '../midi/midi_parser.dart';
import 'musicxml_parser.dart';
import 'pdf_omr_client.dart';
import 'pdf_to_musicxml_converter.dart';

typedef MidiBytesReader = Future<Uint8List> Function(String filePath);
typedef MidiImportWorkerResult = ({String digest, MidiSongData songData});
typedef MidiImportWorker =
    MidiImportWorkerResult Function(
      MidiFileParser parser,
      Uint8List bytes, {
      required String fileName,
    });

class ScoreImportService {
  final MidiFileParser _midiParser;
  final MidiBytesReader _midiBytesReader;
  final MidiImportWorker _midiImportWorker;
  final MusicXmlParser _musicXmlParser;
  final PdfToMusicXmlConverter? _pdfConverter;

  ScoreImportService({
    MidiFileParser? midiParser,
    MidiBytesReader? midiBytesReader,
    MidiImportWorker? midiImportWorker,
    MusicXmlParser? musicXmlParser,
    PdfToMusicXmlConverter? pdfConverter,
  }) : _midiParser = midiParser ?? MidiFileParser(),
       _midiBytesReader = midiBytesReader ?? _readMidiBytes,
       _midiImportWorker = midiImportWorker ?? _parseAndHashMidi,
       _musicXmlParser = musicXmlParser ?? MusicXmlParser(),
       _pdfConverter =
           pdfConverter ??
           (omrServiceBaseUrlFromEnvironment.isEmpty
               ? null
               : HttpPdfToMusicXmlConverter(
                   baseUrl: Uri.parse(omrServiceBaseUrlFromEnvironment),
                 ));

  Future<ScoreSession> importFile(String filePath) async {
    final extension = _extensionOf(filePath);
    switch (extension) {
      case '.mid':
      case '.midi':
        return _importMidi(filePath);
      case '.xml':
      case '.musicxml':
        final xml = await File(filePath).readAsString();
        return _musicXmlParser
            .parseDocumentString(xml, fileName: _fileName(filePath))
            .toSession(ScoreSourceType.musicXml);
      case '.pdf':
        return _importPdf(filePath);
      default:
        throw UnsupportedError('暂不支持的乐谱格式：$extension');
    }
  }

  Future<ScoreSession> _importMidi(String filePath) async {
    final bytes = await _midiBytesReader(filePath);
    final parser = _midiParser;
    final worker = _midiImportWorker;
    final fileName = _fileName(filePath);
    final result = await Isolate.run(
      () => worker(parser, bytes, fileName: fileName),
      debugName: 'MIDI import parse and SHA-256',
    );
    return ScoreSession.midiOnly(
      result.songData,
      sourceFingerprint: 'midi:sha256:${result.digest}',
    );
  }

  Future<ScoreSession> _importPdf(String filePath) async {
    final converter = _pdfConverter;
    if (converter == null) {
      throw UnsupportedError(
        'PDF 转 MIDI 需要先通过 OMR 识谱生成 MusicXML；'
        '当前尚未配置 PDF 识谱服务。',
      );
    }
    final pdfFile = File(filePath);
    if (!await pdfFile.exists()) {
      throw FileSystemException('PDF file not found', filePath);
    }
    final xml = await converter.convert(pdfFile);
    return _musicXmlParser
        .parseDocumentString(
          xml,
          fileName: '${_basenameWithoutExtension(filePath)}.musicxml',
        )
        .toSession(ScoreSourceType.pdfOmr);
  }

  String _fileName(String filePath) =>
      filePath.split(Platform.pathSeparator).last;

  String _extensionOf(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return '';
    return fileName.substring(dotIndex).toLowerCase();
  }

  String _basenameWithoutExtension(String filePath) {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return fileName;
    return fileName.substring(0, dotIndex);
  }
}

Future<Uint8List> _readMidiBytes(String filePath) =>
    File(filePath).readAsBytes();

MidiImportWorkerResult _parseAndHashMidi(
  MidiFileParser parser,
  Uint8List bytes, {
  required String fileName,
}) => (
  digest: sha256.convert(bytes).toString(),
  songData: parser.parseBytes(bytes, fileName: fileName),
);
