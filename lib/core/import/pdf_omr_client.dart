import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pdf_to_musicxml_converter.dart';

const String omrServiceBaseUrlFromEnvironment = String.fromEnvironment(
  'OMR_SERVICE_BASE_URL',
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

  HttpPdfToMusicXmlConverter({
    required this.baseUrl,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(seconds: 2),
    this.maxPollAttempts = 90,
  }) : _httpClient = httpClient ?? HttpClient();

  @override
  Future<String> convert(File pdfFile) async {
    return _wrapNetworkErrors(() async {
      final jobId = await _createJob(pdfFile);
      return _waitForMusicXml(jobId);
    });
  }

  Future<String> _createJob(File pdfFile) async {
    final boundary = 'midi-music-${DateTime.now().microsecondsSinceEpoch}';
    final request = await _httpClient
        .postUrl(_resolve('/v1/omr/jobs'))
        .timeout(timeout);
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );

    request
      ..write('--$boundary\r\n')
      ..write(
        'Content-Disposition: form-data; name="file"; '
        'filename="${_escapeHeaderValue(pdfFile.uri.pathSegments.last)}"\r\n',
      )
      ..write('Content-Type: application/pdf\r\n\r\n');
    await request.addStream(pdfFile.openRead());
    request.write('\r\n--$boundary--\r\n');

    final response = await request.close().timeout(timeout);
    final body = await _readBody(response);
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
      final request = await _httpClient
          .getUrl(_resolve('/v1/omr/jobs/${Uri.encodeComponent(jobId)}'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await _readBody(response);
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
    final request = await _httpClient.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    final body = await _readBody(response);
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
}
