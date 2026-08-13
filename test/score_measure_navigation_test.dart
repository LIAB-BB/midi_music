import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';

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
