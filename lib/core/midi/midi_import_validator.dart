import 'dart:io';

const int kMaxMidiImportBytes = 50 * 1024 * 1024;

enum MidiImportErrorType {
  unsupportedExtension,
  fileNotFound,
  emptyFile,
  fileTooLarge,
  permissionDenied,
  unknown,
}

class MidiImportException implements Exception {
  final MidiImportErrorType type;
  final String message;
  final String path;

  const MidiImportException(this.type, this.message, {required this.path});

  @override
  String toString() => message;
}

class MidiImportFileInfo {
  final String path;
  final int sizeBytes;

  const MidiImportFileInfo({required this.path, required this.sizeBytes});
}

Future<MidiImportFileInfo> validateMidiImportFile(
  String path, {
  int maxBytes = kMaxMidiImportBytes,
}) async {
  if (!_hasSupportedMidiExtension(path)) {
    throw MidiImportException(
      MidiImportErrorType.unsupportedExtension,
      '只支持导入 .mid 或 .midi 文件。',
      path: path,
    );
  }

  final file = File(path);
  try {
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw MidiImportException(
        MidiImportErrorType.fileNotFound,
        '文件不存在或已被移动。',
        path: path,
      );
    }
    if (stat.size <= 0) {
      throw MidiImportException(
        MidiImportErrorType.emptyFile,
        '文件为空，无法作为 MIDI 乐谱导入。',
        path: path,
      );
    }
    if (stat.size > maxBytes) {
      throw MidiImportException(
        MidiImportErrorType.fileTooLarge,
        '文件过大，当前最多支持 ${(maxBytes / 1024 / 1024).round()} MB 的 MIDI 文件。',
        path: path,
      );
    }
    return MidiImportFileInfo(path: path, sizeBytes: stat.size);
  } on MidiImportException {
    rethrow;
  } on FileSystemException catch (error) {
    final osError = error.osError;
    if (osError != null && osError.errorCode == 13) {
      throw MidiImportException(
        MidiImportErrorType.permissionDenied,
        '没有权限读取这个文件，请换一个文件或检查系统权限。',
        path: path,
      );
    }
    throw MidiImportException(
      MidiImportErrorType.unknown,
      '读取文件失败：${error.message}',
      path: path,
    );
  }
}

bool _hasSupportedMidiExtension(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mid') || lower.endsWith('.midi');
}
