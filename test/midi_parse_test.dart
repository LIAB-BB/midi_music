import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('解析内置 MIDI 样例并生成播放数据', () async {
    const filePath = 'assets/midi/Beethoven-Moonlight-Sonata.mid';
    final file = File(filePath);

    expect(file.existsSync(), isTrue, reason: '测试样例 MIDI 文件不存在');

    final song = await MidiFileParser().parseFile(filePath);

    expect(song.fileName, 'Beethoven-Moonlight-Sonata.mid');
    expect(song.format, anyOf(0, 1));
    expect(song.ticksPerBeat, greaterThan(0));
    expect(song.tracks, isNotEmpty);
    expect(song.noteTracks, isNotEmpty);
    expect(song.timeline, isNotEmpty);
    expect(song.totalTicks, greaterThan(0));
    expect(song.totalDuration, greaterThan(0));
  });

  test('从 Flutter asset 后台解析 MIDI 样例', () async {
    final song = await MidiFileParser().parseAsset(
      'assets/midi/bach_wtc1_prelude.mid',
    );

    expect(song.fileName, 'bach_wtc1_prelude.mid');
    expect(song.noteTracks, isNotEmpty);
    expect(song.timeline, isNotEmpty);
    expect(song.totalDuration, greaterThan(0));
  });
}
