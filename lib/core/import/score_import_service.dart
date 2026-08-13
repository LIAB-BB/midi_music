import 'dart:io';

import '../../models/score_session.dart';
import '../midi/midi_parser.dart';
import 'musicxml_parser.dart';
import 'pdf_omr_client.dart';
import 'pdf_to_musicxml_converter.dart';

class ScoreImportService {
  final MidiFileParser _midiParser;
  final MusicXmlParser _musicXmlParser;
  final PdfToMusicXmlConverter? _pdfConverter;

  ScoreImportService({
    MidiFileParser? midiParser,
    MusicXmlParser? musicXmlParser,
    PdfToMusicXmlConverter? pdfConverter,
  }) : _midiParser = midiParser ?? MidiFileParser(),
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
        return ScoreSession.midiOnly(await _midiParser.parseFile(filePath));
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
