import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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
import 'package:midi_music/ui/pages/home_page.dart';
import 'package:midi_music/ui/pages/score_practice_page.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';
import 'package:provider/provider.dart';

import 'helpers/score_renderer_test_fakes.dart';
import 'helpers/score_test_fixtures.dart';

void main() {
  testWidgets('内置 MIDI 卡片显示可生成五线谱且不伪造谱面', (tester) async {
    await tester.pumpWidget(_appWithHome());

    expect(find.text('可生成五线谱'), findsNWidgets(5));
    expect(find.text('仅预览'), findsNWidgets(8));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_SheetPreviewPainter',
      ),
      findsNothing,
    );
    expect(find.textContaining('PDF'), findsNothing);
  });

  testWidgets('首页导入 MIDI 使用内容指纹且只 prepare 一次后显示生成谱', (tester) async {
    final song = midiOnlySession().songData;
    final imported = ScoreSession.midiOnly(
      song,
      sourceFingerprint: 'midi:sha256:abc123',
    );
    final builder = _ImmediateNotationBuilder();
    final player = readyPlayer();
    await tester.pumpWidget(
      _appWithHome(
        player: player,
        picker: _FakeScorePicker(() => SynchronousFuture('/tmp/song.mid')),
        importer: _FakeScoreImportService(session: imported),
        notationBuilder: builder,
      ),
    );

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();

    expect(builder.prepareCount, 1);
    expect(builder.fingerprints, ['midi:sha256:abc123']);
    expect(player.songData, same(song));
    expect(player.scoreSession?.songData, same(song));
    expect(player.scoreSession?.sourceType, ScoreSourceType.midiNotation);
    expect(find.byKey(const Key('fake-score-surface')), findsOneWidget);
  });

  testWidgets('MusicXML 导入后进入交互谱面页且只由该页加载一次', (tester) async {
    final session = interactiveSession();
    final player = readyPlayer();
    final picker = _FakeScorePicker(
      () => SynchronousFuture('/tmp/score.musicxml'),
    );
    final importer = _FakeScoreImportService(session: session);
    var notifyCount = 0;
    player.addListener(() => notifyCount += 1);
    await tester.pumpWidget(
      _appWithHome(player: player, picker: picker, importer: importer),
    );

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();

    expect(find.byType(ScorePracticePage), findsOneWidget);
    expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
    expect(player.scoreSession, same(session));
    expect(player.playbackSpeed, 1.25);
    expect(notifyCount, 2);
    expect(importer.paths, ['/tmp/score.musicxml']);
  });

  testWidgets('文件选择未完成时快速双击只发起一次导入', (tester) async {
    final pending = Completer<String?>();
    final picker = _FakeScorePicker(() => pending.future);
    final importer = _FakeScoreImportService(session: interactiveSession());
    await tester.pumpWidget(_appWithHome(picker: picker, importer: importer));

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.tap(find.byKey(const Key('import-score')));

    expect(picker.pickCount, 1);
    expect(importer.paths, isEmpty);

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-score')), findsOneWidget);
  });

  testWidgets('取消导入后恢复按钮并允许再次选择', (tester) async {
    final picker = _FakeScorePicker(() => SynchronousFuture(null));
    final importer = _FakeScoreImportService(session: interactiveSession());
    await tester.pumpWidget(_appWithHome(picker: picker, importer: importer));

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ScorePracticePage), findsNothing);
    expect(importer.paths, isEmpty);
    expect(find.byKey(const Key('import-score')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();
    expect(picker.pickCount, 2);
  });

  testWidgets('文件选择异常显示错误且关闭后允许重试', (tester) async {
    final picker = _FakeScorePicker(
      () => Future<String?>.error(StateError('picker failed')),
    );
    await tester.pumpWidget(_appWithHome(picker: picker));

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();

    expect(find.text('错误'), findsOneWidget);
    expect(find.textContaining('请确认文件格式有效后重试'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('import-score')), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();
    expect(picker.pickCount, 2);
    expect(find.text('错误'), findsOneWidget);
  });

  testWidgets('导入解析异常沿用可读错误提示并停留在乐库', (tester) async {
    final importer = _FakeScoreImportService(
      error: const FormatException('bad score'),
    );
    await tester.pumpWidget(
      _appWithHome(
        picker: _FakeScorePicker(() => SynchronousFuture('/tmp/bad.musicxml')),
        importer: importer,
      ),
    );

    await tester.tap(find.byKey(const Key('import-score')));
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(ScorePracticePage), findsNothing);
    expect(find.text('错误'), findsOneWidget);
    expect(find.textContaining('文件内容无法解析'), findsOneWidget);
  });
}

Widget _appWithHome({
  MidiPlayerController? player,
  ScoreFilePicker? picker,
  ScoreImportService? importer,
  MidiNotationBuilder? notationBuilder,
}) {
  final settings = AppSettingsController(storage: _MemorySettingsStorage())
    ..setDefaultPlaybackSpeed(1.25);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: player ?? readyPlayer()),
      ChangeNotifierProvider.value(value: settings),
    ],
    child: CupertinoApp(
      home: HomePage(
        filePicker: picker,
        importService: importer,
        practiceSurfaceFactory: _fakeSurface,
        practiceNotationBuilder: notationBuilder,
      ),
    ),
  );
}

ScoreSurface _fakeSurface(ValueChanged<ScoreRendererMessage> onMessage) {
  scheduleMicrotask(() => onMessage(const ScoreRendererMessage.ready()));
  return ScoreSurface(
    port: RecordingRendererPort(),
    child: const SizedBox(key: Key('fake-score-surface')),
  );
}

class _FakeScorePicker implements ScoreFilePicker {
  final Future<String?> Function() result;
  int pickCount = 0;

  _FakeScorePicker(this.result);

  @override
  Future<String?> pickScorePath() {
    pickCount += 1;
    return result();
  }
}

class _FakeScoreImportService extends ScoreImportService {
  final ScoreSession? session;
  final Object? error;
  final List<String> paths = [];

  _FakeScoreImportService({this.session, this.error});

  @override
  Future<ScoreSession> importFile(String filePath) {
    paths.add(filePath);
    final importError = error;
    if (importError != null) return Future<ScoreSession>.error(importError);
    return SynchronousFuture(session!);
  }
}

class _MemorySettingsStorage implements AppSettingsStorage {
  Map<String, Object?> values = {};

  @override
  Future<Map<String, Object?>> read() async => Map.of(values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    this.values = Map.of(values);
  }
}

class _ImmediateNotationBuilder implements MidiNotationBuilder {
  int prepareCount = 0;
  final List<String> fingerprints = [];

  @override
  void cancel() {}

  @override
  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  }) {
    prepareCount += 1;
    fingerprints.add(fingerprint);
    final base = interactiveSession();
    final catalog = MidiScoreCatalog(
      fingerprint: fingerprint,
      parts: [
        MidiScorePart(
          id: 'piano',
          label: '钢琴',
          kind: MidiPartKind.piano,
          sources: const [],
          noteCount: 1,
          staffMode: MidiStaffMode.grandStaff,
        ),
      ],
      recommendedPartIds: const {'piano'},
      recommendedOrigin: MidiSelectionOrigin.automaticPiano,
    );
    return SynchronousFuture(
      MidiNotationPreparation(
        catalog: catalog,
        selection: MidiScoreSelection(
          partIds: const {'piano'},
          origin: MidiSelectionOrigin.automaticPiano,
        ),
        session: ScoreSession(
          songData: song,
          musicXml: '<score-partwise id="generated"/>',
          sourceType: ScoreSourceType.midiNotation,
          measures: base.measures,
          mappingStatus: ScoreMappingStatus.complete,
          sourceFingerprint: fingerprint,
          selectedPartIds: const {'piano'},
        ),
      ),
    );
  }

  @override
  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  }) => throw UnimplementedError();
}
