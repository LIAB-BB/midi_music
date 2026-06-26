import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'music_xml_parser.dart';
import 'score_document.dart';

class MxlParseException implements Exception {
  final String message;

  const MxlParseException(this.message);

  @override
  String toString() => message;
}

class MxlScoreParser {
  final MusicXmlScoreParser musicXmlParser;

  const MxlScoreParser({this.musicXmlParser = const MusicXmlScoreParser()});

  ScoreDocument parse(
    Uint8List bytes, {
    String sourceId = 'mxl',
    String? path,
  }) {
    final archive = _decodeArchive(bytes);
    final container = archive.findFile('META-INF/container.xml');
    if (container == null) {
      throw const MxlParseException('MXL 缺少 META-INF/container.xml。');
    }

    final rootfilePath = _rootfilePath(_decodeText(container));
    final scoreFile = archive.findFile(rootfilePath);
    if (scoreFile == null) {
      throw MxlParseException('MXL rootfile 不存在：$rootfilePath。');
    }

    return musicXmlParser.parse(
      _decodeText(scoreFile),
      sourceId: sourceId,
      path: path ?? rootfilePath,
    );
  }

  Archive _decodeArchive(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } on Object catch (error) {
      throw MxlParseException('MXL zip 解码失败：$error。');
    }
  }

  String _rootfilePath(String containerXml) {
    if (!containerXml.contains('<container')) {
      throw const MxlParseException('MXL container.xml 根节点不是 container。');
    }
    final rootfilePattern = RegExp(
      r'''<rootfile\b[^>]*\bfull-path\s*=\s*["']([^"']+)["']''',
      multiLine: true,
    );
    final match = rootfilePattern.firstMatch(containerXml);
    if (match != null) {
      return _decodeXmlEntities(match.group(1)!.trim());
    }
    throw const MxlParseException('MXL container.xml 缺少 rootfile full-path。');
  }

  String _decodeText(ArchiveFile file) {
    final content = file.content;
    final bytes = switch (content) {
      List<int> value => value,
      _ => throw MxlParseException('MXL 文件内容类型不支持：${file.name}。'),
    };
    return utf8.decode(bytes);
  }
}

String _decodeXmlEntities(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
