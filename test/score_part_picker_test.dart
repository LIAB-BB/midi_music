import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/ui/widgets/score_part_picker.dart';

void main() {
  test('ScorePartPickerResult 防御复制声部集合', () {
    final mutablePartIds = <String>{'piano'};
    final result = ScorePartPickerResult(
      action: ScorePartPickerAction.apply,
      partIds: mutablePartIds,
    );

    mutablePartIds.add('violin');

    expect(result.partIds, {'piano'});
    expect(
      () => result.partIds.add('violin'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  testWidgets('入口快照输入集合且外部后续修改不影响面板', (tester) async {
    final selectedPartIds = <String>{'piano'};
    final warnings = <MidiNotationWarning>{MidiNotationWarning.rhythmQuantized};
    ScorePartPickerResult? result;
    await tester.pumpWidget(
      _pickerHarness(
        _catalog(),
        selectedPartIds: selectedPartIds,
        warnings: warnings,
        afterShow: () {
          selectedPartIds
            ..clear()
            ..add('violin');
          warnings
            ..clear()
            ..add(MidiNotationWarning.unknownInstrument);
        },
        onResult: (value) => result = value,
      ),
    );
    await _openPicker(tester);

    expect(
      tester.getSemantics(find.byKey(const Key('score-part-piano'))).label,
      endsWith('已选择'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-part-violin'))).label,
      endsWith('未选择'),
    );
    expect(find.textContaining('部分节奏已对齐到可显示的记谱网格'), findsOneWidget);
    expect(find.textContaining('部分乐器无法识别'), findsNothing);

    warnings
      ..clear()
      ..add(MidiNotationWarning.densePassage);
    selectedPartIds.clear();
    await tester.tap(find.text('小提琴'));
    await tester.pump();

    expect(find.textContaining('部分节奏已对齐到可显示的记谱网格'), findsOneWidget);
    expect(find.textContaining('部分段落声部过密'), findsNothing);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result?.partIds, {'piano', 'violin'});
  });

  testWidgets('声部面板允许多选组合总谱', (tester) async {
    ScorePartPickerResult? result;
    await tester.pumpWidget(
      _pickerHarness(
        _catalog(),
        selectedPartIds: {'piano'},
        onResult: (value) => result = value,
      ),
    );
    await _openPicker(tester);

    await tester.tap(find.text('小提琴'));
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(result?.action, ScorePartPickerAction.apply);
    expect(result?.partIds, {'piano', 'violin'});
  });

  testWidgets('全选只选择有音符声部，清除后全部提交动作禁用', (tester) async {
    await tester.pumpWidget(_pickerHarness(_catalog()));
    await _openPicker(tester);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('score-part-piano'))),
      matchesSemantics(
        label: '钢琴，钢琴，128 个音符，大谱表（高音与低音谱表），已选择',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-part-empty'))),
      matchesSemantics(
        label: '空轨，其他，0 个音符，单谱表，未选择',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );

    await tester.tap(find.text('清除'));
    await tester.pump();

    expect(find.text('至少选择一个有音符声部'), findsOneWidget);
    for (final label in ['应用', '设为本曲默认', '设为全局默认']) {
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, label),
            )
            .onPressed,
        isNull,
      );
    }
  });

  testWidgets('可分别设为本曲默认和全局默认', (tester) async {
    for (final expectation in [
      (label: '设为本曲默认', action: ScorePartPickerAction.setSongDefault),
      (label: '设为全局默认', action: ScorePartPickerAction.setGlobalDefault),
    ]) {
      ScorePartPickerResult? result;
      await tester.pumpWidget(
        _pickerHarness(
          _catalog(),
          selectedPartIds: {'piano'},
          onResult: (value) => result = value,
        ),
      );
      await _openPicker(tester);

      await tester.tap(find.text(expectation.label));
      await tester.pumpAndSettle();

      expect(result?.action, expectation.action);
      expect(result?.partIds, {'piano'});
    }
  });

  testWidgets('标题说明五类当前选择来源', (tester) async {
    const expectedLabels = {
      MidiSelectionOrigin.songDefault: '使用本曲默认',
      MidiSelectionOrigin.globalDefault: '使用全局默认',
      MidiSelectionOrigin.automaticPiano: '自动选择钢琴',
      MidiSelectionOrigin.automaticEnsemble: '自动选择非打击乐声部',
      MidiSelectionOrigin.percussionFallback: '仅打击乐回退',
    };

    for (final entry in expectedLabels.entries) {
      await tester.pumpWidget(
        _pickerHarness(
          _catalog(),
          selectedPartIds: {'piano'},
          origin: entry.key,
        ),
      );
      await _openPicker(tester);

      expect(find.text(entry.value), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('显示 warning 中文详情和声部类别音符数谱表说明', (tester) async {
    await tester.pumpWidget(
      _pickerHarness(
        _catalog(),
        selectedPartIds: {'piano'},
        warnings: MidiNotationWarning.values.toSet(),
      ),
    );
    await _openPicker(tester);

    expect(find.text('钢琴 · 128 个音符 · 大谱表（高音与低音谱表）'), findsOneWidget);
    expect(find.text('弦乐 · 96 个音符 · 单谱表'), findsOneWidget);
    expect(find.text('其他 · 0 个音符 · 单谱表'), findsOneWidget);
    expect(find.text('显示提示'), findsOneWidget);
    expect(find.textContaining('部分节奏已对齐到可显示的记谱网格'), findsOneWidget);
    expect(find.textContaining('部分乐器无法识别'), findsOneWidget);
    expect(find.textContaining('乐曲中途包含拍号变化'), findsOneWidget);
    expect(find.textContaining('部分段落声部过密'), findsOneWidget);
  });

  testWidgets('声部和三个提交动作提供准确语义', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _pickerHarness(_catalog(), selectedPartIds: {'piano'}),
    );
    await _openPicker(tester);

    expect(
      tester.getSemantics(find.byKey(const Key('score-part-piano'))),
      matchesSemantics(
        label: '钢琴，钢琴，128 个音符，大谱表（高音与低音谱表），已选择',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('score-part-violin'))),
      matchesSemantics(
        label: '小提琴，弦乐，96 个音符，单谱表，未选择',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    for (final entry in {
      'score-part-apply': '应用',
      'score-part-song-default': '设为本曲默认',
      'score-part-global-default': '设为全局默认',
    }.entries) {
      expect(
        tester.getSemantics(find.byKey(Key(entry.key))),
        matchesSemantics(
          label: entry.value,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });

  testWidgets('横屏大字号下正文可滚动且底部动作始终可达', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _pickerHarness(
        _largeCatalog(),
        selectedPartIds: {'part-0'},
        textScaler: const TextScaler.linear(1.8),
      ),
    );
    await _openPicker(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('score-part-list')), findsOneWidget);
    expect(find.byKey(const Key('score-part-part-11')), findsNothing);
    expect(find.byKey(const Key('score-part-apply')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('score-part-apply'))).dy,
      lessThan(390),
    );

    await tester.fling(
      find.byKey(const Key('score-part-list')),
      const Offset(0, -2400),
      10000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('score-part-part-11')), findsOneWidget);
    expect(find.byKey(const Key('score-part-apply')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.text('打开声部面板'));
  await tester.pumpAndSettle();
}

Widget _pickerHarness(
  MidiScoreCatalog catalog, {
  Set<String> selectedPartIds = const {},
  MidiSelectionOrigin origin = MidiSelectionOrigin.songDefault,
  Set<MidiNotationWarning> warnings = const {},
  ValueChanged<ScorePartPickerResult?>? onResult,
  VoidCallback? afterShow,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return CupertinoApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Builder(
      builder: (context) => CupertinoPageScaffold(
        child: Center(
          child: CupertinoButton(
            onPressed: () async {
              final resultFuture = showScorePartPicker(
                context,
                catalog: catalog,
                selectedPartIds: selectedPartIds,
                origin: origin,
                warnings: warnings,
              );
              afterShow?.call();
              final result = await resultFuture;
              onResult?.call(result);
            },
            child: const Text('打开声部面板'),
          ),
        ),
      ),
    ),
  );
}

MidiScoreCatalog _catalog() => MidiScoreCatalog(
  fingerprint: 'fixture',
  parts: [
    _part(
      id: 'piano',
      label: '钢琴',
      kind: MidiPartKind.piano,
      noteCount: 128,
      staffMode: MidiStaffMode.grandStaff,
    ),
    _part(
      id: 'violin',
      label: '小提琴',
      kind: MidiPartKind.strings,
      noteCount: 96,
    ),
    _part(id: 'empty', label: '空轨', kind: MidiPartKind.other, noteCount: 0),
  ],
  recommendedPartIds: const {'piano'},
  recommendedOrigin: MidiSelectionOrigin.automaticPiano,
);

MidiScoreCatalog _largeCatalog() => MidiScoreCatalog(
  fingerprint: 'large-fixture',
  parts: [
    for (var index = 0; index < 12; index += 1)
      _part(
        id: 'part-$index',
        label: '声部 ${index + 1}',
        kind: MidiPartKind.values[index % MidiPartKind.values.length],
        noteCount: 100 + index,
        staffMode: index == 9
            ? MidiStaffMode.percussionStaff
            : MidiStaffMode.singleStaff,
      ),
  ],
  recommendedPartIds: const {'part-0'},
  recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
);

MidiScorePart _part({
  required String id,
  required String label,
  required MidiPartKind kind,
  required int noteCount,
  MidiStaffMode staffMode = MidiStaffMode.singleStaff,
}) => MidiScorePart(
  id: id,
  label: label,
  kind: kind,
  sources: const [],
  noteCount: noteCount,
  staffMode: staffMode,
);
