import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_import_validator.dart';

void main() {
  test('接受 .mid 和 .midi 文件', () async {
    final tempDir = await Directory.systemTemp.createTemp('midi-import-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final mid = File('${tempDir.path}/score.mid')
      ..writeAsBytesSync([0x4d, 0x54, 0x68, 0x64]);
    final midi = File('${tempDir.path}/score.midi')
      ..writeAsBytesSync([0x4d, 0x54, 0x68, 0x64]);

    expect((await validateMidiImportFile(mid.path)).sizeBytes, 4);
    expect((await validateMidiImportFile(midi.path)).sizeBytes, 4);
  });

  test('拒绝非 MIDI 扩展名', () async {
    expect(
      () => validateMidiImportFile('/tmp/score.xml'),
      throwsA(
        isA<MidiImportException>().having(
          (e) => e.type,
          'type',
          MidiImportErrorType.unsupportedExtension,
        ),
      ),
    );
  });

  test('拒绝空文件和超过限制的文件', () async {
    final tempDir = await Directory.systemTemp.createTemp('midi-import-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final empty = File('${tempDir.path}/empty.mid')..writeAsBytesSync([]);
    final large = File('${tempDir.path}/large.mid')
      ..writeAsBytesSync([1, 2, 3]);

    expect(
      () => validateMidiImportFile(empty.path),
      throwsA(
        isA<MidiImportException>().having(
          (e) => e.type,
          'type',
          MidiImportErrorType.emptyFile,
        ),
      ),
    );
    expect(
      () => validateMidiImportFile(large.path, maxBytes: 2),
      throwsA(
        isA<MidiImportException>().having(
          (e) => e.type,
          'type',
          MidiImportErrorType.fileTooLarge,
        ),
      ),
    );
  });
}
