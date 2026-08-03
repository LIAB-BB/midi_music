import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/models/midi_track.dart';

/// MIDI 回归测试集
///
/// 使用程序生成的合成 MIDI 数据覆盖多种场景：
/// - Format 0 单轨 / Format 1 多轨
/// - 不同 PPQ 值
/// - 多 tempo 变化
/// - 多拍号变化
/// - 重叠音符、零力度 NoteOn、空轨道等边界情况
///
/// 每个测试解析后验证关键属性，确保解析器改动不引入退化。

void main() {
  // ============================================================
  // Format 0 — 单轨简单曲目
  // ============================================================

  test('Format 0 单轨两个音符', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0x90, 0x3C, 0x50, // C4 note on vel=80
        0x3C, 0x80, 0x3C, 0x00, // C4 note off
        0x00, 0x90, 0x40, 0x60, // E4 note on vel=96
        0x3C, 0x80, 0x40, 0x00, // E4 note off
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ]),
    );

    expect(song.format, 0);
    expect(song.ticksPerBeat, 480);
    expect(song.noteTracks, hasLength(1));

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(2));
    expect(notes[0].noteName, 'C4');
    expect(notes[0].velocity, 80);
    expect(notes[1].noteName, 'E4');
    expect(notes[1].velocity, 96);
    expect(notes[0].startTick, 0);
    expect(notes[0].endTick, 0x3C);
    expect(notes[1].startTick, 0x3C);
    expect(notes[1].endTick, 0x78);
    expect(song.totalDuration, greaterThan(0));
  });

  test('Format 0 包含 Program Change', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0xC0, 0x28, // program change to 40 (Violin)
        0x00, 0x90, 0x3C, 0x50,
        0x3C, 0x80, 0x3C, 0x00,
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    final track = song.noteTracks.single;
    expect(track.programByChannel[0], 40);
    expect(track.channels, contains(0));
    expect(
      song.timeline.any((e) => e.type == MidiEventType.programChange),
      isTrue,
    );
  });

  test('Format 0 零力度 NoteOn 视为 NoteOff', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0x90, 0x3C, 0x50, // C4 note on
        0x3C, 0x90, 0x3C, 0x00, // C4 velocity=0（等同于 note off）
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(1));
    expect(notes[0].startTick, 0);
    expect(notes[0].endTick, 0x3C);
  });

  // ============================================================
  // Format 1 — 多轨
  // ============================================================

  test('Format 1 两条轨道各自含音符', () {
    final song = _parse(
      _fmt1Midi([
        // Track 0: no notes, only meta
        [0x00, 0xFF, 0x2F, 0x00],
        // Track 1: two notes
        [
          0x00,
          0x90,
          0x40,
          0x60,
          0x3C,
          0x80,
          0x40,
          0x00,
          0x00,
          0xFF,
          0x2F,
          0x00,
        ],
      ]),
    );

    expect(song.format, 1);
    expect(song.tracks, hasLength(2));
    expect(song.noteTracks, hasLength(1)); // only track 1 has notes

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(1));
    expect(notes[0].noteName, 'E4');
  });

  test('Format 1 多轨各自独立 channel', () {
    final song = _parse(
      _fmt1Midi([
        [0x00, 0xFF, 0x2F, 0x00],
        [
          0x00, 0xC0, 0x00, // channel 0: piano
          0x00, 0x90, 0x3C, 0x50, 0x3C, 0x80, 0x3C, 0x00,
          0x00, 0xFF, 0x2F, 0x00,
        ],
        [
          0x00, 0xC1, 0x28, // channel 1: violin
          0x00, 0x91, 0x40, 0x60, 0x3C, 0x81, 0x40, 0x00,
          0x00, 0xFF, 0x2F, 0x00,
        ],
      ]),
    );

    expect(song.noteTracks, hasLength(2));
    final programs = <int, int>{};
    for (final t in song.noteTracks) {
      programs.addAll(t.programByChannel);
    }
    expect(programs[0], 0); // piano
    expect(programs[1], 40); // violin
  });

  // ============================================================
  // 重叠音符 FIFO 配对
  // ============================================================

  test('同 channel/note 三次重叠按 FIFO 配对三个音符', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0x90, 0x3C, 0x40, // C4 on #1
        0x0A, 0x90, 0x3C, 0x50, // C4 on #2 (overlap)
        0x0A, 0x90, 0x3C, 0x60, // C4 on #3 (double overlap)
        0x0A, 0x80, 0x3C, 0x00, // C4 off → should match #1
        0x0A, 0x80, 0x3C, 0x00, // C4 off → should match #2
        0x0A, 0x80, 0x3C, 0x00, // C4 off → should match #3
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(3));
    expect(notes[0].startTick, 0);
    expect(notes[0].endTick, 0x0A + 0x0A + 0x0A); // first note off at tick 30
    expect(notes[0].velocity, 0x40);
    expect(notes[1].startTick, 0x0A);
    expect(notes[1].endTick, 0x0A + 0x0A + 0x0A + 0x0A);
    expect(notes[1].velocity, 0x50);
    expect(notes[2].startTick, 0x0A + 0x0A);
    expect(notes[2].endTick, 0x0A + 0x0A + 0x0A + 0x0A + 0x0A);
    expect(notes[2].velocity, 0x60);
  });

  test('不同 channel 的同音符独立配对', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0x90, 0x3C, 0x40, // ch0 C4 on
        0x00, 0x91, 0x3C, 0x50, // ch1 C4 on
        0x3C, 0x80, 0x3C, 0x00, // ch0 C4 off
        0x00, 0x81, 0x3C, 0x00, // ch1 C4 off
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(2));
    expect(notes[0].channel, 0);
    expect(notes[1].channel, 1);
  });

  // ============================================================
  // Tempo 变化
  // ============================================================

  test('多个 tempo 变化点正确影响时长', () {
    final song = _parse(
      _fmt0Midi([
        // tempo 120 BPM at tick 0 (500000 us/beat)
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,
        // 第一个 480 ticks = 1 beat = 0.5s at 120 BPM
        0x00, 0x90, 0x3C, 0x50,
        0x83,
        0x60, // delta 480
        0xFF,
        0x51,
        0x03,
        0x0F,
        0x42,
        0x40, // tempo 60 BPM (1000000 us/beat)
        0x83, 0x60, 0x80, 0x3C, 0x00, // 再经过 480 ticks 后 note off
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    expect(song.tempoChanges.length, 2);
    expect(song.tempoChanges[0].bpm, closeTo(120, 0.1));
    expect(song.tempoChanges[1].bpm, closeTo(60, 0.1));
    expect(song.tempoChanges[1].tick, 480);
    expect(song.totalDuration, closeTo(1.5, 0.0001));
  });

  test('无 tempo 事件时使用默认 120 BPM', () {
    final song = _parse(
      _fmt0Midi([
        0x00,
        0x90,
        0x40,
        0x60,
        0x3C,
        0x80,
        0x40,
        0x00,
        0x00,
        0xFF,
        0x2F,
        0x00,
      ]),
    );

    expect(song.tempoChanges.length, 1); // parser adds default
    expect(song.tempoChanges.first.bpm, closeTo(120, 0.1));
  });

  // ============================================================
  // 拍号变化
  // ============================================================

  test('拍号事件被正确提取', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08, // 4/4
        0x82, 0x00, 0x90, 0x3C, 0x50, 0x3C, 0x80, 0x3C, 0x00,
        0x00, 0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08, // 3/4
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    expect(song.timeSignatureChanges.length, 2);
    expect(song.timeSignatureChanges[0].numerator, 4);
    expect(song.timeSignatureChanges[0].denominator, 4);
    expect(song.timeSignatureChanges[1].numerator, 3);
    expect(song.timeSignatureChanges[1].denominator, 4);
  });

  // ============================================================
  // 不同 PPQ 值
  // ============================================================

  test('非标准 PPQ 值正确解析', () {
    final song = _parse(
      _fmt0MidiWithPPQ(960, [
        0x00, 0x90, 0x3C, 0x50,
        0x82, 0x03, 0x80, 0x3C, 0x00, // ~480 ticks at PPQ=960
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    expect(song.ticksPerBeat, 960);
    expect(song.noteTracks.single.notes, hasLength(1));
  });

  // ============================================================
  // 边界情况
  // ============================================================

  test('空轨道不崩溃', () {
    final song = _parse(_fmt0Midi([0x00, 0xFF, 0x2F, 0x00]));

    expect(song.tracks, hasLength(1));
    expect(song.noteTracks, isEmpty);
    expect(song.timeline, isNotEmpty); // at least EOT
    expect(song.totalDuration, 0);
  });

  test('轨道名称被提取', () {
    final nameBytes = 'Violin'.codeUnits;
    final song = _parse(
      _fmt0Midi([
        // Track name meta event
        0x00,
        0xFF,
        0x03,
        nameBytes.length,
        ...nameBytes,
        0x00,
        0x90,
        0x3C,
        0x50,
        0x3C,
        0x80,
        0x3C,
        0x00,
        0x00,
        0xFF,
        0x2F,
        0x00,
      ]),
    );

    expect(song.tracks[0].name, 'Violin');
  });

  test('时间线事件按 tick 排序且同 tick 优先 NoteOff', () {
    final song = _parse(
      _fmt0Midi([
        0x0A, 0x90, 0x3C, 0x50, // note on at tick 10
        0x00, 0x80, 0x3C, 0x00, // note off at tick 10
        0x00, 0xC0, 0x28, // program change at tick 10
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    // Find events at tick 10（不含 EOT）
    final atTick10 = song.timeline
        .where((e) => e.tick == 10 && e.type != MidiEventType.endOfTrack)
        .toList();
    expect(atTick10.length, 3);
    // NoteOff 优先于控制事件，再优先于 NoteOn
    expect(atTick10[0].type, MidiEventType.noteOff);
    expect(atTick10[1].type, MidiEventType.programChange);
    expect(atTick10[2].type, MidiEventType.noteOn);
  });

  test('时间线包含所有事件类型', () {
    final song = _parse(
      _fmt0Midi([
        0x00, 0xC0, 0x28, // program change
        0x00, 0x90, 0x40, 0x60, // note on
        0x3C, 0x80, 0x40, 0x00, // note off
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ]),
    );

    final types = song.timeline.map((e) => e.type).toSet();
    expect(types, contains(MidiEventType.programChange));
    expect(types, contains(MidiEventType.noteOn));
    expect(types, contains(MidiEventType.noteOff));
    expect(types, contains(MidiEventType.endOfTrack));
  });

  _runRealFileTests();

  test('大跨度曲目不溢出', () {
    // A note lasting many ticks, using running status
    final song = _parse(
      _fmt0Midi([
        0x00, 0x90, 0x3C, 0x50, // note on at tick 0
        0x87, 0x0F, 0x80, 0x3C, 0x00, // note off at tick ~1000
        0x00, 0xFF, 0x2F, 0x00,
      ]),
    );

    final notes = song.noteTracks.single.notes;
    expect(notes, hasLength(1));
    expect(notes[0].duration, greaterThan(0));
  });
}

// 真实古典 MIDI 文件回归 — 在 main() 末尾调用 _runRealFileTests()

// ============================================================
// MIDI 构造辅助函数
// ============================================================

/// 真实古典 MIDI 文件回归测试
void _runRealFileTests() {
  const fixtures = [
    ('assets/midi/Beethoven-Moonlight-Sonata.mid', '贝多芬月光奏鸣曲', 4, 100),
    ('assets/midi/bach_wtc1_prelude.mid', '巴赫平均律 C大调前奏曲', 3, 50),
    ('assets/midi/mozart_k545.mid', '莫扎特钢琴奏鸣曲 K545', 2, 80),
    ('assets/midi/chopin_nocturne.mid', '肖邦夜曲', 2, 30),
    ('assets/midi/beethoven_moonlight_2.mid', '贝多芬月光第二乐章', 2, 20),
  ];

  for (final f in fixtures) {
    final (path, label, minTracks, minNotes) = f;
    test('真实文件 $label', () async {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '测试文件缺失：$path');

      final song = await MidiFileParser().parseFile(path);

      expect(song.fileName, isNotEmpty);
      expect(song.format, anyOf(0, 1));
      expect(song.ticksPerBeat, greaterThan(0));
      expect(song.tracks.length, greaterThanOrEqualTo(minTracks));
      expect(song.totalTicks, greaterThan(0));
      expect(song.totalDuration, greaterThan(0));

      final totalNotes = song.tracks.fold<int>(
        0,
        (sum, t) => sum + t.notes.length,
      );
      expect(
        totalNotes,
        greaterThanOrEqualTo(minNotes),
        reason: '期望至少 $minNotes 个音符，实际 $totalNotes',
      );

      expect(song.timeline, isNotEmpty);
      for (var i = 1; i < song.timeline.length; i++) {
        expect(
          song.timeline[i].tick,
          greaterThanOrEqualTo(song.timeline[i - 1].tick),
          reason: '时间线未按 tick 排序（索引 $i）',
        );
      }

      final lastEventTime = song.timeline.last.time;
      expect(
        lastEventTime,
        lessThanOrEqualTo(song.totalDuration + 0.001),
        reason: '最后事件时间超出总时长',
      );
    });
  }

  test('所有真实文件可读出有效初始 BPM', () async {
    for (final f in fixtures) {
      final (path, label, _, _) = f;
      final file = File(path);
      if (!file.existsSync()) continue;
      final song = await MidiFileParser().parseFile(path);
      expect(
        song.initialBpm,
        greaterThan(0),
        reason: '$label 的 initialBpm 应为正数',
      );
      expect(
        song.initialBpm,
        lessThan(300),
        reason: '$label 的 initialBpm 异常偏高',
      );
    }
  });
}

/// Parse a MIDI byte array into MidiSongData.
MidiSongData _parse(Uint8List bytes) {
  return MidiFileParser().parseBytes(bytes, fileName: 'synthetic.mid');
}

/// Build a Format 0 MIDI file from track data bytes.
Uint8List _fmt0Midi(List<int> trackData) {
  return _fmt0MidiWithPPQ(480, trackData);
}

/// Build a Format 0 MIDI file with a custom PPQ.
Uint8List _fmt0MidiWithPPQ(int ppq, List<int> trackData) {
  return Uint8List.fromList([
    0x4D, 0x54, 0x68, 0x64, // MThd
    0x00, 0x00, 0x00, 0x06, // header length
    0x00, 0x00, // format 0
    0x00, 0x01, // 1 track
    (ppq >> 8) & 0xFF,
    ppq & 0xFF, // ticks per beat
    0x4D, 0x54, 0x72, 0x6B, // MTrk
    (trackData.length >> 24) & 0xFF,
    (trackData.length >> 16) & 0xFF,
    (trackData.length >> 8) & 0xFF,
    trackData.length & 0xFF,
    ...trackData,
  ]);
}

/// Build a Format 1 MIDI file from multiple track data lists.
Uint8List _fmt1Midi(List<List<int>> trackDataList) {
  final trackChunks = <int>[];
  for (final data in trackDataList) {
    trackChunks.addAll([
      0x4D, 0x54, 0x72, 0x6B, // MTrk
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...data,
    ]);
  }

  return Uint8List.fromList([
    0x4D, 0x54, 0x68, 0x64, // MThd
    0x00, 0x00, 0x00, 0x06, // header length
    0x00, 0x01, // format 1
    (trackDataList.length >> 8) & 0xFF,
    trackDataList.length & 0xFF, // track count
    0x01, 0xE0, // 480 ticks per beat
    ...trackChunks,
  ]);
}
