import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/midi_player_score_playback_adapter.dart';

import 'helpers/score_test_fixtures.dart';

void main() {
  test('播放器适配器原样委托谱面状态与小节跳转', () {
    final player = readyPlayer()..loadScore(interactiveSession());
    addTearDown(player.dispose);
    final adapter = MidiPlayerScorePlaybackAdapter(player);

    expect(adapter.scoreSession, same(player.scoreSession));
    expect(adapter.currentMeasureOrdinal, player.currentMeasureOrdinal);
    expect(adapter.seekToMeasure(2), isTrue);
    expect(adapter.currentMeasureOrdinal, 2);
  });

  test('播放器拒绝的小节不会被适配器绕过', () {
    final player = readyPlayer()..loadScore(partialSession());
    addTearDown(player.dispose);
    final adapter = MidiPlayerScorePlaybackAdapter(player);
    final before = player.currentTime;

    expect(adapter.seekToMeasure(2), isFalse);
    expect(player.currentTime, before);
  });
}
