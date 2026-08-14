import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/import/score_import_service.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/notation/midi_notation_service.dart';
import 'package:midi_music/core/notation/midi_score_selection.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/core/settings/app_settings.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
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

  testWidgets('仅 MIDI 曲目显示生成态且保留播放控制', (tester) async {
    final player = readyPlayer()..loadScore(midiOnlySession());
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), notationBuilder: builder),
    );
    await tester.pump();

    expect(find.text('正在生成五线谱'), findsOneWidget);
    expect(find.text('仅伴奏'), findsNothing);
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
    final oldSession = interactiveSession();
    final player = readyPlayer()
      ..loadScore(oldSession)
      ..seekTo(0.75);
    final surface = _ScoreSurfaceHarness();
    await tester.pumpWidget(_page(player, surface, initialSession: null));

    expect(surface.createCount, 0);
    expect(find.text('暂无可显示乐谱'), findsOneWidget);
    expect(player.songData, isNot(same(oldSession.songData)));
    expect(player.currentTime, 0);
  });

  testWidgets('初始会话在首帧创建对应谱面 surface', (tester) async {
    final player = readyPlayer()..loadScore(midiOnlySession());
    final surface = _ScoreSurfaceHarness();
    final session = interactiveSession();

    await tester.pumpWidget(_page(player, surface, initialSession: session));

    expect(surface.createCount, 1);
    expect(surface.port.loadedXml, [session.musicXml]);
    expect(find.text('暂无可显示乐谱'), findsNothing);
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

  testWidgets('内置 MIDI 先显示生成态然后直接显示交互五线谱', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();

    await tester.pumpWidget(
      _page(
        player,
        surface,
        notationBuilder: builder,
        sourceFingerprint: 'asset:fixture.mid',
      ),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);

    expect(find.text('正在生成五线谱'), findsOneWidget);
    expect(find.text('仅伴奏'), findsNothing);
    expect(builder.prepareRequests.single.fingerprint, 'asset:fixture.mid');

    builder.prepareRequests.single.complete(
      _preparation(midiSession.songData, xmlMarker: 'staves-2'),
    );
    await tester.pump();

    expect(surface.port.loadedXml.single, contains('staves-2'));
    expect(player.scoreSession?.sourceType, ScoreSourceType.midiNotation);
    expect(player.scoreSession?.songData, same(midiSession.songData));
  });

  testWidgets('asset 首开只加载一次真实 MIDI 且不经过 empty 会话', (tester) async {
    const assetPath = 'assets/midi/Beethoven-Moonlight-Sonata.mid';
    final player = readyPlayer();
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final observedSongs = <MidiSongData>[];
    player.addListener(() {
      final song = player.songData;
      if (song != null && !observedSongs.any((item) => identical(item, song))) {
        observedSongs.add(song);
      }
    });

    await tester.pumpWidget(
      _page(
        player,
        surface,
        initialSession: null,
        assetPath: assetPath,
        notationBuilder: builder,
      ),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);

    expect(observedSongs, hasLength(1));
    expect(observedSongs.single.totalTicks, greaterThan(0));
    expect(builder.prepareRequests.single.song, same(observedSongs.single));
    expect(builder.prepareRequests.single.fingerprint, 'asset:$assetPath');
  });

  testWidgets('上一曲播放中等待 asset 会立即清空且最终只加载真实资源一次', (tester) async {
    const assetPath = 'assets/midi/delayed-clear-fixture.mid';
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
    final oldSession = interactiveSession();
    final player = readyPlayer()
      ..loadScore(oldSession, songId: 'old-song', filePath: '/tmp/old.mid')
      ..setLoopRange(start: 0.1, end: 0.4)
      ..setLoopEnabled(enabled: true)
      ..play();
    final loadedSongs = <MidiSongData>[];
    player.addListener(() {
      final song = player.songData;
      if (song != null &&
          !identical(song, oldSession.songData) &&
          !loadedSongs.any((item) => identical(item, song))) {
        loadedSongs.add(song);
      }
    });
    final builder = _ControlledNotationBuilder();

    await tester.pumpWidget(
      _page(
        player,
        _ScoreSurfaceHarness(),
        initialSession: null,
        assetPath: assetPath,
        notationBuilder: builder,
      ),
    );
    await tester.pump();

    expect(player.songData, isNull);
    expect(player.scoreSession, isNull);
    expect(player.currentSongId, isNull);
    expect(player.currentFilePath, isNull);
    expect(player.isStopped, isTrue);
    expect(player.isLoopEnabled, isFalse);
    expect(loadedSongs, isEmpty);

    assetGate.complete();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (builder.prepareRequests.isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(loadedSongs, hasLength(1));
    expect(builder.prepareRequests.single.song, same(loadedSongs.single));
    expect(player.songData, same(loadedSongs.single));
  });

  testWidgets('延迟 asset 中导入失败后重试同一路径且旧资源不再落地', (tester) async {
    const assetPath = 'assets/midi/delayed-retry-fixture.mid';
    const importPath = '/tmp/retry-score.musicxml';
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
    FilePicker.platform = _FakeFilePicker(
      () => SynchronousFuture(
        FilePickerResult([
          PlatformFile(name: 'retry-score.musicxml', size: 1, path: importPath),
        ]),
      ),
    );
    final importer = _ControlledScoreImportService();
    final oldSession = interactiveSession();
    final player = readyPlayer()
      ..loadScore(oldSession, songId: 'old-song', filePath: '/tmp/old.mid')
      ..play();
    final surface = _ScoreSurfaceHarness();

    await tester.pumpWidget(
      _page(
        player,
        surface,
        initialSession: null,
        assetPath: assetPath,
        importService: importer,
      ),
    );
    await tester.pump();
    expect(player.songData, isNull);

    await tester.tap(find.text('导入文件'));
    await _pumpUntil(tester, () => importer.paths.isNotEmpty);
    importer.completers.single.completeError(StateError('first import failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('无法生成五线谱'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.tap(find.text('重试'));
    await _pumpUntil(tester, () => importer.paths.length == 2);
    expect(importer.paths, [importPath, importPath]);
    final importedSession = interactiveSession();
    importer.completers[1].complete(importedSession);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(player.scoreSession, same(importedSession));
    expect(player.songData, same(importedSession.songData));
    expect(surface.createCount, 1);

    assetGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(player.scoreSession, same(importedSession));
    expect(player.songData, same(importedSession.songData));
    expect(surface.createCount, 1);
  });

  testWidgets('慢导入一选中路径就使旧 prepare 失效且失败回到可重试终态', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final importer = _ControlledScoreImportService();
    FilePicker.platform = _FakeFilePicker(
      () => SynchronousFuture(
        FilePickerResult([
          PlatformFile(name: 'slow.mid', size: 1, path: '/tmp/slow.mid'),
        ]),
      ),
    );
    await tester.pumpWidget(
      _page(player, surface, notationBuilder: builder, importService: importer),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);

    await tester.tap(find.text('导入文件'));
    await _pumpUntil(tester, () => importer.paths.isNotEmpty);
    builder.prepareRequests.single.complete(
      _preparation(midiSession.songData, xmlMarker: 'stale-before-import'),
    );
    await tester.pump();

    expect(surface.createCount, 0);
    expect(player.songData, same(midiSession.songData));
    expect(find.text('正在生成五线谱'), findsOneWidget);

    importer.completer.completeError(StateError('slow import failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('无法生成五线谱'), findsOneWidget);
    expect(find.textContaining('slow import failed'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('导入文件'), findsOneWidget);
    expect(find.text('正在生成五线谱'), findsNothing);
  });

  testWidgets('切换声部保持播放状态并在 renderer ready 后同步高亮', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final settings = AppSettingsController(storage: _MemorySettingsStorage());
    await tester.pumpWidget(
      _page(player, surface, notationBuilder: builder, settings: settings),
    );
    await _completeInitialNotation(tester, builder, midiSession.songData);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    player
      ..seekTo(0.25)
      ..setSpeed(1.25)
      ..setLoopRange(start: 0.1, end: 0.8)
      ..setLoopEnabled(enabled: true)
      ..play();
    final originalSong = player.songData;

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('应用'));
    await _pumpUntil(tester, () => builder.rebuildRequests.isNotEmpty);
    await tester.pump();

    expect(surface.port.loadedXml.single, contains('initial'));
    expect(find.byKey(const Key('notation-rebuild-progress')), findsOneWidget);
    final timeBeforePresentationSwap = player.currentTime;
    builder.rebuildRequests.single.complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'piano-and-strings',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();

    expect(player.songData, same(originalSong));
    expect(player.currentTime, closeTo(timeBeforePresentationSwap, 0.01));
    expect(player.playbackSpeed, 1.25);
    expect(player.loopStartTime, 0.1);
    expect(player.loopEndTime, 0.8);
    expect(player.isLoopEnabled, isTrue);
    expect(player.isPlaying, isTrue);
    expect(surface.port.loadedXml.last, contains('piano-and-strings'));

    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();
    expect(surface.port.highlighted.last, player.currentMeasureOrdinal);
    player.stop();
  });

  testWidgets('较早转换结果不会覆盖较新的选择', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(_page(player, surface, notationBuilder: builder));
    await _completeInitialNotation(tester, builder, midiSession.songData);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    await _requestViolinRebuild(tester);
    await _requestViolinRebuild(tester);
    expect(builder.rebuildRequests, hasLength(2));

    builder.rebuildRequests[1].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'newer-b',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();
    builder.rebuildRequests[0].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'stale-a',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();

    expect(surface.port.loadedXml.last, contains('newer-b'));
    expect(surface.port.loadedXml.last, isNot(contains('stale-a')));
  });

  testWidgets('转换失败保留上一次谱面与选择', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final settings = AppSettingsController(storage: _MemorySettingsStorage());
    await tester.pumpWidget(
      _page(player, surface, notationBuilder: builder, settings: settings),
    );
    await _completeInitialNotation(tester, builder, midiSession.songData);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('设为本曲默认'));
    await _pumpUntil(tester, () => builder.rebuildRequests.isNotEmpty);
    builder.rebuildRequests.single.completeError(
      StateError('converter failed'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('无法更新五线谱'), findsOneWidget);
    expect(surface.port.loadedXml.last, contains('initial'));
    expect(settings.scorePartSelectionForSong('fixture-fingerprint'), isNull);
    await tester.tap(find.text('好的'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('score-part-violin'))).label,
      endsWith('未选择'),
    );
  });

  testWidgets('本曲与全局默认只在 rebuild 成功后持久化', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final settings = AppSettingsController(storage: _MemorySettingsStorage());
    await tester.pumpWidget(
      _page(player, surface, notationBuilder: builder, settings: settings),
    );
    await _completeInitialNotation(tester, builder, midiSession.songData);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('设为本曲默认'));
    await _pumpUntil(tester, () => builder.rebuildRequests.isNotEmpty);
    expect(settings.scorePartSelectionForSong('fixture-fingerprint'), isNull);

    builder.rebuildRequests.single.complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'song-default',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();
    expect(settings.scorePartSelectionForSong('fixture-fingerprint'), {
      'piano',
      'violin',
    });

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('设为全局默认'));
    await _pumpUntil(tester, () => builder.rebuildRequests.length == 2);
    expect(settings.defaultScorePartKinds, {MidiPartKind.piano});

    builder.rebuildRequests[1].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'global-default',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();
    expect(settings.defaultScorePartKinds, {
      MidiPartKind.piano,
      MidiPartKind.strings,
    });
  });

  testWidgets('首次生成失败进入可重试错误态且不泄漏旧曲', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(interactiveSession());
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(
        player,
        surface,
        initialSession: midiSession,
        notationBuilder: builder,
      ),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);
    builder.prepareRequests.single.completeError(StateError('音符超限'));
    await tester.pump();

    expect(find.text('无法生成五线谱'), findsOneWidget);
    expect(find.textContaining('音符超限'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('导入文件'), findsOneWidget);
    expect(find.text('仅伴奏'), findsNothing);
    expect(surface.createCount, 0);
    expect(player.songData, same(midiSession.songData));
    expect(find.byKey(const Key('score-play-pause')), findsOneWidget);

    await tester.tap(find.text('重试'));
    await _pumpUntil(tester, () => builder.prepareRequests.length == 2);
    expect(builder.prepareRequests[1].song, same(midiSession.songData));
  });

  testWidgets('等待冷启动设置加载后才解析已保存默认', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final builder = _ControlledNotationBuilder();
    final storage = _DelayedSettingsStorage();
    final settings = AppSettingsController(storage: storage);
    await tester.pumpWidget(
      _page(
        player,
        _ScoreSurfaceHarness(),
        notationBuilder: builder,
        sourceFingerprint: 'asset:fixture.mid',
        settings: settings,
      ),
    );
    await tester.pump();

    expect(builder.prepareRequests, isEmpty);
    storage.readCompleter.complete({
      'schemaVersion': 3,
      'defaultScorePartKinds': ['strings'],
      'songScorePartSelections': {
        'asset:fixture.mid': ['violin'],
      },
    });
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);

    expect(builder.prepareRequests, hasLength(1));
    expect(builder.prepareRequests.single.globalDefaultKinds, {
      MidiPartKind.strings,
    });
    expect(builder.prepareRequests.single.songDefaultPartIds, {'violin'});
  });

  testWidgets('首次错误态的导入文件可选择 MIDI 并恢复生成谱', (tester) async {
    final initialMidi = midiOnlySession();
    final importedSong = interactiveSession().songData;
    final importedMidi = ScoreSession.midiOnly(
      importedSong,
      sourceFingerprint: 'midi:sha256:imported',
    );
    final player = readyPlayer()..loadScore(initialMidi);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    final picker = _FakeFilePicker(
      () => SynchronousFuture(
        FilePickerResult([
          PlatformFile(name: 'new.mid', size: 1, path: '/tmp/new.mid'),
        ]),
      ),
    );
    FilePicker.platform = picker;
    await tester.pumpWidget(
      _page(
        player,
        surface,
        initialSession: initialMidi,
        notationBuilder: builder,
        importService: _FakeScoreImportService(importedMidi),
      ),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);
    builder.prepareRequests.single.completeError(StateError('first failed'));
    await tester.pump();

    await tester.tap(find.text('导入文件'));
    await _pumpUntil(tester, () => builder.prepareRequests.length == 2);
    expect(picker.allowedExtensions, ['mid', 'midi', 'musicxml', 'xml', 'pdf']);
    expect(builder.prepareRequests[1].fingerprint, 'midi:sha256:imported');
    expect(player.songData, same(importedSong));

    builder.prepareRequests[1].complete(
      _preparation(importedSong, xmlMarker: 'imported-midi'),
    );
    await tester.pump();
    expect(surface.port.loadedXml.last, contains('imported-midi'));
    expect(find.text('无法生成五线谱'), findsNothing);
  });

  testWidgets('MusicXML 和 PDF 会话不显示声部按钮', (tester) async {
    final musicXml = interactiveSession();
    final pdf = ScoreSession(
      songData: musicXml.songData,
      musicXml: musicXml.musicXml,
      sourceType: ScoreSourceType.pdfOmr,
      measures: musicXml.measures,
      mappingStatus: musicXml.mappingStatus,
    );
    for (final session in [musicXml, pdf]) {
      final player = readyPlayer()..loadScore(session);
      await tester.pumpWidget(
        _page(player, _ScoreSurfaceHarness(), initialSession: session),
      );
      await tester.pump();
      expect(find.byKey(const Key('score-parts')), findsNothing);
    }
  });

  testWidgets('记谱 warning 显示可关闭简短 banner 且面板保留详情', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), notationBuilder: builder),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);
    builder.prepareRequests.single.complete(
      _preparation(
        midiSession.songData,
        xmlMarker: 'warnings',
        warnings: MidiNotationWarning.values.toSet(),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('节奏已近似量化 / 未知乐器按独立声部显示 / 拍号变化已截断小节 / 谱面较密集'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('dismiss-notation-warnings')));
    await tester.pump();
    expect(find.byKey(const Key('notation-warning-banner')), findsNothing);
  });

  testWidgets('生成与首次错误态在横屏大字号下可滚动且操作可达', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(
        player,
        _ScoreSurfaceHarness(),
        notationBuilder: builder,
        textScaler: const TextScaler.linear(1.8),
      ),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('notation-generating-scroll')), findsOneWidget);
    expect(find.text('导入文件'), findsOneWidget);
    expect(tester.getBottomRight(find.text('导入文件')).dy, lessThan(390));

    builder.prepareRequests.single.completeError(StateError('layout failed'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('notation-error-scroll')), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('导入文件'), findsOneWidget);
    await tester.ensureVisible(find.text('重试'));
    await tester.ensureVisible(find.text('导入文件'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('声部、设置和关闭 warning 提供中文语义与 44 点击区', (tester) async {
    final semantics = tester.ensureSemantics();
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), notationBuilder: builder),
    );
    await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);
    builder.prepareRequests.single.complete(
      _preparation(
        midiSession.songData,
        xmlMarker: 'semantics',
        warnings: const {MidiNotationWarning.rhythmQuantized},
      ),
    );
    await tester.pump();

    for (final entry in {
      'score-parts': '选择显示声部',
      'score-settings': '打开设置',
      'dismiss-notation-warnings': '关闭记谱提示',
    }.entries) {
      final finder = find.byKey(Key(entry.key));
      expect(
        tester.getSemantics(finder),
        matchesSemantics(
          label: entry.value,
          isButton: true,
          hasTapAction: true,
        ),
      );
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    semantics.dispose();
  });

  testWidgets('普通应用后面板显示当前临时选择而设为默认后恢复真实来源', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final surface = _ScoreSurfaceHarness();
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(_page(player, surface, notationBuilder: builder));
    await _completeInitialNotation(tester, builder, midiSession.songData);
    surface.emit(const ScoreRendererMessage.ready());
    await tester.pump();

    await _requestViolinRebuild(tester);
    builder.rebuildRequests.single.complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'temporary',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('当前临时选择'), findsOneWidget);
    expect(find.text('自动选择钢琴'), findsNothing);
    await tester.tap(find.text('设为本曲默认'));
    await _pumpUntil(tester, () => builder.rebuildRequests.length == 2);
    builder.rebuildRequests[1].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'saved-default',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('使用本曲默认'), findsOneWidget);
    expect(find.text('当前临时选择'), findsNothing);
  });

  testWidgets('无改动应用及恢复 baseline 后保持真实选择来源', (tester) async {
    final midiSession = midiOnlySession();
    final player = readyPlayer()..loadScore(midiSession);
    final builder = _ControlledNotationBuilder();
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), notationBuilder: builder),
    );
    await _completeInitialNotation(tester, builder, midiSession.songData);

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('应用'));
    await _pumpUntil(tester, () => builder.rebuildRequests.length == 1);
    builder.rebuildRequests[0].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'same-baseline',
        selectedPartIds: {'piano'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('自动选择钢琴'), findsOneWidget);
    expect(find.text('当前临时选择'), findsNothing);
    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('应用'));
    await _pumpUntil(tester, () => builder.rebuildRequests.length == 2);
    builder.rebuildRequests[1].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'temporary-change',
        selectedPartIds: {'piano', 'violin'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('当前临时选择'), findsOneWidget);
    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('应用'));
    await _pumpUntil(tester, () => builder.rebuildRequests.length == 3);
    builder.rebuildRequests[2].complete(
      _notationSession(
        midiSession.songData,
        xmlMarker: 'restored-baseline',
        selectedPartIds: {'piano'},
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('score-parts')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('自动选择钢琴'), findsOneWidget);
    expect(find.text('当前临时选择'), findsNothing);
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
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), initialSession: null),
    );

    await tester.tap(find.text('导入文件'));
    await tester.pumpAndSettle();

    expect(find.text('导入失败'), findsOneWidget);
    expect(find.textContaining('picker failed'), findsOneWidget);
  });

  testWidgets('MusicXML 文件选择未完成时忽略重复导入', (tester) async {
    final pending = Completer<FilePickerResult?>();
    final picker = _FakeFilePicker(() => pending.future);
    FilePicker.platform = picker;
    final player = readyPlayer()..loadScore(midiOnlySession());
    await tester.pumpWidget(
      _page(player, _ScoreSurfaceHarness(), initialSession: null),
    );

    await tester.tap(find.text('导入文件'));
    await tester.tap(find.text('导入文件'));
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

    await tester.tap(find.text('导入文件'));
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
    expect(find.text('暂无可显示乐谱'), findsNothing);
    expect(surface.createCount, greaterThan(0));

    assetGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();

    expect(player.scoreSession?.musicXml, isNotNull);
    expect(player.scoreSession?.sourceType, ScoreSourceType.musicXml);
    expect(surface.createCount, 1);
    expect(find.text('暂无可显示乐谱'), findsNothing);
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
  String? sourceFingerprint,
  ScoreImportService? importService,
  MidiNotationBuilder? notationBuilder,
  AppSettingsController? settings,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: player),
      ChangeNotifierProvider.value(
        value:
            settings ??
            AppSettingsController(storage: _MemorySettingsStorage()),
      ),
    ],
    child: CupertinoApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
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
          sourceFingerprint: sourceFingerprint,
        ),
        initialSession: identical(initialSession, _usePlayerSession)
            ? player.scoreSession
            : initialSession as ScoreSession?,
        surfaceFactory: surface.create,
        importService: importService,
        notationBuilder: notationBuilder,
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
  List<String>? allowedExtensions;

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
    this.allowedExtensions = allowedExtensions;
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

class _ControlledScoreImportService extends ScoreImportService {
  final List<String> paths = [];
  final List<Completer<ScoreSession>> completers = [];

  Completer<ScoreSession> get completer => completers.single;

  @override
  Future<ScoreSession> importFile(String filePath) {
    paths.add(filePath);
    final completer = Completer<ScoreSession>();
    completers.add(completer);
    return completer.future;
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (predicate()) return;
    await tester.pump();
  }
  fail('异步条件未在预期时间内满足');
}

Future<void> _completeInitialNotation(
  WidgetTester tester,
  _ControlledNotationBuilder builder,
  MidiSongData song,
) async {
  await _pumpUntil(tester, () => builder.prepareRequests.isNotEmpty);
  builder.prepareRequests.single.complete(
    _preparation(song, xmlMarker: 'initial'),
  );
  await tester.pump();
}

Future<void> _requestViolinRebuild(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('score-parts')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.ensureVisible(find.text('小提琴'));
  await tester.tap(find.text('小提琴'));
  await tester.ensureVisible(find.text('应用'));
  await tester.tap(find.text('应用'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

MidiNotationPreparation _preparation(
  MidiSongData song, {
  required String xmlMarker,
  Set<MidiNotationWarning> warnings = const {},
}) {
  final catalog = _notationCatalog();
  return MidiNotationPreparation(
    catalog: catalog,
    selection: MidiScoreSelection(
      partIds: const {'piano'},
      origin: MidiSelectionOrigin.automaticPiano,
    ),
    session: _notationSession(
      song,
      xmlMarker: xmlMarker,
      selectedPartIds: const {'piano'},
      warnings: warnings,
    ),
  );
}

ScoreSession _notationSession(
  MidiSongData song, {
  required String xmlMarker,
  required Set<String> selectedPartIds,
  Set<MidiNotationWarning> warnings = const {},
}) {
  final base = interactiveSession();
  return ScoreSession(
    songData: song,
    musicXml: '<score-partwise id="$xmlMarker"/>',
    sourceType: ScoreSourceType.midiNotation,
    measures: base.measures,
    mappingStatus: ScoreMappingStatus.complete,
    sourceFingerprint: 'fixture-fingerprint',
    selectedPartIds: selectedPartIds,
    notationWarnings: warnings,
  );
}

MidiScoreCatalog _notationCatalog() => MidiScoreCatalog(
  fingerprint: 'fixture-fingerprint',
  parts: [
    MidiScorePart(
      id: 'piano',
      label: '钢琴',
      kind: MidiPartKind.piano,
      sources: const [],
      noteCount: 128,
      staffMode: MidiStaffMode.grandStaff,
    ),
    MidiScorePart(
      id: 'violin',
      label: '小提琴',
      kind: MidiPartKind.strings,
      sources: const [],
      noteCount: 96,
      staffMode: MidiStaffMode.singleStaff,
    ),
  ],
  recommendedPartIds: const {'piano'},
  recommendedOrigin: MidiSelectionOrigin.automaticPiano,
);

class _PrepareRequest {
  final MidiSongData song;
  final String fingerprint;
  final Set<MidiPartKind> globalDefaultKinds;
  final Set<String>? songDefaultPartIds;
  final Completer<MidiNotationPreparation> _completer = Completer();

  _PrepareRequest({
    required this.song,
    required this.fingerprint,
    required this.globalDefaultKinds,
    required this.songDefaultPartIds,
  });

  Future<MidiNotationPreparation> get future => _completer.future;

  void complete(MidiNotationPreparation value) => _completer.complete(value);

  void completeError(Object error) => _completer.completeError(error);
}

class _RebuildRequest {
  final MidiSongData song;
  final MidiScoreCatalog catalog;
  final Set<String> selectedPartIds;
  final Completer<ScoreSession> _completer = Completer();

  _RebuildRequest({
    required this.song,
    required this.catalog,
    required this.selectedPartIds,
  });

  Future<ScoreSession> get future => _completer.future;

  void complete(ScoreSession value) => _completer.complete(value);

  void completeError(Object error) => _completer.completeError(error);
}

class _ControlledNotationBuilder implements MidiNotationBuilder {
  final List<_PrepareRequest> prepareRequests = [];
  final List<_RebuildRequest> rebuildRequests = [];

  @override
  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  }) {
    final request = _PrepareRequest(
      song: song,
      fingerprint: fingerprint,
      globalDefaultKinds: Set<MidiPartKind>.of(globalDefaultKinds),
      songDefaultPartIds: songDefaultPartIds == null
          ? null
          : Set<String>.of(songDefaultPartIds),
    );
    prepareRequests.add(request);
    return request.future;
  }

  @override
  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  }) {
    final request = _RebuildRequest(
      song: song,
      catalog: catalog,
      selectedPartIds: Set<String>.of(selectedPartIds),
    );
    rebuildRequests.add(request);
    return request.future;
  }
}

class _DelayedSettingsStorage implements AppSettingsStorage {
  final Completer<Map<String, Object?>> readCompleter = Completer();

  @override
  Future<Map<String, Object?>> read() => readCompleter.future;

  @override
  Future<void> write(Map<String, Object?> values) async {}
}
