import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = <String, ({int program, String name})>{
    'assets/soundfonts/k478_violin.sf2': (program: 40, name: 'Violin'),
    'assets/soundfonts/k478_cello.sf2': (program: 42, name: 'Cello'),
  };

  for (final entry in cases.entries) {
    test('${entry.key} 是未压缩的单预设 SF2', () {
      final bytes = File(entry.key).readAsBytesSync();
      final data = ByteData.sublistView(bytes);

      expect(bytes.length, greaterThan(12));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'sfbk');
      expect(data.getUint32(4, Endian.little) + 8, bytes.length);
      expect(_containsAscii(bytes, 'OggS'), isFalse);

      final presets = MidiPro.parseSoundfontPresets(bytes);
      expect(presets, hasLength(1));
      expect(presets.single.bank, 0);
      expect(presets.single.program, entry.value.program);
      expect(presets.single.name, entry.value.name);
    });
  }
}

bool _containsAscii(Uint8List bytes, String value) {
  final pattern = value.codeUnits;
  for (var offset = 0; offset <= bytes.length - pattern.length; offset++) {
    var matches = true;
    for (var index = 0; index < pattern.length; index++) {
      if (bytes[offset + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
