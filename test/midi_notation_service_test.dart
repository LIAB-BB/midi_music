import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/core/import/score_import_service.dart';
import 'package:midi_music/core/notation/midi_notation_service.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('MIDI 导入使用内容哈希且路径变化不改变指纹', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'midi-notation-fingerprint-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final bytes = await File('assets/midi/mozart_k545.mid').readAsBytes();
    final copyA = File('${temporaryDirectory.path}/copy-a.mid');
    final copyB = File('${temporaryDirectory.path}/copy-b.midi');
    await copyA.writeAsBytes(bytes);
    await copyB.writeAsBytes(bytes);
    final service = ScoreImportService();

    final a = await service.importFile(copyA.path);
    final b = await service.importFile(copyB.path);

    expect(a.sourceFingerprint, startsWith('midi:sha256:'));
    expect(a.sourceFingerprint, b.sourceFingerprint);
  });

  testWidgets('大 MIDI 解析与哈希期间 UI isolate 仍可响应', (tester) async {
    final bytes = _largeMidi(noteCount: 2000);
    var fileReadCount = 0;
    final service = ScoreImportService(
      midiBytesReader: (path) {
        fileReadCount++;
        return SynchronousFuture<Uint8List>(bytes);
      },
      midiImportWorker: _slowMidiImportWorker,
    );
    var tickerCount = 0;
    final ticker = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 1),
    )..addListener(() => tickerCount++);
    unawaited(ticker.repeat());

    var completed = false;
    late Future<ScoreSession> future;
    await tester.runAsync(() async {
      future = service.importFile('/virtual/large.mid');
      unawaited(future.whenComplete(() => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 16));
    ticker.dispose();

    expect(tickerCount, greaterThan(0));
    expect(completed, isFalse);
    await tester.runAsync(() => future);
    expect(fileReadCount, 1);
  });

  test('parseFile 和字节入口共用可等待的后台 worker', () async {
    final directory = await Directory.systemTemp.createTemp(
      'midi-parser-background-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fixture.mid');
    final bytes = _largeMidi(noteCount: 1);
    await file.writeAsBytes(bytes);
    final requests = <({Uint8List bytes, String fileName})>[];
    final completers = <Completer<MidiSongData>>[];
    final parser = MidiFileParser(
      backgroundRunner: (bytes, fileName) {
        requests.add((bytes: bytes, fileName: fileName));
        final completer = Completer<MidiSongData>();
        completers.add(completer);
        return completer.future;
      },
    );

    final bytesFuture = parser.parseBytesInBackground(
      bytes,
      fileName: 'bytes.mid',
    );
    expect(requests.single.fileName, 'bytes.mid');
    final bytesSong = _song();
    completers.single.complete(bytesSong);
    expect(await bytesFuture, same(bytesSong));

    final fileFuture = parser.parseFile(file.path);
    while (requests.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(requests, hasLength(2));
    expect(requests.last.fileName, 'fixture.mid');
    expect(requests.last.bytes, bytes);
    final fileSong = _song();
    completers.last.complete(fileSong);
    expect(await fileFuture, same(fileSong));
  });

  test('服务在异步边界分析、解析默认并生成显示会话', () async {
    final song = _song();

    final prepared = await MidiNotationService().prepare(
      song,
      fingerprint: 'asset:a.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );

    expect(prepared.catalog.parts, isNotEmpty);
    expect(prepared.selection.partIds, prepared.catalog.recommendedPartIds);
    expect(prepared.selection.origin, MidiSelectionOrigin.globalDefault);
    expect(prepared.session.sourceType, ScoreSourceType.midiNotation);
    expect(prepared.session.sourceFingerprint, 'asset:a.mid');
    expect(prepared.session.songData, same(song));
    expect(prepared.session.hasInteractiveScore, isTrue);
  });

  test('重建验证选择并重新绑定原始播放数据实例', () async {
    final song = _song();
    final service = MidiNotationService();
    final prepared = await service.prepare(
      song,
      fingerprint: 'asset:a.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );

    final rebuilt = await service.rebuild(
      song,
      catalog: prepared.catalog,
      selectedPartIds: prepared.catalog.recommendedPartIds,
    );

    expect(rebuilt.songData, same(song));
    expect(rebuilt.sourceFingerprint, prepared.catalog.fingerprint);
    expect(rebuilt.selectedPartIds, prepared.catalog.recommendedPartIds);
    await expectLater(
      service.rebuild(
        song,
        catalog: prepared.catalog,
        selectedPartIds: const {'missing'},
      ),
      throwsArgumentError,
    );
  });

  test('取消会终止当前 isolate worker 且后续任务可继续', () async {
    final service = MidiNotationService();
    final cancelled = service.prepare(
      _largeSong(noteCount: 500000),
      fingerprint: 'asset:cancel.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );
    final cancellationExpectation = expectLater(
      cancelled,
      throwsA(isA<MidiNotationCancelledException>()),
    );

    service.cancel();

    await cancellationExpectation;
    final recovered = await service.prepare(
      _song(),
      fingerprint: 'asset:recovered.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );
    expect(recovered.session.sourceFingerprint, 'asset:recovered.mid');
  });
}

MidiImportWorkerResult _slowMidiImportWorker(
  MidiFileParser parser,
  Uint8List bytes, {
  required String fileName,
}) {
  final deadline = DateTime.now().add(const Duration(milliseconds: 100));
  while (DateTime.now().isBefore(deadline)) {}
  return (
    digest: sha256.convert(bytes).toString(),
    songData: parser.parseBytes(bytes, fileName: fileName),
  );
}

MidiSongData _song() {
  final note = MidiNote(
    noteNumber: 60,
    velocity: 90,
    channel: 0,
    startTick: 0,
    endTick: 480,
    endTime: 0.5,
  );
  final track = MidiTrackInfo(
    index: 0,
    name: 'Piano',
    channels: {0},
    programByChannel: {0: 0},
    notes: [note],
  );
  return MidiSongData(
    fileName: 'fixture.mid',
    format: 0,
    ticksPerBeat: 480,
    tracks: [track],
    timeline: const [],
    tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
    timeSignatureChanges: [
      TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
    ],
    totalTicks: 1920,
    totalDuration: 2,
  );
}

MidiSongData _largeSong({required int noteCount}) {
  final notes = [
    for (var index = 0; index < noteCount; index++)
      MidiNote(
        noteNumber: 60 + (index % 12),
        velocity: 90,
        channel: 0,
        startTick: index * 120,
        endTick: index * 120 + 120,
        endTime: index / 4 + 0.25,
      ),
  ];
  final track = MidiTrackInfo(
    index: 0,
    name: 'Piano',
    channels: {0},
    programByChannel: {0: 0},
    notes: notes,
  );
  return MidiSongData(
    fileName: 'large.mid',
    format: 0,
    ticksPerBeat: 480,
    tracks: [track],
    timeline: const [],
    tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
    timeSignatureChanges: [
      TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
    ],
    totalTicks: noteCount * 120,
    totalDuration: noteCount / 4,
  );
}

Uint8List _largeMidi({required int noteCount}) {
  final track = BytesBuilder(copy: false);
  for (var index = 0; index < noteCount; index++) {
    track.add(const [0x00, 0x90, 0x3c, 0x40]);
    track.add(const [0x01, 0x80, 0x3c, 0x00]);
  }
  track.add(const [0x00, 0xff, 0x2f, 0x00]);
  final trackBytes = track.takeBytes();
  final result = BytesBuilder(copy: false)
    ..add(const [
      0x4d,
      0x54,
      0x68,
      0x64,
      0x00,
      0x00,
      0x00,
      0x06,
      0x00,
      0x00,
      0x00,
      0x01,
      0x01,
      0xe0,
      0x4d,
      0x54,
      0x72,
      0x6b,
    ])
    ..add([
      (trackBytes.length >> 24) & 0xff,
      (trackBytes.length >> 16) & 0xff,
      (trackBytes.length >> 8) & 0xff,
      trackBytes.length & 0xff,
    ])
    ..add(trackBytes);
  return result.takeBytes();
}
