import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pdf_to_musicxml_converter.dart';

const String omrServiceBaseUrlFromEnvironment = String.fromEnvironment(
  'OMR_SERVICE_BASE_URL',
);
const int omrMaxUploadMbFromEnvironment = int.fromEnvironment(
  'OMR_MAX_UPLOAD_MB',
  defaultValue: 30,
);

class OmrServiceException implements Exception {
  final String message;
  final Object? cause;

  const OmrServiceException(this.message, {this.cause});

  @override
  String toString() => message;
}

class HttpPdfToMusicXmlConverter implements PdfToMusicXmlConverter {
  final Uri baseUrl;
  final HttpClient _httpClient;
  final Duration timeout;
  final Duration pollInterval;
  final int maxPollAttempts;
  final int maxUploadBytes;

  HttpPdfToMusicXmlConverter({
    required this.baseUrl,
    HttpClient? httpClient,
    this.timeout = const Duration(minutes: 2),
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 300,
    this.maxUploadBytes = omrMaxUploadMbFromEnvironment * 1024 * 1024,
  }) : _httpClient = httpClient ?? HttpClient();

  @override
  Future<String> convert(File pdfFile) async {
    return _wrapNetworkErrors(() async {
      await _validatePdfSize(pdfFile);
      final jobId = await _createJob(pdfFile);
      return _waitForMusicXml(jobId);
    });
  }

  Future<String> _createJob(File pdfFile) async {
    final boundary = 'midi-music-${DateTime.now().microsecondsSinceEpoch}';
    final header =
        '--$boundary\r\n'
        '${_contentDispositionForFile(pdfFile)}'
        'Content-Type: application/pdf\r\n\r\n';
    final footer = '\r\n--$boundary--\r\n';
    final pdfLength = await pdfFile.length();
    final headerBytes = utf8.encode(header);
    final footerBytes = utf8.encode(footer);

    final request = await _withTimeout(
      _httpClient.postUrl(_resolve('/v1/omr/jobs')),
      '连接 PDF 识谱服务',
    );
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    request.contentLength = headerBytes.length + pdfLength + footerBytes.length;

    request.add(headerBytes);
    await _withTimeout(request.addStream(pdfFile.openRead()), '上传 PDF 文件');
    request.add(footerBytes);

    final response = await _withTimeout(request.close(), '创建 PDF 识谱任务');
    final body = await _withTimeout(_readBody(response), '读取 PDF 识谱任务响应');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OmrServiceException('PDF 识谱任务创建失败：${response.statusCode} $body');
    }

    final jsonBody = _decodeJsonObject(body);
    final jobId = jsonBody['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const OmrServiceException('PDF 识谱服务返回缺少 jobId');
    }
    return jobId;
  }

  Future<String> _waitForMusicXml(String jobId) async {
    for (var attempt = 0; attempt < maxPollAttempts; attempt++) {
      final request = await _withTimeout(
        _httpClient.getUrl(
          _resolve('/v1/omr/jobs/${Uri.encodeComponent(jobId)}'),
        ),
        '连接 PDF 识谱服务',
      );
      final response = await _withTimeout(request.close(), '查询 PDF 识谱任务');
      final body = await _withTimeout(_readBody(response), '读取 PDF 识谱任务响应');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OmrServiceException('PDF 识谱任务查询失败：${response.statusCode} $body');
      }

      final jsonBody = _decodeJsonObject(body);
      final status = jsonBody['status'];
      switch (status) {
        case 'succeeded':
          final musicXml = jsonBody['musicXml'];
          if (musicXml is String && musicXml.trim().isNotEmpty) {
            return musicXml;
          }
          final downloadUrl = jsonBody['downloadUrl'];
          if (downloadUrl is String && downloadUrl.isNotEmpty) {
            return _downloadMusicXml(downloadUrl);
          }
          throw const OmrServiceException('PDF 识谱成功但未返回 MusicXML');
        case 'failed':
          final message = jsonBody['message'];
          throw OmrServiceException(
            message is String && message.isNotEmpty ? message : 'PDF 识谱失败',
          );
        case 'queued':
        case 'running':
          await Future<void>.delayed(pollInterval);
          break;
        default:
          throw OmrServiceException('未知的 PDF 识谱任务状态：$status');
      }
    }
    throw const OmrServiceException('PDF 识谱超时，请稍后重试');
  }

  Future<String> _downloadMusicXml(String downloadUrl) async {
    final uri = Uri.parse(downloadUrl);
    final request = await _withTimeout(
      _httpClient.getUrl(uri),
      '连接 MusicXML 下载地址',
    );
    final response = await _withTimeout(request.close(), '下载 MusicXML');
    final body = await _withTimeout(_readBody(response), '读取 MusicXML 响应');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OmrServiceException('MusicXML 下载失败：${response.statusCode} $body');
    }
    return body;
  }

  Future<T> _wrapNetworkErrors<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on OmrServiceException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OmrServiceException(
        'PDF 识谱服务响应超时，请检查网络是否稳定，或换一份页数更少、更清晰的 PDF 后重试。',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OmrServiceException(
        'PDF 识谱服务连接中断，请稍后重试；如果多次出现，请检查 OMR 服务是否重启或代理是否稳定。',
        cause: error,
      );
    } on HttpException catch (error) {
      throw OmrServiceException('PDF 识谱服务连接失败，请检查服务地址和网络。', cause: error);
    } on FormatException catch (error) {
      throw OmrServiceException('PDF 识谱服务返回内容异常，请稍后重试。', cause: error);
    }
  }

  Uri _resolve(String path) {
    final normalizedBase = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return normalizedBase.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
  }

  Future<String> _readBody(HttpClientResponse response) {
    return utf8.decoder.bind(response).join();
  }

  Future<void> _validatePdfSize(File pdfFile) async {
    final size = await pdfFile.length();
    if (size <= maxUploadBytes) return;

    throw OmrServiceException(
      'PDF 文件过大：${_formatBytes(size)}。'
      '当前 OMR 上传限制为 ${_formatBytes(maxUploadBytes)}，'
      '请压缩 PDF，或同时提高服务端 OMR_MAX_UPLOAD_MB 和 App 启动参数。',
    );
  }

  Future<T> _withTimeout<T>(Future<T> future, String action) {
    return future.timeout(
      timeout,
      onTimeout: () => throw OmrServiceException(
        '$action超时，请确认手机与 OMR 服务在同一网络，'
        '服务仍在运行，或尝试更小、更清晰的 PDF。',
      ),
    );
  }

  Map<String, Object?> _decodeJsonObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
    throw const OmrServiceException('PDF 识谱服务返回格式不是 JSON 对象');
  }

  String _escapeHeaderValue(String value) {
    return value
        .replaceAll('"', r'\"')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
  }

  String _contentDispositionForFile(File pdfFile) {
    final fileName = pdfFile.uri.pathSegments.last;
    final fallbackFileName = _asciiFallbackFileName(fileName);
    return 'Content-Disposition: form-data; name="file"; '
        'filename="${_escapeHeaderValue(fallbackFileName)}"; '
        "filename*=UTF-8''${_encodeRfc5987Value(fileName)}\r\n";
  }

  String _asciiFallbackFileName(String fileName) {
    final sanitized = fileName
        .replaceAll(RegExp(r'[\r\n"\\]'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._()-]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty || sanitized == '.pdf') {
      return 'score.pdf';
    }
    if (sanitized.toLowerCase().endsWith('.pdf')) {
      return sanitized;
    }
    return '$sanitized.pdf';
  }

  String _encodeRfc5987Value(String value) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(value)) {
      if (_isRfc5987AttrChar(byte)) {
        buffer.writeCharCode(byte);
      } else {
        buffer.write(
          '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}',
        );
      }
    }
    return buffer.toString();
  }

  bool _isRfc5987AttrChar(int byte) {
    return byte >= 0x30 && byte <= 0x39 ||
        byte >= 0x41 && byte <= 0x5A ||
        byte >= 0x61 && byte <= 0x7A ||
        byte == 0x21 ||
        byte == 0x23 ||
        byte == 0x24 ||
        byte == 0x26 ||
        byte == 0x2B ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5E ||
        byte == 0x5F ||
        byte == 0x60 ||
        byte == 0x7C ||
        byte == 0x7E;
  }

  String _formatBytes(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)}MB';
    }
    const kb = 1024;
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)}KB';
    }
    return '$bytes bytes';
  }
}
