# MIDI 自动五线谱与声部选择 Implementation Plan

> **历史状态（2026-08-15）：** 本计划已实施。后续增量还包括 50%–140% OSMD 原生缩放、连续缩放请求合并，以及保留明确 `upper/right hand` 和 `lower/left hand` MIDI 轨道的上/下谱表归属。本文保留为执行记录，当前操作与验收以 `README.md`、`CLAUDE.md` 和 `docs/release_checklist.md` 为准。

> **历史执行说明，禁止重新执行：** 当时曾要求用 subagent-driven-development 逐任务实施；这些步骤现只用于追溯设计与提交，不是待办清单。

**Goal:** 将内置和用户导入的 MIDI 离线生成真实可交互五线谱，默认显示钢琴双谱表，并支持多选声部组成总谱以及全局/单曲默认。

**Architecture:** 原 `MidiSongData` 始终是唯一播放真值；新的 notation 深模块负责轨道分析、默认选择和 MusicXML 生成。生成结果只替换 `ScoreSession` 的显示数据，播放器通过 presentation-only 更新保持时间、速度、AB 循环与播放状态。现有离线 OSMD、`MeasureMap`、小节点击、高亮和自动跟随协议继续复用。

**Tech Stack:** Flutter 3.44.1、Dart 3.12.1、Dart isolate、General MIDI、MusicXML 3.1、OpenSheetMusicDisplay 1.9.9、Provider、Cupertino UI。

## Global Constraints

- 所有生产代码与测试先 RED、再 GREEN；不得先写实现后补测试。
- 不恢复 `_PracticeScorePainter` 假谱、钢琴卷帘或 PDF 主视图。
- MIDI 量化只影响显示；不得重写 `MidiSongData` 或播放事件。
- 有 MIDI 音符时不允许显示“仅伴奏”；转换失败时保留上一份可用谱面并给出错误。
- 钢琴声部始终使用双谱表；多选必须输出同一 MusicXML 总谱。
- 曲目默认优先于全局默认；无有效选择时必须回退，不得生成空谱。
- 运行时离线；不得新增远程渲染脚本、网络请求或隐藏 WebView 导航。
- 轨道名、文件名和 part 名必须 XML 转义；最多处理 64 个有音符轨道和 500,000 个音符。
- 每个任务只暂存本任务文件，使用中文提交信息且不含 AI 署名；用户已授权本计划中的本地子任务提交，不再逐次确认。
- 每个任务结束都运行 focused tests、完整 `flutter test`、`flutter analyze` 和 `git diff --check`；最后再统一运行 iOS build 与真机 QA。

## File Map

### New files

- `lib/models/midi_score_part.dart`：声部类别、谱表模式、目录、选择来源与记谱结果。
- `lib/core/notation/midi_part_analyzer.dart`：轨道名、channel 和 GM program 的确定性声部分析。
- `lib/core/notation/midi_score_selection.dart`：曲目默认、全局默认与安全回退解析。
- `lib/core/notation/midi_to_musicxml_converter.dart`：小节、量化、voice、staff、rest、tie 与 MusicXML 生成。
- `lib/core/notation/midi_notation_service.dart`：面向页面的分析/选择/转换深模块和 isolate 边界。
- `lib/ui/widgets/score_part_picker.dart`：可滚动多选声部面板与默认设置操作。
- `test/midi_part_analyzer_test.dart`
- `test/midi_score_selection_test.dart`
- `test/midi_to_musicxml_converter_test.dart`
- `test/midi_notation_service_test.dart`
- `test/score_part_picker_test.dart`
- `integration_test/midi_notation_render_test.dart`：在真实 WebView 中让 OSMD 渲染生成 XML 的自动化 smoke test。

### Modified files

- `lib/models/score_session.dart`：增加 `midiNotation` 来源、源指纹、选中声部和量化警告。
- `lib/core/settings/app_settings.dart`：schema v3、全局默认类别与单曲选择持久化。
- `lib/core/import/score_import_service.dart`：MIDI 内容指纹。
- `lib/core/midi/midi_player.dart`：presentation-only 会话更新。
- `lib/ui/pages/score_practice_page.dart`：自动转谱、加载态、声部切换和默认保存。
- `lib/ui/widgets/interactive_score_view.dart`：只保留真正无可用源时的文件导入空态。
- `lib/ui/pages/home_page.dart`：内置 MIDI 标为“可生成五线谱”，传稳定资产指纹。
- `test/app_settings_test.dart`
- `test/score_session_test.dart`
- `test/score_measure_navigation_test.dart`
- `test/score_practice_page_test.dart`
- `test/interactive_score_view_test.dart`
- `test/home_score_navigation_test.dart`
- `test/widget_test.dart`
- `pubspec.yaml` / `pubspec.lock`：将已使用的 `crypto` 声明为直接依赖。
- `README.md`、`CLAUDE.md`、`docs/release_checklist.md`：架构、功能和验收同步。

---

### Task 1: 建立可选声部模型与确定性分析

**Files:**
- Create: `lib/models/midi_score_part.dart`
- Create: `lib/core/notation/midi_part_analyzer.dart`
- Create: `test/midi_part_analyzer_test.dart`

**Interfaces:**
- Consumes: `MidiSongData`、稳定曲目指纹。
- Produces: `MidiScoreCatalog`，供 Task 2 的 resolver、Task 3 的 converter 和 Task 6 的选择界面使用。

- [ ] **Step 1: 写声部分类和 K.478 钢琴组合失败测试**

```dart
test('名为 Piano 的单轨多 channel 仍按 channel 和 GM program 分源', () {
  final song = songWithTracks([
    track(0, name: 'Piano', notes: [
      note(channel: 0, number: 60),
      note(channel: 1, number: 67),
      note(channel: 9, number: 36),
    ], programs: {0: 0, 1: 40, 9: 0}),
  ]);
  final parts = MidiPartAnalyzer().analyze(song, fingerprint: 'fixture').parts;

  expect(parts.map((part) => part.kind).toSet(), {
    MidiPartKind.piano, MidiPartKind.strings, MidiPartKind.percussion,
  });
  expect(parts.expand((part) => part.sources)
      .map((source) => source.channels.single), containsAll(<int>[0, 1, 9]));
});

test('多个钢琴轨道合并为稳定的钢琴双谱表', () async {
  final bytes = File('assets/midi/mozart_k478_piano_quartet.mid')
      .readAsBytesSync();
  final song = MidiFileParser().parseBytes(
    bytes, fileName: 'mozart_k478_piano_quartet.mid');
  final catalog = MidiPartAnalyzer().analyze(
    song,
    fingerprint: 'asset:assets/midi/mozart_k478_piano_quartet.mid',
  );

  final piano = catalog.parts.singleWhere((part) => part.kind == MidiPartKind.piano);
  expect(piano.staffMode, MidiStaffMode.grandStaff);
  expect(piano.sources, isNotEmpty);
  expect(catalog.recommendedPartIds, {piano.id});
});
```

- [ ] **Step 2: 运行测试确认类型不存在**

Run: `flutter test test/midi_part_analyzer_test.dart`

Expected: FAIL，缺少 `MidiScorePart` / `MidiPartAnalyzer`。

- [ ] **Step 3: 实现不可变领域模型**

`lib/models/midi_score_part.dart` 定义以下公开 API；集合类型使用 factory + 私有构造器 defensive copy，再用 `Set.unmodifiable` / `List.unmodifiable` 暴露。测试必须在构造后修改原始 list/set 并证明模型不变：

```dart
enum MidiPartKind { piano, strings, woodwind, brass, guitar, bass, percussion, voice, synth, other }
enum MidiStaffMode { grandStaff, singleStaff, percussionStaff }
enum MidiSelectionOrigin { songDefault, globalDefault, automaticPiano, automaticEnsemble, percussionFallback }
enum MidiNotationWarning { rhythmQuantized, unknownInstrument, irregularTimeSignature, densePassage }

class MidiPartSource {
  final int trackIndex;
  final Set<int> channels;
  factory MidiPartSource({required int trackIndex, required Set<int> channels});
  const MidiPartSource._({required this.trackIndex, required this.channels});

  bool contains(int candidateTrackIndex, int channel) =>
      candidateTrackIndex == trackIndex && channels.contains(channel);
}

class MidiScorePart {
  final String id;
  final String label;
  final MidiPartKind kind;
  final List<MidiPartSource> sources;
  final int noteCount;
  final MidiStaffMode staffMode;
  factory MidiScorePart({required String id, required String label,
    required MidiPartKind kind, required List<MidiPartSource> sources,
    required int noteCount, required MidiStaffMode staffMode});
  const MidiScorePart._({required this.id, required this.label,
    required this.kind, required this.sources, required this.noteCount,
    required this.staffMode});
}

class MidiScoreCatalog {
  final String fingerprint;
  final List<MidiScorePart> parts;
  final Set<String> recommendedPartIds;
  final MidiSelectionOrigin recommendedOrigin;
  factory MidiScoreCatalog({required String fingerprint,
    required List<MidiScorePart> parts, required Set<String> recommendedPartIds,
    required MidiSelectionOrigin recommendedOrigin});
  const MidiScoreCatalog._({required this.fingerprint, required this.parts,
    required this.recommendedPartIds, required this.recommendedOrigin});
}
```

- [ ] **Step 4: 实现证据优先的分析器**

`MidiPartAnalyzer.analyze()` 必须先过滤无音符轨道并检查限制，再把每个原轨按 note.channel 切为稳定 `(trackIndex, channel)` source。每个 source 按以下顺序分类：channel 9；仅当该轨实际 note channel 数量等于 1 时使用明确轨道名关键字；否则使用该 channel 的 GM program；最后 `other`。例如名为 `Piano` 的 Format 0 混合轨，program 40 的 channel 仍必须是 strings。所有 piano sources 合成一个 `piano:<sorted track-channel keys>` part；其他来源按 `(kind, trackIndex, channel)` 成为独立 part，ID 为 `source:<track>:<channel>`。converter 后续必须同时按 track 和 channel 过滤，不能选中整轨全部音符。重名 label 用 `（2）`、`（3）` 去重。推荐选择是钢琴；无钢琴时选择全部非打击乐；仅有打击乐时选择全部打击乐。

GM 区间必须至少覆盖：0–7 piano、24–31 guitar、32–39 bass、40–51 strings、56–63 brass、64–79 woodwind、80–103 synth；program 52–54 优先 voice。一个 channel 出现多次 program change 时取首个 note onset 前最后生效的 program；没有时使用 `programByChannel[channel]`。

- [ ] **Step 5: 运行 focused tests 和静态检查**

Run: `dart format lib/models/midi_score_part.dart lib/core/notation/midi_part_analyzer.dart test/midi_part_analyzer_test.dart && flutter test test/midi_part_analyzer_test.dart && flutter analyze && flutter test && git diff --check`

Expected: PASS；`flutter analyze` 无问题。

- [ ] **Step 6: 提交声部模型**

```bash
git add lib/models/midi_score_part.dart lib/core/notation/midi_part_analyzer.dart test/midi_part_analyzer_test.dart
git commit -m "feat: 建立 MIDI 可选声部模型"
```

---

### Task 2: 持久化全局默认与曲目默认

**Files:**
- Create: `lib/core/notation/midi_score_selection.dart`
- Create: `test/midi_score_selection_test.dart`
- Modify: `lib/core/settings/app_settings.dart`
- Modify: `test/app_settings_test.dart`

**Interfaces:**
- Consumes: Task 1 `MidiScoreCatalog`、settings JSON。
- Produces: `MidiScoreSelectionResolver.resolve()` 与 `AppSettingsController` 的默认读写 API。

- [ ] **Step 1: 写优先级、失效 ID 与 schema 迁移失败测试**

```dart
test('曲目默认优先于全局类别且失效 ID 被忽略', () {
  final result = MidiScoreSelectionResolver().resolve(
    catalog,
    songDefaultPartIds: {'missing', 'source:2:0'},
    globalDefaultKinds: {MidiPartKind.piano},
  );
  expect(result.partIds, {'source:2:0'});
  expect(result.origin, MidiSelectionOrigin.songDefault);
});

test('空曲目默认回退为全局、钢琴、非打击乐、打击乐', () {
  expect(resolveWith(global: {MidiPartKind.strings}).origin,
      MidiSelectionOrigin.globalDefault);
  expect(resolveWith(global: {}).origin, MidiSelectionOrigin.automaticPiano);
});

test('谱面声部设置稳定排序并可恢复', () async {
  final storage = MemorySettingsStorage();
  final settings = AppSettingsController(storage: storage);
  settings.setDefaultScorePartKinds({MidiPartKind.strings, MidiPartKind.piano});
  settings.setScorePartSelectionForSong('asset:a.mid', {'z', 'a'});
  await settings.flush();

  expect(storage.values['defaultScorePartKinds'], ['piano', 'strings']);
  expect((storage.values['songScorePartSelections'] as Map)['asset:a.mid'], ['a', 'z']);
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/midi_score_selection_test.dart test/app_settings_test.dart`

Expected: FAIL，resolver 和设置 API 不存在。

- [ ] **Step 3: 实现无状态选择解析器**

```dart
class MidiScoreSelection {
  final Set<String> partIds;
  final MidiSelectionOrigin origin;
  factory MidiScoreSelection({required Set<String> partIds,
    required MidiSelectionOrigin origin});
  const MidiScoreSelection._({required this.partIds, required this.origin});
}

class MidiScoreSelectionResolver {
  MidiScoreSelection resolve(MidiScoreCatalog catalog, {
    Set<String>? songDefaultPartIds,
    required Set<MidiPartKind> globalDefaultKinds,
  });
}
```

解析顺序严格为：有效曲目 ID → 匹配全局 kind → catalog 推荐；始终只返回目录内且 `noteCount > 0` 的 ID，空目录抛出 `StateError('MIDI 中没有可记谱音符')`。

- [ ] **Step 4: 将设置 schema 升至 3**

在 `AppSettingsController` 新增：

```dart
static const defaultScorePartKindsValue = {MidiPartKind.piano};
Set<MidiPartKind> get defaultScorePartKinds;
Set<String>? scorePartSelectionForSong(String fingerprint);
void setDefaultScorePartKinds(Set<MidiPartKind> kinds);
void setScorePartSelectionForSong(String fingerprint, Set<String> partIds);
void clearScorePartSelectionForSong(String fingerprint);
```

`load()` 改为幂等：第一次调用保存 `_loadFuture`，后续调用返回同一个 future；页面可安全 `await settings.load()`，解决 `main.dart` 冷启动 unawaited load 与进页的竞态。读取时只接受 `MidiPartKind.values.byName()` 可识别值；全局集合空或损坏时回退 `{piano}`。单曲 map 最多 100 条，每条最多 64 个非空 ID，按 fingerprint 和 ID 排序写 JSON。`resetToDefaults()` 同时重置全局类别并清空单曲默认。

- [ ] **Step 5: 验证并提交**

Run: `dart format lib/core/notation/midi_score_selection.dart lib/core/settings/app_settings.dart test/midi_score_selection_test.dart test/app_settings_test.dart && flutter test test/midi_score_selection_test.dart test/app_settings_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add lib/core/notation/midi_score_selection.dart lib/core/settings/app_settings.dart test/midi_score_selection_test.dart test/app_settings_test.dart
git commit -m "feat: 持久化谱面声部默认选择"
```

---

### Task 3: 将选中声部转换为可解析 MusicXML

**Files:**
- Modify: `lib/models/midi_score_part.dart`
- Create: `lib/core/notation/midi_to_musicxml_converter.dart`
- Create: `test/midi_to_musicxml_converter_test.dart`
- Create: `integration_test/midi_notation_render_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces:**
- Consumes: `MidiSongData`、`MidiScoreCatalog`、非空 selected IDs。
- Produces: `MidiNotationResult.musicXml`、原 tick 对齐的 `ScoreMeasureBoundary` 和非阻断 warnings。

- [ ] **Step 1: 写真实记谱结构失败测试**

测试必须用合成 MIDI 覆盖：钢琴高低音、同 onset 和弦、跨小节 tie、休止、附点、三连音、拍号变化；并覆盖钢琴+弦乐多选总谱：

```dart
test('钢琴输出双谱表、和弦、休止和跨小节 tie', () {
  final result = MidiToMusicXmlConverter().convertSync(
    pianoSongFixture(), catalog: pianoCatalog,
    selectedPartIds: pianoCatalog.recommendedPartIds,
  );
  expect(result.musicXml, contains('<staves>2</staves>'));
  expect(result.musicXml, contains('<clef number="1">'));
  expect(result.musicXml, contains('<clef number="2">'));
  expect(result.musicXml, contains('<chord/>'));
  expect(result.musicXml, contains('<rest/>'));
  expect(result.musicXml, contains('tie type="start"'));
  expect(result.musicXml, contains('tie type="stop"'));
  expect(MusicXmlParser().parseDocumentString(result.musicXml).mappingStatus,
      ScoreMappingStatus.complete);
});

test('多选声部生成同一总谱且每个 part 的小节数一致', () {
  final result = converter.convertSync(ensembleSong,
      catalog: ensembleCatalog, selectedPartIds: {'piano:0:0', 'source:2:0'});
  expect(RegExp(r'<score-part id=').allMatches(result.musicXml).length, 2);
  expect(measureCountsByPart(result.musicXml).toSet(), {result.measures.length});
});

test('所有生成边界与原 MIDI MeasureMap 完全一致', () {
  final expected = MeasureMap(song: song, tempoMap: TempoMap(
    ticksPerBeat: song.ticksPerBeat, tempoChanges: song.tempoChanges)).measures;
  expect(result.measures.map((m) => (m.startTick, m.endTick)),
      expected.map((m) => (m.startTick, m.endTick)));
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/midi_to_musicxml_converter_test.dart`

Expected: FAIL，转换器不存在。

- [ ] **Step 3: 增加结果模型和严格前置校验**

```dart
class MidiNotationResult {
  final String musicXml;
  final List<ScoreMeasureBoundary> measures;
  final Set<String> selectedPartIds;
  final Set<MidiNotationWarning> warnings;
  factory MidiNotationResult({required String musicXml,
    required List<ScoreMeasureBoundary> measures,
    required Set<String> selectedPartIds,
    required Set<MidiNotationWarning> warnings});
  const MidiNotationResult._({required this.musicXml, required this.measures,
    required this.selectedPartIds, required this.warnings});
}
```

`convertSync()` 检查 selected IDs 均存在、选择非空、有音符轨道不超过 64、总音符不超过 500,000；错误使用明确 `ArgumentError` / `StateError`。

- [ ] **Step 4: 实现小节与记谱事件管线**

实现顺序必须为：

1. 用 `TempoMap + MeasureMap` 产生共享小节列表，并映射为全 interactive 的 `ScoreMeasureBoundary`。
2. 候选显示时值覆盖 1/32 至 whole、单点/双点和 3:2 三连音；起点与时长选择 tick 误差最小者，平局选较简单表示。若最大误差超过 `ticksPerBeat / 48`，加入 `rhythmQuantized`。
3. 先按 selected part 的每个 `MidiPartSource(trackIndex, channels)` 同时过滤 track 与 note.channel；不得把同一 Format 0 原轨中未选 channel 混入。再按 measure 切分跨界音符并写 start/stop tie，并按 onset 合成 chord。
4. 用 greedy interval coloring 分配最多 4 个 voice；第 5 条交错重叠线到来时，把它的 onset 量化到结束最早 voice 的 current end，再截断为 measure 内最短可表示时值并加入 `densePassage`。若 current end 到小节尾连最短可表示时值都没有，则只从显示谱丢弃该音符/和弦并保留 warning；原 MIDI 播放事件绝不删除。不得让同一 voice 产生重叠。测试必须覆盖五路 staggered overlap，以及四个 voice 占满小节而第五条中途进入；验证每个 voice 的 onset 单调、相邻区间不重叠、每个 measure 的 `<backup>`/duration 守恒。
5. 每个 voice 用 rest 补齐从小节起点到首音、音符间空白和小节尾；多个 voice 用 `<backup>` 回到 measure 起点。
6. piano part 输出 `<staves>2</staves>`、G/F 两套 numbered clef；先按和弦平均音高以 middle C 60 分 staff，同一 voice 的相邻和弦在 57–64 区间沿用前一 staff，减少跳动。
7. 非钢琴默认单谱表；bass / 低音 strings 用 F clef，percussion 用 percussion clef 和 `<unpitched>`。
8. 每个 part 输出完全相同的小节数和 `<attributes><divisions>`；拍号只在变化处输出。曲名、part 名与 instrument 名全部 `_escapeXml()`；任一选中 part 为 `other` 时加入 `unknownInstrument`。
9. 输出 `<sound tempo>` 但不把生成 XML 的音符用于播放。

公开 API：

```dart
class MidiToMusicXmlConverter {
  MidiNotationResult convertSync(MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  });
}
```

- [ ] **Step 5: 加入恶意名字、上限和异常拍号测试**

测试 `<Violin & "Lead">` 被转义；65 个有音符 source 和 500,001 音符立即拒绝；中途拍号变化产生 `irregularTimeSignature` 但仍输出一致边界；选择同一 Format 0 轨道中的一个 channel 不得输出其他 channel 音符。

- [ ] **Step 6: 增加真实 OSMD render smoke**

在 `dev_dependencies` 加入 `integration_test: sdk: flutter` 并运行 `flutter pub get`。`integration_test/midi_notation_render_test.dart` 在 iOS simulator/真机创建生产 `InteractiveScoreView`，依次加载包含 dotted/triplet/tie、multi-voice、grand-staff 和 percussion 的生成 MusicXML，等待真实本地 OSMD bridge 发出 `ready` 与非空 `layout`；任何 JS error、空小节矩形或 15 秒超时都失败。该用例在 Task 8 的 iOS 构建后执行；Task 3 先确保它可编译，并保留纯 Dart parser 测试作为快速门禁。

- [ ] **Step 7: 验证并提交**

Run: `flutter pub get && dart format lib/models/midi_score_part.dart lib/core/notation/midi_to_musicxml_converter.dart test/midi_to_musicxml_converter_test.dart integration_test/midi_notation_render_test.dart && flutter test test/midi_to_musicxml_converter_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add pubspec.yaml pubspec.lock lib/models/midi_score_part.dart lib/core/notation/midi_to_musicxml_converter.dart test/midi_to_musicxml_converter_test.dart integration_test/midi_notation_render_test.dart
git commit -m "feat: 离线生成 MIDI 五线谱"
```

---

### Task 4: 建立 isolate 记谱服务与 MIDI 源指纹

**Files:**
- Create: `lib/core/notation/midi_notation_service.dart`
- Create: `test/midi_notation_service_test.dart`
- Modify: `lib/models/score_session.dart`
- Modify: `lib/core/import/score_import_service.dart`
- Modify: `test/score_session_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces:**
- Consumes: Tasks 1–3 与 MIDI 文件 bytes。
- Produces: 页面可注入的 `MidiNotationService`、内容指纹和 `ScoreSourceType.midiNotation`。

- [ ] **Step 1: 写服务、会话和内容指纹失败测试**

```dart
test('MIDI 导入使用内容哈希且路径变化不改变指纹', () async {
  final a = await service.importFile(copyA.path);
  final b = await service.importFile(copyB.path);
  expect(a.sourceFingerprint, startsWith('midi:sha256:'));
  expect(a.sourceFingerprint, b.sourceFingerprint);
});

testWidgets('大 MIDI 解析与哈希期间 UI isolate 仍可响应', (tester) async {
  final future = service.importFile(largeMidi.path);
  await tester.pump(const Duration(milliseconds: 16));
  expect(tickerCount, greaterThan(0));
  await future;
  expect(fileReadCount, 1);
});

test('服务在异步边界分析、解析默认并生成显示会话', () async {
  final prepared = await MidiNotationService().prepare(
    song,
    fingerprint: 'asset:a.mid',
    globalDefaultKinds: {MidiPartKind.piano},
  );
  expect(prepared.catalog.parts, isNotEmpty);
  expect(prepared.session.sourceType, ScoreSourceType.midiNotation);
  expect(prepared.session.songData, same(song));
  expect(prepared.session.hasInteractiveScore, isTrue);
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/midi_notation_service_test.dart test/score_session_test.dart`

- [ ] **Step 3: 扩展 ScoreSession 显示元数据**

`ScoreSourceType` 增加 `midiNotation`；`ScoreSession` 增加可空 `sourceFingerprint`、不可变 `selectedPartIds` 与 `notationWarnings`。factory：

```dart
factory ScoreSession.midiOnly(MidiSongData songData, {String? sourceFingerprint});

ScoreSession asMidiNotation(MidiNotationResult result) => ScoreSession(
  songData: songData,
  musicXml: result.musicXml,
  sourceType: ScoreSourceType.midiNotation,
  measures: result.measures,
  mappingStatus: ScoreMappingStatus.complete,
  sourceFingerprint: sourceFingerprint,
  selectedPartIds: result.selectedPartIds,
  notationWarnings: result.warnings,
);
```

更新所有直接 `ScoreSession(...)` 调用，确保新增字段有安全默认，不破坏 MusicXML/PDF。

- [ ] **Step 4: 实现可注入的深模块**

```dart
class MidiNotationPreparation {
  final MidiScoreCatalog catalog;
  final MidiScoreSelection selection;
  final ScoreSession session;
  factory MidiNotationPreparation({required MidiScoreCatalog catalog,
    required MidiScoreSelection selection, required ScoreSession session});
  const MidiNotationPreparation._({required this.catalog,
    required this.selection, required this.session});
}

abstract interface class MidiNotationBuilder {
  Future<MidiNotationPreparation> prepare(MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  });
  Future<ScoreSession> rebuild(MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  });
}

class MidiNotationService implements MidiNotationBuilder { /* production */ }
```

`prepare()` 通过 `Isolate.run()` 一次完成 analyzer、resolver 和纯 `convertSync()`；`rebuild()` 同样在 isolate 验证 ID 并只重新生成显示结果。结果回到页面后重新绑定原 `MidiSongData` 实例，保证播放器 presentation 更新的 identity 前置条件。测试 fake 实现接口，不为只有一个生产实现增加多余 adapter。

- [ ] **Step 5: 为 MIDI 导入计算 SHA-256**

将 `crypto: ^3.0.7` 声明为直接依赖。`ScoreImportService` 对 MIDI 只读取一次 bytes，再用单个 `Isolate.run()` request 在后台同时执行 `sha256.convert(bytes)` 和 `MidiFileParser.parseBytes()`，写入 `sourceFingerprint: 'midi:sha256:<digest>'`；不得把当前 `MidiFileParser.parseFile()` 的 compute 后台行为退化到 UI isolate。内置资产指纹由页面使用 `asset:<assetPath>`，不读取哈希。

- [ ] **Step 6: 验证并提交**

Run: `flutter pub get && dart format lib/core/notation/midi_notation_service.dart lib/models/score_session.dart lib/core/import/score_import_service.dart test/midi_notation_service_test.dart test/score_session_test.dart && flutter test test/midi_notation_service_test.dart test/score_session_test.dart test/musicxml_import_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add pubspec.yaml pubspec.lock lib/core/notation/midi_notation_service.dart lib/models/score_session.dart lib/core/import/score_import_service.dart test/midi_notation_service_test.dart test/score_session_test.dart
git commit -m "BREAKING: 扩展谱面会话并串联 MIDI 记谱服务"
```

---

### Task 5: 无损替换播放器显示会话

**Files:**
- Modify: `lib/core/midi/midi_player.dart`
- Modify: `test/score_measure_navigation_test.dart`

**Interfaces:**
- Consumes: Task 4 生成且复用同一 `MidiSongData` 的显示会话。
- Produces: `bool updateScorePresentation(ScoreSession session)`。

- [ ] **Step 1: 写播放状态不变失败测试**

```dart
test('替换 MIDI 显示谱不重置播放时间速度循环或播放状态', () {
  final player = readyPlayer();
  final base = ScoreSession.midiOnly(song, sourceFingerprint: 'asset:a.mid');
  player.loadScore(base, songId: 'a');
  player.setSpeed(1.25);
  player.seekTo(2.0);
  player.setLoopRange(start: 1.0, end: 3.0);
  player.setLoopEnabled(enabled: true);
  player.play();

  expect(player.updateScorePresentation(generatedSession), isTrue);
  expect(player.songData, same(song));
  expect(player.currentTime, closeTo(2.0, 0.01));
  expect(player.playbackSpeed, 1.25);
  expect(player.loopStartTime, 1.0);
  expect(player.loopEndTime, 3.0);
  expect(player.isPlaying, isTrue);
});

test('拒绝替换成另一首歌或非交互会话', () {
  expect(player.updateScorePresentation(otherSongSession), isFalse);
  expect(player.updateScorePresentation(ScoreSession.midiOnly(song)), isFalse);
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/score_measure_navigation_test.dart`

- [ ] **Step 3: 实现原子 presentation 更新**

```dart
bool updateScorePresentation(ScoreSession session) {
  if (_isDisposed || !identical(session.songData, _songData) ||
      !session.hasInteractiveScore) return false;
  final nextMap = MeasureMap(
    song: session.songData,
    tempoMap: _tempoMap!,
    scoreMeasures: session.measures,
  );
  _scoreSession = session;
  _measureMap = nextMap;
  _notifyListenersIfActive();
  return true;
}
```

在赋值前完整构造并验证 `nextMap`，只通知一次；不得调用 `_loadSongData()`、`stop()`、`seekTo()` 或修改 loop/speed/state。

- [ ] **Step 4: 验证并提交**

Run: `dart format lib/core/midi/midi_player.dart test/score_measure_navigation_test.dart && flutter test test/score_measure_navigation_test.dart test/midi_player_controller_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add lib/core/midi/midi_player.dart test/score_measure_navigation_test.dart
git commit -m "feat: 无损更新播放器显示谱面"
```

---

### Task 6: 实现多选声部面板和默认操作

**Files:**
- Create: `lib/ui/widgets/score_part_picker.dart`
- Create: `test/score_part_picker_test.dart`

**Interfaces:**
- Consumes: `MidiScoreCatalog`、当前 selection/origin。
- Produces: `ScorePartPickerResult`，页面根据 action 应用或持久化。

- [ ] **Step 1: 写多选、全选/清除、禁用和默认操作失败测试**

```dart
testWidgets('声部面板允许多选组合总谱', (tester) async {
  await tester.pumpWidget(pickerHarness(catalog, selected: {'piano'}));
  await tester.tap(find.text('小提琴'));
  await tester.tap(find.text('应用'));
  expect(result.action, ScorePartPickerAction.apply);
  expect(result.partIds, {'piano', 'violin'});
});

testWidgets('清空后应用禁用且显示至少选择一个提示', (tester) async {
  await tester.tap(find.text('清除'));
  expect(find.text('至少选择一个有音符声部'), findsOneWidget);
  expect(tester.widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '应用')).onPressed,
      isNull);
});

testWidgets('可分别设为本曲默认和全局默认', (tester) async {
  await tester.tap(find.text('设为本曲默认'));
  expect(result.action, ScorePartPickerAction.setSongDefault);
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/score_part_picker_test.dart`

- [ ] **Step 3: 实现 Cupertino 底部多选面板**

公开 API：

```dart
enum ScorePartPickerAction { apply, setSongDefault, setGlobalDefault }
class ScorePartPickerResult {
  final ScorePartPickerAction action;
  final Set<String> partIds;
  factory ScorePartPickerResult({required ScorePartPickerAction action,
    required Set<String> partIds});
  const ScorePartPickerResult._({required this.action, required this.partIds});
}

Future<ScorePartPickerResult?> showScorePartPicker(BuildContext context, {
  required MidiScoreCatalog catalog,
  required Set<String> selectedPartIds,
  required MidiSelectionOrigin origin,
  required Set<MidiNotationWarning> warnings,
});
```

`ScorePartPickerResult` 也使用 factory defensive copy `partIds`。面板使用固定深紫棕底部操作区和米白内容区，不新增配色体系。标题下必须显示 `origin` 对应的当前来源文案：“使用本曲默认”“使用全局默认”“自动选择钢琴”“自动选择非打击乐声部”或“仅打击乐回退”。每项使用真实 `CupertinoIcons.check_mark_circled_solid` / `circle`，显示 label、类别中文名、音符数与谱表说明。顶部含“全选”“清除”，正文可滚动，底部含“应用”“设为本曲默认”“设为全局默认”。所有操作在空选择时禁用；点击结果前复制集合，不能泄露可变 state。

- [ ] **Step 4: 增加横屏、大字号与语义测试**

覆盖 12 个声部、横屏 844×390、textScale 1.8 无 overflow；断言五类来源文案；每一项 `Semantics` label 含“已选择/未选择”，三个提交动作有 button 语义。

- [ ] **Step 5: 验证并提交**

Run: `dart format lib/ui/widgets/score_part_picker.dart test/score_part_picker_test.dart && flutter test test/score_part_picker_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add lib/ui/widgets/score_part_picker.dart test/score_part_picker_test.dart
git commit -m "feat: 增加多选声部与默认设置面板"
```

---

### Task 7: 接入练习页、首页与回归流程

**Files:**
- Modify: `lib/ui/pages/score_practice_page.dart`
- Modify: `lib/ui/widgets/interactive_score_view.dart`
- Modify: `lib/ui/widgets/score_part_picker.dart`
- Modify: `lib/ui/pages/home_page.dart`
- Modify: `test/score_practice_page_test.dart`
- Modify: `test/interactive_score_view_test.dart`
- Modify: `test/score_part_picker_test.dart`
- Modify: `test/home_score_navigation_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: Tasks 1–6 全部接口。
- Produces: 用户可见的 MIDI 自动谱、声部切换、总谱和默认选择完整流程。

- [ ] **Step 1: 写页面自动转谱和竞态失败测试**

必须覆盖：

```dart
testWidgets('内置 MIDI 先显示生成态然后直接显示交互五线谱', (tester) async {
  final builder = ControlledNotationBuilder();
  await pumpPracticePage(tester, metadataWithMidi, notationBuilder: builder);
  expect(find.text('正在生成五线谱'), findsOneWidget);
  expect(find.text('仅伴奏'), findsNothing);
  builder.completePrepare(preparedPianoSession);
  await tester.pump();
  expect(fakeSurface.loadedXml, contains('<staves>2</staves>'));
});

testWidgets('切换声部保持播放状态并在 renderer ready 后同步高亮', (tester) async {
  // 预置 currentTime、1.25x、AB、playing；选择钢琴+弦乐并应用。
  // 断言 player 状态不变、第二份 XML 含两个 part、ready 后 highlight 当前 measure。
});

testWidgets('较早转换结果不会覆盖较新的选择', (tester) async {
  // 连续提交 A、B，先完成 B 再完成 A；最终必须仍显示 B。
});

testWidgets('转换失败保留上一次谱面与选择', (tester) async {
  // rebuild 抛错；断言旧 XML 仍在并出现可读 alert。
});

testWidgets('首次生成失败进入可重试错误态且不泄漏旧曲', (tester) async {
  // prepare 抛错/空音符/超限；断言播放控制仍绑定当前 MIDI，
  // 中央显示“无法生成五线谱”及“重试/导入文件”，不显示旧 XML 或“仅伴奏”。
});

testWidgets('等待冷启动设置加载后才解析已保存默认', (tester) async {
  // storage.load 使用 Completer 延迟；完成前不 prepare，完成后使用本曲默认且只生成一次。
});

testWidgets('首页导入 MIDI 使用内容指纹且只 prepare 一次后显示生成谱',
    (tester) async {
  // import service 返回 midiOnly + midi:sha256 指纹；进入练习页后只 prepare 一次，
  // 显示生成 XML，并让播放器仍播放原 initialSession.songData。
});

testWidgets('首次错误态的导入文件可选择 MIDI 并恢复生成谱', (tester) async {
  // 点击“导入文件”，picker 允许 mid/midi/musicxml/xml/pdf；选择 MIDI 后重新 prepare。
});
```

- [ ] **Step 2: 运行 RED**

Run: `flutter test test/score_practice_page_test.dart test/home_score_navigation_test.dart test/widget_test.dart`

- [ ] **Step 3: 扩展页面注入点和状态机**

`PracticeScoreMetadata` 增加可空 `sourceFingerprint`；内置 factory 使用 `asset:<assetPath>`。`ScorePracticePage` 增加可选 `MidiNotationBuilder notationBuilder`。

页面状态至少包含：`_catalog`、`_selection`、`_displaySession`、`_isGeneratingNotation`、`_notationGeneration`。流程：

1. 初始 session 或 asset MIDI 只对播放器调用一次 `loadScore(midiOnly)` 并设置默认速度。
2. 若 `sourceType == midiOnly`，先 `await settings.load()`（幂等），确认 generation 仍有效后读取曲目/全局默认并调用 `prepare()`；不得在 settings 未 ready 时用内存初始值生成。
3. generation token 命中时用 `player.updateScorePresentation()` 原子替换，再更新 `_displaySession/_catalog/_selection`。
4. `midiNotation` 初始 session 不重复解析；MusicXML/PDF 保持原流程且隐藏“声部”入口。
5. 手动导入入口从 XML-only 扩展为 `mid`、`midi`、`musicxml`、`xml`、`pdf`；MIDI 也走上述转换，MusicXML/PDF 仍直接显示。错误文案统一为“无法导入乐谱文件”，不再限定 MusicXML。
6. `dispose`、快速返回、asset 慢加载和手动导入之间都用 generation guard；旧 future 不得更新 UI。
7. 首次 prepare 失败、空音符或超限进入独立 `_notationError` 状态：保留当前 MIDI 播放与固定控制栏，中央显示“无法生成五线谱”、简短原因、“重试”和“导入文件”；不得显示上一曲、无限 loading 或“仅伴奏”。重试复用同一当前 session 并递增 generation。

- [ ] **Step 4: 接入右上角声部按钮与默认保存**

`_ScorePageActions` 在 `_catalog != null` 时显示 `CupertinoIcons.person_2` 声部按钮和 gear。打开 Task 6 面板后：

- `apply`：rebuild，成功后只更新当前显示。
- `setSongDefault`：先 rebuild 成功，再 `settings.setScorePartSelectionForSong()`。
- `setGlobalDefault`：先 rebuild 成功，再保存所选 parts 的 kind 集合。
- 保存成功显示 2 秒轻提示；失败不写设置。
- rebuild 期间旧谱仍可见，顶部加非阻断 activity indicator；首次生成才显示居中“正在生成五线谱”。
- `notationWarnings` 非空时在谱面顶部显示一行可关闭的米色 warning banner，简短合并“节奏已近似量化 / 未知乐器按独立声部显示 / 拍号变化已截断小节 / 谱面较密集”；面板信息区显示完整逐项说明并有对应 widget tests。

- [ ] **Step 5: 修正空态与首页文案**

`InteractiveScoreView` 在 `musicXml == null` 时文案改为“暂无可显示乐谱 / 导入 MIDI 或 MusicXML”，不再声称 MIDI 只能伴奏；API 名 `onImportMusicXml` 改为 `onImportScore` 并同步测试。首页有 asset 的卡片 badge 改为“可生成五线谱”；无 asset 保持“仅预览”。删除 `_SheetPreviewPainter` 的 seed 五线谱/音符绘制：卡片只使用现有纹理、专辑色块与真实 music-note 图标，不把任何假音符伪装成曲目内容；有无 MIDI 资产都不画 seed 乐谱。首页导入 MIDI 时将 import service 给出的内容指纹随 initial session 带入页面。

- [ ] **Step 6: 更新原有回归断言**

移除所有预期内置 MIDI 出现“仅伴奏”的测试；新增五个内置 MIDI 卡片 badge 数量、卡片树不再包含 `_SheetPreviewPainter`、无资产卡片仍不伪造谱、MusicXML/PDF 不显示声部按钮、file picker 取消/异常恢复、页面首次空 session 不泄漏上一首播放器状态。

- [ ] **Step 7: 验证并提交**

Run: `dart format lib/ui/pages/score_practice_page.dart lib/ui/widgets/interactive_score_view.dart lib/ui/widgets/score_part_picker.dart lib/ui/pages/home_page.dart test/score_practice_page_test.dart test/interactive_score_view_test.dart test/score_part_picker_test.dart test/home_score_navigation_test.dart test/widget_test.dart && flutter test test/score_practice_page_test.dart test/interactive_score_view_test.dart test/score_part_picker_test.dart test/home_score_navigation_test.dart test/widget_test.dart && flutter analyze && flutter test && git diff --check`

```bash
git add lib/ui/pages/score_practice_page.dart lib/ui/widgets/interactive_score_view.dart lib/ui/widgets/score_part_picker.dart lib/ui/pages/home_page.dart test/score_practice_page_test.dart test/interactive_score_view_test.dart test/score_part_picker_test.dart test/home_score_navigation_test.dart test/widget_test.dart
git commit -m "feat: 在练习页接入 MIDI 自动谱与总谱选择"
```

---

### Task 8: 同步文档并完成全量、构建和真机验收

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `docs/release_checklist.md`
- Modify if generated: `ios/Podfile.lock`
- Test: all affected test files and full `test/`

**Interfaces:**
- Consumes: 完整产品行为。
- Produces: 可交接文档、可复现 iOS 构建与 iPhone 14 Pro 验收证据。

- [ ] **Step 1: 更新架构和发布门禁**

README、CLAUDE 和 AGENTS 必须说明：MIDI 自动谱、钢琴双谱表、多选总谱、原 MIDI 为播放真值、全局/单曲默认优先级、`lib/core/notation/` 新模块。release checklist 新增：K.478 默认钢琴、加入/移除弦乐、本曲默认重进、全局默认跨曲、切换前后时间/速度/AB/playing 不变、点击首中末小节。

- [ ] **Step 2: 跑格式、静态检查和完整测试**

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

Expected: format 无未预期改动；analyze 0 issues；全部测试 PASS。

- [ ] **Step 3: 进行 iOS 无签名构建**

Run: `LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 flutter build ios --debug --no-codesign`

Expected: `Built build/ios/iphoneos/Runner.app`。若 pod install 只产生本功能直接依赖的锁文件差异，核实并提交；不得留下 tracked dirty file。

若 `ios/Podfile.lock` 有预期差异，独立提交：

```bash
git add ios/Podfile.lock
git commit -m "build: 锁定 MIDI 记谱 iOS 依赖"
```

- [ ] **Step 4: 在已连接 iPhone 14 Pro 真机验收**

先用 `flutter devices` 确认 iPhone 14 Pro，再运行：

```bash
flutter run -d <iphone-device-id> --debug
```

先运行 `flutter test integration_test/midi_notation_render_test.dart -d <iphone-device-id>`，确认真实 OSMD 接受 dotted/triplet/tie、multi-voice、grand-staff 与 percussion fixture。再按 checklist 验证：K.478 直接出现钢琴双谱表；声部面板可多选弦乐组成总谱；保存本曲默认后重进；保存全局默认后进入另一首 MIDI；切换时播放状态不变；点击首/中/末小节跳转；竖横屏和 1.8x 大字号无溢出。截取至少钢琴双谱表和多声部总谱两个状态。

- [ ] **Step 5: 做截图对照设计 QA**

参考图稳定路径为用户本轮附件 `/var/folders/wt/b1dv1vrj4wb6823gjvtzzml80000gn/T/codex-clipboard-1b397e59-e99f-4b42-8f51-579d5d31a0b3.jpg`。若临时附件已被系统清理，使用本设计文档第 12.2 节的明确视觉约束完成 QA 并在报告注明外部参考不可用，不阻断功能验收。把参考图和真机截图放在同一对照输入中检查：五线谱是否为主视口、是否没有 PDF 黑框/卷帘/MIDI 数据卡、顶栏和固定底栏是否遮挡、字号/边距/背景/图标是否符合现有设计。发现问题先修复、补回归测试、重复截图比较。

- [ ] **Step 6: 最终提交文档与必要修复**

```bash
git add README.md CLAUDE.md AGENTS.md docs/release_checklist.md
git commit -m "docs: 完成 MIDI 五线谱与声部选择验收"
```

若 Task 8 包含 QA 修复，必须使用独立 `fix:` 提交且只暂存对应实现和测试。最终要求 `git status --short` 为空；不要 push、merge 或删除 worktree，等待用户明确授权。
