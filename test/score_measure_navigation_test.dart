import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/models/score_session.dart';

import 'helpers/score_test_fixtures.dart';

void main() {
  testWidgets('真实弱起小节按 MusicXML 边界跳转', (tester) async {
    final player = readyPlayer();
    addTearDown(player.dispose);
    final session = interactiveSession();

    player.loadScore(session);

    expect(player.scoreSession, same(session));
    expect(player.seekToMeasure(2), isTrue);
    expect(player.currentTime, closeTo(0.5, 0.0001));
    expect(player.currentMeasureOrdinal, 2);
  });

  testWidgets('小节跳转保持播放和暂停状态', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);

    player.play();
    expect(player.seekToMeasure(2), isTrue);
    expect(player.isPlaying, isTrue);

    player.pause();
    expect(player.seekToMeasure(1), isTrue);
    expect(player.isPaused, isTrue);

    player.stop();
    expect(player.seekToMeasure(2), isTrue);
    expect(player.isStopped, isTrue);
  });

  testWidgets('不可交互或越界小节不会改变时间', (tester) async {
    final player = readyPlayer()..loadScore(partialSession());
    addTearDown(player.dispose);
    player.seekTo(0.25);

    expect(player.seekToMeasure(2), isFalse);
    expect(player.seekToMeasure(99), isFalse);
    expect(player.currentTime, 0.25);
  });

  testWidgets('前后小节导航仅在可交互小节间移动', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);

    expect(player.seekToPreviousMeasure(), isFalse);
    expect(player.seekToNextMeasure(), isTrue);
    expect(player.currentMeasureOrdinal, 2);
    expect(player.seekToNextMeasure(), isFalse);
    expect(player.seekToPreviousMeasure(), isTrue);
    expect(player.currentMeasureOrdinal, 1);

    player.loadScore(partialSession());
    expect(player.seekToNextMeasure(), isFalse);
    expect(player.currentMeasureOrdinal, 1);
  });

  test('loadScore 切换到 loadSong 时只通知原子 MIDI-only 快照', () {
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final midiOnly = midiOnlySession();
    final snapshots = <_PlayerSnapshot>[];
    player.addListener(() => snapshots.add(_PlayerSnapshot.capture(player)));

    player.loadSong(midiOnly.songData);

    expect(snapshots.every((snapshot) => snapshot.isConsistent), isTrue);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.hasExplicitMeasures, isFalse);
  });

  test('loadSong 切换到 loadScore 时只通知原子谱面快照', () {
    final player = readyPlayer()..loadSong(midiOnlySession().songData);
    addTearDown(player.dispose);
    final score = interactiveSession();
    final snapshots = <_PlayerSnapshot>[];
    player.addListener(() => snapshots.add(_PlayerSnapshot.capture(player)));

    player.loadScore(score);

    expect(snapshots.every((snapshot) => snapshot.isConsistent), isTrue);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.hasExplicitMeasures, isTrue);
  });

  test('替换 MIDI 显示谱不重置播放状态且只通知一次', () {
    final player = readyPlayer();
    addTearDown(player.dispose);
    final presentation = interactiveSession();
    final base = ScoreSession.midiOnly(
      presentation.songData,
      sourceFingerprint: 'asset:a.mid',
    );
    player.loadScore(base, songId: 'a');
    player.setSpeed(1.25);
    player.seekTo(0.25);
    player.setLoopRange(start: 0.1, end: 0.4);
    player.setLoopEnabled(enabled: true);
    player.play();
    final notifications = <_PlayerSnapshot>[];
    player.addListener(
      () => notifications.add(_PlayerSnapshot.capture(player)),
    );

    expect(player.updateScorePresentation(presentation), isTrue);

    expect(player.scoreSession, same(presentation));
    expect(player.songData, same(presentation.songData));
    expect(player.currentTime, closeTo(0.25, 0.01));
    expect(player.playbackSpeed, 1.25);
    expect(player.loopStartTime, 0.1);
    expect(player.loopEndTime, 0.4);
    expect(player.isLoopEnabled, isTrue);
    expect(player.isPlaying, isTrue);
    expect(notifications, hasLength(1));
    expect(notifications.single.isConsistent, isTrue);
    expect(notifications.single.hasExplicitMeasures, isTrue);
  });

  test('拒绝无效显示谱替换且不通知或改变旧会话', () {
    final player = readyPlayer();
    addTearDown(player.dispose);
    final presentation = interactiveSession();
    final base = ScoreSession.midiOnly(presentation.songData);
    player.loadScore(base);
    var notifications = 0;
    player.addListener(() => notifications++);

    expect(player.updateScorePresentation(interactiveSession()), isFalse);
    expect(
      player.updateScorePresentation(
        ScoreSession.midiOnly(presentation.songData),
      ),
      isFalse,
    );

    expect(notifications, 0);
    expect(player.scoreSession, same(base));
    expect(player.measureMap?.scoreMeasures, isEmpty);
  });

  test('未加载歌曲时拒绝显示谱替换且不通知', () {
    final player = readyPlayer();
    addTearDown(player.dispose);
    var notifications = 0;
    player.addListener(() => notifications++);

    expect(player.updateScorePresentation(interactiveSession()), isFalse);

    expect(notifications, 0);
    expect(player.scoreSession, isNull);
  });

  test('拒绝 ordinal 重复或乱序的交互显示谱且保持旧映射', () {
    final source = interactiveSession();
    final first = source.measures.first;
    final second = source.measures[1];
    final duplicateOrdinal = _presentationWithMeasures(source, [
      first,
      ScoreMeasureBoundary(
        ordinal: first.ordinal,
        label: second.label,
        startTick: second.startTick,
        endTick: second.endTick,
      ),
    ]);
    final unordered = _presentationWithMeasures(source, [second, first]);

    _expectRejectedPresentation(source, duplicateOrdinal);
    _expectRejectedPresentation(source, unordered);
  });

  test('拒绝越界、反向或重叠的交互显示谱且保持旧映射', () {
    final source = interactiveSession();
    final first = source.measures.first;
    final second = source.measures[1];
    final negativeStart = _presentationWithMeasures(source, [
      ScoreMeasureBoundary(
        ordinal: first.ordinal,
        label: first.label,
        startTick: -1,
        endTick: first.endTick,
      ),
      second,
    ]);
    final reversedRange = _presentationWithMeasures(source, [
      ScoreMeasureBoundary(
        ordinal: first.ordinal,
        label: first.label,
        startTick: first.startTick,
        endTick: first.startTick,
      ),
      second,
    ]);
    final beyondSong = _presentationWithMeasures(source, [
      first,
      ScoreMeasureBoundary(
        ordinal: second.ordinal,
        label: second.label,
        startTick: second.startTick,
        endTick: source.songData.totalTicks + 1,
      ),
    ]);
    final overlapping = _presentationWithMeasures(source, [
      first,
      ScoreMeasureBoundary(
        ordinal: second.ordinal,
        label: second.label,
        startTick: first.endTick - 1,
        endTick: second.endTick,
      ),
    ]);

    _expectRejectedPresentation(source, negativeStart);
    _expectRejectedPresentation(source, reversedRange);
    _expectRejectedPresentation(source, beyondSong);
    _expectRejectedPresentation(source, overlapping);
  });
}

ScoreSession _presentationWithMeasures(
  ScoreSession source,
  List<ScoreMeasureBoundary> measures,
) => ScoreSession(
  songData: source.songData,
  musicXml: source.musicXml,
  sourceType: source.sourceType,
  measures: measures,
  mappingStatus: ScoreMappingStatus.complete,
);

void _expectRejectedPresentation(ScoreSession source, ScoreSession candidate) {
  final player = readyPlayer();
  addTearDown(player.dispose);
  final base = ScoreSession.midiOnly(source.songData);
  player.loadScore(base);
  final oldMap = player.measureMap;
  var notifications = 0;
  player.addListener(() => notifications++);

  expect(candidate.hasInteractiveScore, isTrue);
  expect(player.updateScorePresentation(candidate), isFalse);
  expect(notifications, 0);
  expect(player.scoreSession, same(base));
  expect(player.measureMap, same(oldMap));
}

class _PlayerSnapshot {
  final bool sessionSongMatches;
  final bool measureMapSongMatches;
  final bool hasExplicitMeasures;

  const _PlayerSnapshot({
    required this.sessionSongMatches,
    required this.measureMapSongMatches,
    required this.hasExplicitMeasures,
  });

  bool get isConsistent => sessionSongMatches && measureMapSongMatches;

  factory _PlayerSnapshot.capture(
    MidiPlayerController player,
  ) => _PlayerSnapshot(
    sessionSongMatches: identical(
      player.scoreSession?.songData,
      player.songData,
    ),
    measureMapSongMatches: identical(player.measureMap?.song, player.songData),
    hasExplicitMeasures: player.measureMap?.scoreMeasures.isNotEmpty ?? false,
  );
}
