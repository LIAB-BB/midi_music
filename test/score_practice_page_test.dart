import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/core/settings/app_settings.dart';
import 'package:midi_music/models/score_session.dart';
import 'package:midi_music/ui/pages/score_practice_page.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';
import 'package:provider/provider.dart';

import 'helpers/score_renderer_test_fakes.dart';
import 'helpers/score_test_fixtures.dart';

void main() {
  testWidgets('MusicXML 页面只显示五线谱主视图和固定控制栏', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
    expect(find.byKey(const Key('score-transport-bar')), findsOneWidget);
    expect(find.byKey(const Key('pdf-score-viewer')), findsNothing);
    expect(find.byKey(const Key('midi-piano-roll')), findsNothing);
    expect(find.text('真实 MIDI 数据'), findsNothing);
  });

  testWidgets('仅 MIDI 曲目显示仅伴奏但保留播放控制', (tester) async {
    final player = readyPlayer()..loadScore(midiOnlySession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    expect(find.text('仅伴奏'), findsOneWidget);
    expect(find.text('导入对应 MusicXML 以显示可交互乐谱'), findsOneWidget);
    expect(find.byKey(const Key('score-play-pause')), findsOneWidget);
  });

  testWidgets('播放控制和前后小节调用播放器', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    await tester.tap(find.byKey(const Key('score-next-measure')));
    expect(player.currentMeasureOrdinal, 2);
    expect(player.isStopped, isTrue);

    await tester.tap(find.byKey(const Key('score-play-pause')));
    expect(player.isPlaying, isTrue);
    player.stop();
  });

  testWidgets('AB 按钮依次设置 A、B 并在第三次清除', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    player.seekTo(0.25);
    await tester.tap(find.byKey(const Key('score-ab-loop')));
    expect(player.loopStartTime, 0.25);

    player.seekTo(0.75);
    await tester.tap(find.byKey(const Key('score-ab-loop')));
    expect(player.loopEndTime, 0.75);
    expect(player.isLoopEnabled, isTrue);

    await tester.tap(find.byKey(const Key('score-ab-loop')));
    expect(player.loopStartTime, isNull);
    expect(player.loopEndTime, isNull);
  });

  testWidgets('速度菜单使用固定档位并更新播放器', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface));
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25x'));
    await tester.pumpAndSettle();

    expect(player.playbackSpeed, 1.25);
  });

  testWidgets('ready 后播放器小节变化同步谱面高亮', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface));

    expect(surface.port.highlighted, isEmpty);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();
    player.seekToMeasure(2);
    await tester.pump();

    expect(surface.port.highlighted, [2]);
    expect(surface.port.scrollFlags, [isTrue]);
  });

  testWidgets('initialSession 只在页面首帧加载一次', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface));

    player.seekTo(0.75);
    await tester.pumpWidget(_page(player, surface));
    await tester.pump();

    expect(player.currentTime, 0.75);
  });

  testWidgets('复杂反复显示顺序播放提示', (tester) async {
    final base = interactiveSession();
    final session = ScoreSession(
      songData: base.songData,
      musicXml: base.musicXml,
      sourceType: base.sourceType,
      measures: base.measures,
      mappingStatus: base.mappingStatus,
      warnings: {...base.warnings, ScoreWarning.complexRepetition},
    );
    final player = readyPlayer()..loadScore(session);

    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    expect(find.text('此乐谱包含复杂反复，当前按谱面顺序播放。'), findsOneWidget);
  });

  testWidgets('不可映射小节点击显示非阻塞提示', (tester) async {
    final player = readyPlayer()..loadScore(partialSession());
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface));

    surface.emit(const ScoreRendererMessage.ready());
    surface.emit(
      const ScoreRendererMessage.layout(
        complete: true,
        measureRects: [
          ScoreMeasureRect(ordinal: 2, left: 0, top: 0, width: 20, height: 20),
        ],
      ),
    );
    surface.emit(
      const ScoreRendererMessage.gestureEnd(
        x: 10,
        y: 10,
        travel: 0,
        durationMs: 100,
        pointerCount: 1,
      ),
    );
    await tester.pump();

    expect(find.text('谱面与伴奏小节不一致，无法跳转到这一小节。'), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });
}

Widget _page(MidiPlayerController player, _ScoreSurfaceHarness surface) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: player),
      ChangeNotifierProvider(
        create: (_) => AppSettingsController(storage: _MemorySettingsStorage()),
      ),
    ],
    child: CupertinoApp(
      home: ScorePracticePage(
        score: const PracticeScoreMetadata(
          title: 'Interactive Fixture',
          composer: 'Fixture Composer',
          category: '古典',
          level: '中级',
          duration: '1:00',
          saves: '0',
          accent: Color(0xFFA2773F),
          seed: 1,
        ),
        initialSession: player.scoreSession,
        surfaceFactory: surface.create,
      ),
    ),
  );
}

class _ScoreSurfaceHarness {
  final RecordingRendererPort port = RecordingRendererPort();
  late ValueChanged<ScoreRendererMessage> emit;

  ScoreSurface create(ValueChanged<ScoreRendererMessage> onMessage) {
    emit = onMessage;
    return ScoreSurface(port: port, child: const SizedBox());
  }
}

class _MemorySettingsStorage implements AppSettingsStorage {
  Map<String, Object?> values = {};

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    this.values = Map<String, Object?>.from(values);
  }
}
