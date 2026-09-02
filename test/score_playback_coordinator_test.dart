import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/score_playback_coordinator.dart';
import 'package:midi_music/core/score/score_playback_port.dart';
import 'package:midi_music/core/score/score_renderer_port.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('点击只能命中渲染器上报的可映射小节', () {
    final player = _FakePlayer(scoreSession: _interactiveSession());
    final renderer = _RecordingRenderer();
    final coordinator = ScorePlaybackCoordinator(
      player: player,
      port: renderer,
    );
    coordinator.handleMessage(_layout());

    expect(
      coordinator.handleMessage(_tapAt(50, 120)),
      ScoreMessageHandlingResult.handled,
    );
    expect(player.currentMeasureOrdinal, 2);
    expect(
      coordinator.handleMessage(_tapAt(250, 120)),
      ScoreMessageHandlingResult.ignored,
    );

    player.scoreSession = _partialSession();
    player.currentMeasureOrdinal = 1;
    expect(
      coordinator.handleMessage(_tapAt(50, 120)),
      ScoreMessageHandlingResult.unmappableMeasure,
    );
    expect(player.currentMeasureOrdinal, 1);
  });

  test('手动浏览暂停自动滚动，恢复跟随后重新滚动', () async {
    final player = _FakePlayer(scoreSession: _interactiveSession());
    final renderer = _RecordingRenderer();
    final coordinator = ScorePlaybackCoordinator(
      player: player,
      port: renderer,
    );

    coordinator.handleMessage(
      const ScoreRendererMessage.gestureEnd(
        x: 50,
        y: 120,
        travel: 40,
        durationMs: 300,
        pointerCount: 1,
      ),
    );
    player.currentMeasureOrdinal = 2;
    coordinator.syncFromPlayer();
    expect(renderer.scrollFlags.last, isFalse);
    await _drainAsyncCommands();

    coordinator.resumeAutoFollow();
    coordinator.syncFromPlayer(force: true);
    expect(renderer.scrollFlags.last, isTrue);
  });

  test('同步命令在成功后去重，失败后下一次同步会重试', () async {
    final player = _FakePlayer(scoreSession: _interactiveSession());
    final renderer = _ControllableRenderer();
    final coordinator = ScorePlaybackCoordinator(
      player: player,
      port: renderer,
    );

    coordinator.syncFromPlayer();
    coordinator.syncFromPlayer();
    expect(renderer.highlighted, [1]);
    renderer.highlightCompleters.single.completeError(StateError('failed'));
    await _drainAsyncCommands();

    coordinator.syncFromPlayer();
    expect(renderer.highlighted, [1, 1]);
    renderer.highlightCompleters.last.complete();
    await _drainAsyncCommands();
    coordinator.syncFromPlayer();
    expect(renderer.highlighted, [1, 1]);
  });

  test('清除高亮失败后可重试，并在成功后去重', () async {
    final player = _FakePlayer(scoreSession: _interactiveSession());
    final renderer = _ControllableRenderer();
    final coordinator = ScorePlaybackCoordinator(
      player: player,
      port: renderer,
    );
    player.currentMeasureOrdinal = null;

    coordinator.syncFromPlayer();
    coordinator.syncFromPlayer();
    expect(renderer.clearCount, 1);
    renderer.clearCompleters.single.completeError(StateError('failed'));
    await _drainAsyncCommands();

    coordinator.syncFromPlayer();
    expect(renderer.clearCount, 2);
    renderer.clearCompleters.last.complete();
    await _drainAsyncCommands();
    coordinator.syncFromPlayer();
    expect(renderer.clearCount, 2);
  });
}

ScoreRendererMessage _layout() => const ScoreRendererMessage.layout(
  complete: true,
  measureRects: [
    ScoreMeasureRect(ordinal: 2, left: 0, top: 100, width: 200, height: 80),
  ],
);

ScoreRendererMessage _tapAt(double x, double y) =>
    ScoreRendererMessage.gestureEnd(
      x: x,
      y: y,
      travel: 4,
      durationMs: 120,
      pointerCount: 1,
    );

Future<void> _drainAsyncCommands() async {
  await Future<void>.value();
  await Future<void>.value();
}

class _FakePlayer implements ScorePlaybackPort {
  @override
  ScoreSession? scoreSession;

  @override
  int? currentMeasureOrdinal;

  _FakePlayer({required this.scoreSession}) : currentMeasureOrdinal = 1;

  @override
  bool seekToMeasure(int ordinal) {
    if (scoreSession?.isMeasureInteractive(ordinal) != true) return false;
    currentMeasureOrdinal = ordinal;
    return true;
  }
}

class _RecordingRenderer implements ScoreRendererPort {
  final List<int> highlighted = [];
  final List<bool> scrollFlags = [];
  int clearCount = 0;

  @override
  Future<void> clearHighlight() {
    clearCount++;
    return Future<void>.value();
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    highlighted.add(ordinal);
    scrollFlags.add(scrollIntoView);
    return Future<void>.value();
  }

  @override
  Future<void> loadMusicXml(String musicXml) => Future<void>.value();

  @override
  Future<void> setZoom(double zoom) => Future<void>.value();
}

class _ControllableRenderer extends _RecordingRenderer {
  final List<Completer<void>> highlightCompleters = [];
  final List<Completer<void>> clearCompleters = [];

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    highlighted.add(ordinal);
    scrollFlags.add(scrollIntoView);
    final completer = Completer<void>();
    highlightCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<void> clearHighlight() {
    clearCount++;
    final completer = Completer<void>();
    clearCompleters.add(completer);
    return completer.future;
  }
}

ScoreSession _interactiveSession() => ScoreSession(
  songData: _song(),
  musicXml: '<score-partwise/>',
  sourceType: ScoreSourceType.midiNotation,
  measures: const [
    ScoreMeasureBoundary(ordinal: 1, label: '1', startTick: 0, endTick: 1920),
    ScoreMeasureBoundary(
      ordinal: 2,
      label: '2',
      startTick: 1920,
      endTick: 3840,
    ),
  ],
  mappingStatus: ScoreMappingStatus.complete,
);

ScoreSession _partialSession() => ScoreSession(
  songData: _song(),
  musicXml: '<score-partwise/>',
  sourceType: ScoreSourceType.midiNotation,
  measures: const [
    ScoreMeasureBoundary(ordinal: 1, label: '1', startTick: 0, endTick: 1920),
    ScoreMeasureBoundary(
      ordinal: 2,
      label: '2',
      startTick: 1920,
      endTick: 3840,
      isInteractive: false,
    ),
  ],
  mappingStatus: ScoreMappingStatus.partial,
);

MidiSongData _song() => MidiSongData(
  fileName: 'fixture.mid',
  format: 0,
  ticksPerBeat: 480,
  tracks: const [],
  timeline: const [],
  tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
  timeSignatureChanges: [
    TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
  ],
  totalTicks: 3840,
  totalDuration: 4,
);
