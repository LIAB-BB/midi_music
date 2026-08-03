import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';

void main() {
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

  test('钢琴四重奏 demo 保留独立的钢琴双手与弦乐轨', () async {
    const filePath = 'assets/midi/mozart_k478_piano_quartet.mid';
    final file = File(filePath);

    expect(file.existsSync(), isTrue, reason: 'K.478 demo MIDI 文件不存在');

    final song = await MidiFileParser().parseFile(filePath);
    final upper = song.tracks.singleWhere((track) => track.name == 'upper');
    final lower = song.tracks.singleWhere((track) => track.name == 'lower');

    expect(song.format, 1);
    expect(song.noteTracks, hasLength(5));
    expect(song.totalDuration, closeTo(479.7, 0.2));
    expect(upper.channels, {3});
    expect(lower.channels, {4});
    expect(upper.notes, isNotEmpty);
    expect(lower.notes, isNotEmpty);
  });
}
