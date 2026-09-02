import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/notation/midi_notation_service.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
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
    final workerStarted = Completer<void>();
    final service = MidiNotationService(
      onWorkerStarted: () {
        if (!workerStarted.isCompleted) workerStarted.complete();
      },
    );
    final cancelled = service.prepare(
      _largeSong(noteCount: 500000),
      fingerprint: 'asset:cancel.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );
    final cancellationExpectation = expectLater(
      cancelled,
      throwsA(isA<MidiNotationCancelledException>()),
    );

    await workerStarted.future;
    service.cancel();

    await cancellationExpectation;
    final recovered = await service.prepare(
      _song(),
      fingerprint: 'asset:recovered.mid',
      globalDefaultKinds: {MidiPartKind.piano},
    );
    expect(recovered.session.sourceFingerprint, 'asset:recovered.mid');
  });

  test('记谱 worker 未回传结果即退出时 Future 不会悬挂', () async {
    final service = MidiNotationService(
      workerEntrypoint: _exitWithoutNotationResponse,
    );

    await expectLater(
      service
          .prepare(
            _song(),
            fingerprint: 'asset:exit.mid',
            globalDefaultKinds: {MidiPartKind.piano},
          )
          .timeout(const Duration(seconds: 1)),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('worker exited'),
        ),
      ),
    );
  });

  test('记谱 worker 抛出不可发送对象时 Future 不会悬挂', () async {
    final service = MidiNotationService(
      workerEntrypoint: _throwUnsendableWorkerError,
    );

    try {
      await service
          .prepare(
            _song(),
            fingerprint: 'asset:unsendable.mid',
            globalDefaultKinds: {MidiPartKind.piano},
          )
          .timeout(const Duration(seconds: 1));
      fail('异常 worker 应完成为错误');
    } catch (error) {
      expect(error, isNot(isA<TimeoutException>()));
    }
  });
}

void _exitWithoutNotationResponse(Object? _) {}

void _throwUnsendableWorkerError(Object? _) {
  throw ReceivePort();
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
