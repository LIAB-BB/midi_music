import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/import/score_import_service.dart';
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
    expect(surface.port.highlighted, [1]);
    expect(surface.port.scrollFlags, [isTrue]);

    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    expect(surface.port.highlighted, [1, 1]);
    expect(surface.port.scrollFlags, [isTrue, isTrue]);
  });

  testWidgets('没有初始会话时首帧不展示全局旧谱', (tester) async {
    final player = readyPlayer()..loadScore(interactiveSession());
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface, initialSession: null));

    expect(surface.createCount, 0);
    expect(find.text('仅伴奏'), findsOneWidget);
  });

  testWidgets('初始会话在首帧创建对应谱面 surface', (tester) async {
    final player = readyPlayer()..loadScore(midiOnlySession());
    final surface = _ScoreSurfaceHarness();
    final session = interactiveSession();

    await tester.pumpWidget(_page(player, surface, initialSession: session));

    expect(surface.createCount, 1);
    expect(surface.port.loadedXml, [session.musicXml]);
    expect(find.text('仅伴奏'), findsNothing);
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

  testWidgets('MusicXML 文件选择异常显示导入失败', (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () => Future<FilePickerResult?>.error(StateError('picker failed')),
    );
    final player = readyPlayer()..loadScore(midiOnlySession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    await tester.tap(find.text('导入 MusicXML'));
    await tester.pumpAndSettle();

    expect(find.text('导入失败'), findsOneWidget);
    expect(find.textContaining('picker failed'), findsOneWidget);
  });

  testWidgets('MusicXML 文件选择未完成时忽略重复导入', (tester) async {
    final pending = Completer<FilePickerResult?>();
    final picker = _FakeFilePicker(() => pending.future);
    FilePicker.platform = picker;
    final player = readyPlayer()..loadScore(midiOnlySession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    await tester.tap(find.text('导入 MusicXML'));
    await tester.tap(find.text('导入 MusicXML'));
    expect(picker.pickCount, 1);

    pending.complete(null);
    await tester.pump();
  });

  testWidgets('手动 MusicXML 成功后延迟内置伴奏不得覆盖', (tester) async {
    const assetPath = 'assets/midi/delayed-fixture.mid';
    final assetGate = Completer<void>();
    final midiBytes = File(
      'assets/midi/Beethoven-Moonlight-Sonata.mid',
    ).readAsBytesSync();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async {
        final key = String.fromCharCodes(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        );
        if (key != assetPath) return null;
        await assetGate.future;
        return ByteData.sublistView(Uint8List.fromList(midiBytes));
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
    });

    final selectedFile = FilePickerResult([
      PlatformFile(
        name: 'interactive_score.musicxml',
        size: 1,
        path: '/tmp/interactive_score.musicxml',
      ),
    ]);
    final picker = _FakeFilePicker(() => SynchronousFuture(selectedFile));
    FilePicker.platform = picker;

    final player = readyPlayer();
    final surface = _ScoreSurfaceHarness();
    final importedSession = interactiveSession();
    await tester.pumpWidget(
      _page(
        player,
        surface,
        initialSession: null,
        assetPath: assetPath,
        importService: _FakeScoreImportService(importedSession),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('导入 MusicXML'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (player.scoreSession?.musicXml != null) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(picker.pickCount, 1);
    expect(find.text('导入失败'), findsNothing);
    expect(find.text('仅伴奏'), findsNothing);
    expect(surface.createCount, greaterThan(0));

    assetGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(player.scoreSession?.musicXml, isNotNull);
    expect(player.scoreSession?.sourceType, ScoreSourceType.musicXml);
    expect(surface.createCount, 1);
    expect(find.text('仅伴奏'), findsNothing);
  });

  testWidgets('核心播放按钮提供动态中文语义', (tester) async {
    final semantics = tester.ensureSemantics();
    final player = readyPlayer()..loadScore(interactiveSession());
    await tester.pumpWidget(_page(player, _ScoreSurfaceHarness()));

    expect(
      tester.getSemantics(find.byKey(const Key('score-previous-measure'))),
      matchesSemantics(label: '上一小节', isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-play-pause'))),
      matchesSemantics(label: '播放', isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-next-measure'))),
      matchesSemantics(label: '下一小节', isButton: true, hasTapAction: true),
    );

    await tester.tap(find.byKey(const Key('score-play-pause')));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('score-play-pause'))),
      matchesSemantics(label: '暂停', isButton: true, hasTapAction: true),
    );
    player.stop();
    semantics.dispose();
  });
}

Widget _page(
  MidiPlayerController player,
  _ScoreSurfaceHarness surface, {
  Object? initialSession = _usePlayerSession,
  String? assetPath,
  ScoreImportService? importService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: player),
      ChangeNotifierProvider(
        create: (_) => AppSettingsController(storage: _MemorySettingsStorage()),
      ),
    ],
    child: CupertinoApp(
      home: ScorePracticePage(
        score: PracticeScoreMetadata(
          title: 'Interactive Fixture',
          composer: 'Fixture Composer',
          category: '古典',
          level: '中级',
          duration: '1:00',
          saves: '0',
          accent: const Color(0xFFA2773F),
          seed: 1,
          assetPath: assetPath,
        ),
        initialSession: identical(initialSession, _usePlayerSession)
            ? player.scoreSession
            : initialSession as ScoreSession?,
        surfaceFactory: surface.create,
        importService: importService,
      ),
    ),
  );
}

const _usePlayerSession = Object();

class _ScoreSurfaceHarness {
  final RecordingRendererPort port = RecordingRendererPort();
  late ValueChanged<ScoreRendererMessage> emit;
  int createCount = 0;

  ScoreSurface create(ValueChanged<ScoreRendererMessage> onMessage) {
    createCount += 1;
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

class _FakeFilePicker extends FilePicker {
  final Future<FilePickerResult?> Function() result;
  int pickCount = 0;

  _FakeFilePicker(this.result);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    pickCount += 1;
    return result();
  }
}

class _FakeScoreImportService extends ScoreImportService {
  final ScoreSession session;

  _FakeScoreImportService(this.session);

  @override
  Future<ScoreSession> importFile(String filePath) =>
      SynchronousFuture<ScoreSession>(session);
}
