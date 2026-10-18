import 'dart:io';

import '../../models/midi_track.dart';
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

  Future<MidiSongData> importFile(String filePath) async {
    final extension = _extensionOf(filePath);
    switch (extension) {
      case '.mid':
      case '.midi':
        return _midiParser.parseFile(filePath);
      case '.xml':
      case '.musicxml':
        return _musicXmlParser.parseFile(filePath);
      case '.pdf':
        return _importPdf(filePath);
      default:
        throw UnsupportedError('暂不支持的乐谱格式：$extension');
    }
  }

  Future<MidiSongData> _importPdf(String filePath) async {
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
    final musicXml = await converter.convert(pdfFile);
    return _musicXmlParser.parseString(
      musicXml,
      fileName: '${_basenameWithoutExtension(filePath)}.musicxml',
    );
  }

  String _extensionOf(String filePath) {
    final fileName = _basename(filePath);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return '';
    return fileName.substring(dotIndex).toLowerCase();
  }

  String _basenameWithoutExtension(String filePath) {
    final fileName = _basename(filePath);
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0) return fileName;
    return fileName.substring(0, dotIndex);
  }

  /// 同时接受 `/` 与 `\`：Windows 上 `Directory.systemTemp.path` 可能是
  /// 反斜杠，而调用方/测试可能用正斜杠拼接路径。
  String _basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isEmpty ? filePath : segments.last;
  }
}
