# 可交互 MusicXML 谱面播放器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将练习页重构为以 MusicXML 五线谱为唯一主视图的离线播放器，并实现小节点击跳转、播放高亮、前后小节、速度与 AB 循环。

**Architecture:** 导入层返回统一的 `ScoreSession`，其中同时保存 MusicXML 原文、播放时间线和真实小节边界；`MidiPlayerController` 基于同一 `MeasureMap` 提供小节导航。OSMD 1.9.9 在本地 WebView 中离线渲染 MusicXML，本地桥接层只上报受校验的小节矩形与点击坐标，Flutter 负责命中判断和所有播放状态变更。

**Tech Stack:** Flutter 3.44.1、Dart 3.12.1、`webview_flutter` 4.14.1、OpenSheetMusicDisplay 1.9.9、WKWebView、现有 MIDI/SoundFont 播放引擎。

## Global Constraints

- iOS 最低版本继续保持 13.6。
- OSMD 1.9.9 必须随 App 离线打包，运行时不得从 CDN 或其他网络地址加载脚本。
- MusicXML 是唯一可交互谱面来源；PDF 只作为 OMR 输入；不得实现 MIDI 自动转谱。
- 点击小节只改变播放位置：播放中继续播放，暂停中保持暂停。
- 仅 MIDI 曲目保留并标注“仅伴奏”，不得展示 PDF 或钢琴卷帘作为替代谱面。
- 无法可靠映射的小节必须禁用点击，不得猜测近似时间。
- 复杂反复第一版按 MusicXML 书写顺序播放并提示用户。
- 只在当前小节变化时更新网页高亮，不按播放帧操作 SVG。
- 所有新行为先写失败测试，再写最小实现。
- 每个提交只暂存本任务列出的文件，不使用 `git add .`，提交信息使用中文且不包含 AI 署名。
- 每个任务到提交步骤时，先展示 `git diff --cached --name-only` 与拟用提交信息，获得用户确认后再提交。

---

## File Map

### New files

- `lib/models/score_session.dart`：统一曲目会话、谱面来源、真实小节边界和映射状态。
- `lib/core/score/score_renderer_protocol.dart`：严格解析并验证 WebView 消息、小节矩形与点击坐标。
- `lib/core/score/score_playback_coordinator.dart`：小节点击、播放高亮和自动跟随的纯 Dart 协调器。
- `lib/ui/widgets/interactive_score_view.dart`：受控 WebView 适配器与 Flutter 谱面组件。
- `lib/ui/widgets/score_transport_bar.dart`：上一小节、播放、下一小节、速度和 AB 循环。
- `assets/score_renderer/index.html`：离线谱面容器。
- `assets/score_renderer/score_bridge.js`：OSMD 渲染、边界上报、高亮和滚动桥；不做播放命中决策。
- `assets/score_renderer/opensheetmusicdisplay.min.js`：固定版本 OSMD 1.9.9。
- `assets/score_renderer/LICENSE`：OSMD BSD-3-Clause 许可证。
- `test/fixtures/interactive_score.musicxml`：含弱起、拍号改变和反复标记的测试谱。
- `test/score_session_test.dart`：导入会话与 MusicXML 小节边界测试。
- `test/score_measure_navigation_test.dart`：播放器小节导航与播放状态测试。
- `test/score_renderer_protocol_test.dart`：桥接消息白名单和数据校验测试。
- `test/score_playback_coordinator_test.dart`：高亮去重、手动滚动和点击协调测试。
- `test/helpers/score_renderer_test_fakes.dart`：桥接与 WebView 组件测试共用的记录型 renderer port。
- `test/interactive_score_view_test.dart`：谱面组件状态和 WebView 适配边界测试。
- `test/score_practice_page_test.dart`：新版页面、仅伴奏和控制栏交互测试。
- `test/helpers/score_test_fixtures.dart`：跨播放器、协调器和页面测试复用的曲目会话与 ready MIDI 引擎。

### Modified files

- `pubspec.yaml` / `pubspec.lock`：加入 WebView 依赖和离线谱面资源。
- `lib/core/import/musicxml_parser.dart`：返回播放数据及真实书写小节边界。
- `lib/core/import/score_import_service.dart`：所有格式统一返回 `ScoreSession`。
- `lib/core/midi/measure_map.dart`：优先使用真实 MusicXML 小节边界，保留 MIDI 推算回退。
- `lib/core/midi/midi_player.dart`：加载会话并公开安全的小节导航 API。
- `lib/ui/pages/score_practice_page.dart`：替换 PDF/卷帘混合页为连续交互谱面。
- `lib/ui/pages/home_page.dart`：导入后进入练习页，内置曲目标记“仅伴奏”。
- `test/musicxml_import_test.dart`：适配统一会话返回值并覆盖 PDF OMR 原文保留。
- `test/widget_test.dart`：更新 App 冒烟断言。
- `README.md`、`docs/release_checklist.md`、`CLAUDE.md`：同步架构和真机验收说明。

### Deliberately retained

- `lib/ui/widgets/midi_piano_roll.dart`、`lib/ui/widgets/pdf_score_viewer.dart` 及 PDF 图片资产暂不删除；它们不再被新版练习页引用，避免把界面重构和仓库资产清理混为同一变更。
- `lib/ui/pages/player_page.dart` 保留 USB MIDI 跟随实现，但不再作为乐谱阅读主界面；后续若恢复入口，应从设置或独立演奏模式进入。

---

### Task 1: 固定离线谱面运行时

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `assets/score_renderer/opensheetmusicdisplay.min.js`
- Create: `assets/score_renderer/LICENSE`
- Test: `test/score_renderer_assets_test.dart`

**Interfaces:**
- Consumes: Flutter asset bundle。
- Produces: `assets/score_renderer/` 资源目录；后续 `InteractiveScoreView` 通过 `loadFlutterAsset()` 加载。

- [ ] **Step 1: 写离线资源失败测试**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OSMD 与许可证随 Flutter asset bundle 打包', () async {
    final script = await rootBundle.loadString(
      'assets/score_renderer/opensheetmusicdisplay.min.js',
    );
    final license = await rootBundle.loadString(
      'assets/score_renderer/LICENSE',
    );

    expect(script, contains('OpenSheetMusicDisplay'));
    expect(license, contains('Copyright 2019 PhonicScore'));
    expect(license, contains('Redistribution and use'));
  });
}
```

- [ ] **Step 2: 运行测试确认缺少资源**

Run: `flutter test test/score_renderer_assets_test.dart`

Expected: FAIL，错误包含 `Unable to load asset`。

- [ ] **Step 3: 固定依赖版本与 asset 目录**

在 `pubspec.yaml` 的 `dependencies` 中加入：

```yaml
  webview_flutter: 4.14.1
```

在 `flutter.assets` 中加入：

```yaml
    - assets/score_renderer/
```

执行：

```bash
flutter pub get
curl -sSLo /private/tmp/opensheetmusicdisplay-1.9.9.tgz \
  https://registry.npmjs.org/opensheetmusicdisplay/-/opensheetmusicdisplay-1.9.9.tgz
openssl dgst -sha256 /private/tmp/opensheetmusicdisplay-1.9.9.tgz
```

Expected SHA-256:

```text
4d24f04508ae9fd5beed87c0db7fb10e5a6630f95cf8bd4473967159d016eb21
```

从已校验包中提取：

```bash
mkdir -p assets/score_renderer
tar -xOf /private/tmp/opensheetmusicdisplay-1.9.9.tgz \
  package/build/opensheetmusicdisplay.min.js \
  > assets/score_renderer/opensheetmusicdisplay.min.js
tar -xOf /private/tmp/opensheetmusicdisplay-1.9.9.tgz \
  package/LICENSE \
  > assets/score_renderer/LICENSE
openssl dgst -sha256 assets/score_renderer/opensheetmusicdisplay.min.js
```

Expected script SHA-256:

```text
658ed444554d43ec66bfb54c72d6833d369e5f93a3a2c06095187cd09a401034
```

- [ ] **Step 4: 运行资源测试**

Run: `flutter test test/score_renderer_assets_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交离线运行时**

```bash
git add pubspec.yaml pubspec.lock assets/score_renderer/opensheetmusicdisplay.min.js assets/score_renderer/LICENSE test/score_renderer_assets_test.dart
git commit -m "build: 固定离线 MusicXML 谱面引擎"
```

---

### Task 2: 建立统一曲目会话与真实小节模型

**Files:**
- Create: `lib/models/score_session.dart`
- Create: `test/fixtures/interactive_score.musicxml`
- Create: `test/score_session_test.dart`
- Modify: `lib/core/import/musicxml_parser.dart`
- Modify: `lib/core/import/score_import_service.dart`
- Modify: `test/musicxml_import_test.dart`

**Interfaces:**
- Consumes: `MidiSongData`、MusicXML 原文、PDF OMR 返回字符串。
- Produces: `ScoreSession`、`ScoreMeasureBoundary`、`MusicXmlParseResult`；Task 3 的 `MeasureMap` 和播放器依赖这些类型。

- [ ] **Step 1: 创建覆盖弱起、拍号变化和复杂反复的 fixture**

`test/fixtures/interactive_score.musicxml` 使用两个书写小节：第 1 小节为 1/4 弱起，第 2 小节切换为 3/4，并在第 2 小节包含 `<repeat direction="backward"/>`。核心内容必须是：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="3.1">
  <work><work-title>Interactive Fixture</work-title></work>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="0" implicit="yes">
      <attributes>
        <divisions>1</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <direction><sound tempo="120"/></direction>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
    <measure number="1">
      <attributes><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>3</duration><type>half</type><dot/></note>
      <barline location="right"><repeat direction="backward"/></barline>
    </measure>
  </part>
</score-partwise>
```

- [ ] **Step 2: 写会话与边界失败测试**

```dart
test('MusicXML 会话保留原文、真实弱起边界和复杂反复警告', () async {
  final xml = File('test/fixtures/interactive_score.musicxml').readAsStringSync();
  final result = MusicXmlParser().parseDocumentString(
    xml,
    fileName: 'interactive_score.musicxml',
  );

  expect(result.musicXml, xml);
  expect(result.measures, [
    const ScoreMeasureBoundary(ordinal: 1, label: '0', startTick: 0, endTick: 480),
    const ScoreMeasureBoundary(ordinal: 2, label: '1', startTick: 480, endTick: 1920),
  ]);
  expect(result.warnings, contains(ScoreWarning.complexRepetition));
});

test('MIDI 导入产生仅伴奏会话', () async {
  final session = await ScoreImportService().importFile('assets/midi/mozart_k545.mid');
  expect(session.sourceType, ScoreSourceType.midiOnly);
  expect(session.musicXml, isNull);
  expect(session.mappingStatus, ScoreMappingStatus.unavailable);
  expect(session.hasInteractiveScore, isFalse);
});

test('PDF OMR 会话保留转换后的 MusicXML', () async {
  final tempDir = await Directory.systemTemp.createTemp('score-session-pdf-');
  addTearDown(() => tempDir.delete(recursive: true));
  final pdfFile = File('${tempDir.path}/fixture.pdf');
  await pdfFile.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
  final service = ScoreImportService(pdfConverter: _FakePdfConverter());
  final session = await service.importFile(pdfFile.path);
  expect(session.sourceType, ScoreSourceType.pdfOmr);
  expect(session.musicXml, _simpleMusicXml);
  expect(session.hasInteractiveScore, isTrue);
});
```

前两个测试写入新建的 `test/score_session_test.dart`；PDF 测试替换 `test/musicxml_import_test.dart` 中现有的“ScoreImportService 可通过 PDF OMR 接口导入 PDF”，从而复用该文件已有的 `_FakePdfConverter` 和 `_simpleMusicXml`，不能把私有测试符号跨文件引用。

- [ ] **Step 3: 运行测试确认新类型和 API 尚不存在**

Run: `flutter test test/score_session_test.dart test/musicxml_import_test.dart`

Expected: FAIL，包含 `ScoreSession` 或 `parseDocumentString` 未定义。

- [ ] **Step 4: 新增统一会话模型**

`lib/models/score_session.dart` 的公共接口固定为：

```dart
import 'midi_track.dart';

enum ScoreSourceType { midiOnly, musicXml, pdfOmr }

enum ScoreMappingStatus { unavailable, complete, partial }

enum ScoreWarning { complexRepetition, inconsistentPartMeasures }

class ScoreMeasureBoundary {
  final int ordinal;
  final String label;
  final int startTick;
  final int endTick;
  final bool isInteractive;

  const ScoreMeasureBoundary({
    required this.ordinal,
    required this.label,
    required this.startTick,
    required this.endTick,
    this.isInteractive = true,
  });

  @override
  bool operator ==(Object other) =>
      other is ScoreMeasureBoundary &&
      ordinal == other.ordinal &&
      label == other.label &&
      startTick == other.startTick &&
      endTick == other.endTick &&
      isInteractive == other.isInteractive;

  @override
  int get hashCode => Object.hash(ordinal, label, startTick, endTick, isInteractive);
}

class ScoreSession {
  final MidiSongData songData;
  final String? musicXml;
  final ScoreSourceType sourceType;
  final List<ScoreMeasureBoundary> measures;
  final ScoreMappingStatus mappingStatus;
  final Set<ScoreWarning> warnings;

  const ScoreSession({
    required this.songData,
    required this.sourceType,
    this.musicXml,
    this.measures = const [],
    required this.mappingStatus,
    this.warnings = const {},
  });

  factory ScoreSession.midiOnly(MidiSongData songData) => ScoreSession(
        songData: songData,
        sourceType: ScoreSourceType.midiOnly,
        mappingStatus: ScoreMappingStatus.unavailable,
      );

  bool get hasInteractiveScore =>
      musicXml != null &&
      musicXml!.trim().isNotEmpty &&
      mappingStatus != ScoreMappingStatus.unavailable &&
      measures.any((measure) => measure.isInteractive);

  bool isMeasureInteractive(int ordinal) => measures.any(
        (measure) => measure.ordinal == ordinal && measure.isInteractive,
      );
}
```

- [ ] **Step 5: 让 MusicXML 解析器同时返回播放数据与真实书写边界**

在 `musicxml_parser.dart` 增加：

```dart
class MusicXmlParseResult {
  final MidiSongData songData;
  final String musicXml;
  final List<ScoreMeasureBoundary> measures;
  final ScoreMappingStatus mappingStatus;
  final Set<ScoreWarning> warnings;

  const MusicXmlParseResult({
    required this.songData,
    required this.musicXml,
    required this.measures,
    required this.mappingStatus,
    required this.warnings,
  });

  ScoreSession toSession(ScoreSourceType sourceType) => ScoreSession(
        songData: songData,
        musicXml: musicXml,
        sourceType: sourceType,
        measures: measures,
        mappingStatus: mappingStatus,
        warnings: warnings,
      );
}
```

保留现有 `parseString()` 返回 `MidiSongData` 的兼容 API，并增加：

```dart
MidiSongData parseString(String xml, {String fileName = 'score.musicxml'}) =>
    parseDocumentString(xml, fileName: fileName).songData;

MusicXmlParseResult parseDocumentString(
  String xml, {
  String fileName = 'score.musicxml',
}) {
  final document = _parseDocument(xml, fileName: fileName);
  final primary = document.parts.first.measures;
  final validated = <ScoreMeasureBoundary>[];
  var hasMismatch = false;
  for (var index = 0; index < primary.length; index++) {
    final measure = primary[index];
    final matchesAllParts = document.parts.every((part) {
      if (index >= part.measures.length) return false;
      final other = part.measures[index];
      return other.startTick == measure.startTick &&
          other.endTick == measure.endTick;
    });
    hasMismatch = hasMismatch || !matchesAllParts;
    validated.add(ScoreMeasureBoundary(
      ordinal: measure.ordinal,
      label: measure.label,
      startTick: measure.startTick,
      endTick: measure.endTick,
      isInteractive: matchesAllParts,
    ));
  }
  hasMismatch = hasMismatch ||
      document.parts.any((part) => part.measures.length != primary.length);
  return MusicXmlParseResult(
    songData: document.songData,
    musicXml: xml,
    measures: validated,
    mappingStatus: validated.isNotEmpty && !hasMismatch
        ? ScoreMappingStatus.complete
        : validated.any((measure) => measure.isInteractive)
            ? ScoreMappingStatus.partial
            : ScoreMappingStatus.unavailable,
    warnings: {
      if (document.hasComplexRepetition) ScoreWarning.complexRepetition,
      if (hasMismatch) ScoreWarning.inconsistentPartMeasures,
    },
  );
}
```

把现有 `parseString()` 主体抽成私有 `_parseDocument()`，返回 `songData`、每个 `_ParsedPart` 和 `hasComplexRepetition`；现有 tempo、track、timeline 构建代码原样迁入，不能再从 `parseDocumentString()` 回调 `parseString()`。新增带属性的 measure 迭代器，并将 `_parsePart` 的外层循环改为：

```dart
final measures = <ScoreMeasureBoundary>[];
var ordinal = 1;
for (final measure in _measureElements(part.body)) {
  final measureStartTick = currentTick;
  var measureEndTick = currentTick;
  previousNoteStartTick = measureStartTick;

  final attributesXml = _firstElement(measure.body, 'attributes');
  if (attributesXml != null) {
    final parsedDivisions = _firstInt(attributesXml, 'divisions');
    if (parsedDivisions != null && parsedDivisions > 0) {
      divisions = parsedDivisions;
    }
    final timeXml = _firstElement(attributesXml, 'time');
    if (timeXml != null) {
      final beats = _firstInt(timeXml, 'beats');
      final beatType = _firstInt(timeXml, 'beat-type');
      if (beats != null && beatType != null) {
        timeSignatureChanges.add(TimeSignatureChange(
          tick: measureStartTick,
          numerator: beats,
          denominator: beatType,
        ));
      }
    }
  }
  for (final directionXml in _elements(measure.body, 'direction')) {
    final tempo = _parseSoundTempo(directionXml);
    if (tempo != null && tempo > 0) {
      tempoChanges.add(TempoChange(
        tick: measureStartTick,
        microsecondsPerBeat: (60000000 / tempo).round(),
      ));
    }
  }
  for (final token in _measurePlaybackTokens(measure.body)) {
    switch (token.name) {
      case 'note':
        final parsedNote = _parseNoteToken(
          token.body,
          divisions: divisions,
          currentTick: currentTick,
          previousNoteStartTick: previousNoteStartTick,
          channel: channel,
        );
        if (parsedNote.note != null) {
          final note = parsedNote.note!;
          notes.add(note);
          maxTick = math.max(maxTick, note.endTick);
          events
            ..add(TimelineEvent(
              type: MidiEventType.noteOn,
              tick: note.startTick,
              channel: channel,
              trackIndex: trackIndex,
              data1: note.noteNumber,
              data2: note.velocity,
            ))
            ..add(TimelineEvent(
              type: MidiEventType.noteOff,
              tick: note.endTick,
              channel: channel,
              trackIndex: trackIndex,
              data1: note.noteNumber,
            ));
          measureEndTick = math.max(measureEndTick, note.endTick);
          previousNoteStartTick = note.startTick;
        }
        currentTick += parsedNote.advanceTick;
        measureEndTick = math.max(measureEndTick, currentTick);
        break;
      case 'backup':
        currentTick = math.max(
          measureStartTick,
          currentTick - _durationToTicks(
            _firstInt(token.body, 'duration') ?? 0,
            divisions,
          ),
        );
        break;
      case 'forward':
        currentTick += _durationToTicks(
          _firstInt(token.body, 'duration') ?? 0,
          divisions,
        );
        measureEndTick = math.max(measureEndTick, currentTick);
        break;
    }
  }

  currentTick = measureEndTick;
  measures.add(ScoreMeasureBoundary(
    ordinal: ordinal,
    label: _attribute(measure.attributes, 'number') ?? '$ordinal',
    startTick: measureStartTick,
    endTick: measureEndTick,
  ));
  ordinal++;
}
```

`_ParsedPart` 增加 `List<ScoreMeasureBoundary> measures` 字段。`_measureElements()` 使用正则 `<measure\b([^>]*)>([\s\S]*?)</measure>` 返回 `_MusicXmlMeasure(attributes, body)`，确保能读取 number 属性。

检测以下元素时加入 `ScoreWarning.complexRepetition`：`<repeat>`、`<ending>`、`<segno>`、`<coda>` 或包含 `D.C.` / `D.S.` 的 direction words。

- [ ] **Step 6: 统一导入服务返回 `ScoreSession`**

`ScoreImportService.importFile` 签名改为：

```dart
Future<ScoreSession> importFile(String filePath)
```

分流结果固定为：

```dart
case '.mid':
case '.midi':
  return ScoreSession.midiOnly(await _midiParser.parseFile(filePath));
case '.xml':
case '.musicxml':
  final xml = await File(filePath).readAsString();
  return _musicXmlParser
      .parseDocumentString(xml, fileName: _fileName(filePath))
      .toSession(ScoreSourceType.musicXml);
case '.pdf':
  final converter = _pdfConverter;
  if (converter == null) {
    throw UnsupportedError(
      'PDF 转 MIDI 需要先通过 OMR 识谱生成 MusicXML；当前尚未配置 PDF 识谱服务。',
    );
  }
  final pdfFile = File(filePath);
  if (!await pdfFile.exists()) {
    throw FileSystemException('PDF file not found', filePath);
  }
  final xml = await converter.convert(pdfFile);
  return _musicXmlParser
      .parseDocumentString(xml, fileName: '${_basenameWithoutExtension(filePath)}.musicxml')
      .toSession(ScoreSourceType.pdfOmr);
```

同时补充私有工具方法，PDF 未配置 OMR 时的现有明确错误文案保持不变：

```dart
String _fileName(String filePath) =>
    filePath.split(Platform.pathSeparator).last;
```

- [ ] **Step 7: 运行导入测试**

Run: `flutter test test/score_session_test.dart test/musicxml_import_test.dart`

Expected: PASS。

- [ ] **Step 8: 提交统一会话**

```bash
git add lib/models/score_session.dart lib/core/import/musicxml_parser.dart lib/core/import/score_import_service.dart test/fixtures/interactive_score.musicxml test/score_session_test.dart test/musicxml_import_test.dart
git commit -m "feat: 保留 MusicXML 谱面与真实小节边界"
```

---

### Task 3: 将真实小节映射接入播放器

**Files:**
- Modify: `lib/core/midi/measure_map.dart`
- Modify: `lib/core/midi/midi_player.dart`
- Create: `test/score_measure_navigation_test.dart`
- Create: `test/helpers/score_test_fixtures.dart`
- Modify: `test/midi_player_controller_test.dart`

**Interfaces:**
- Consumes: `ScoreSession.measures`、`ScoreSession.isMeasureInteractive()`。
- Produces: `MidiPlayerController.loadScore()`、`currentMeasureOrdinal`、`seekToMeasure()`、`seekToPreviousMeasure()`、`seekToNextMeasure()`。

- [ ] **Step 1: 写真实边界和播放状态失败测试**

```dart
testWidgets('真实弱起小节按 MusicXML 边界跳转', (tester) async {
  final player = readyPlayer();
  player.loadScore(interactiveSession());

  expect(player.seekToMeasure(2), isTrue);
  expect(player.currentTime, closeTo(0.5, 0.0001));
  expect(player.currentMeasureOrdinal, 2);
});

testWidgets('小节跳转保持播放和暂停状态', (tester) async {
  final player = readyPlayer()..loadScore(interactiveSession());

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
  player.seekTo(0.25);

  expect(player.seekToMeasure(2), isFalse);
  expect(player.seekToMeasure(99), isFalse);
  expect(player.currentTime, 0.25);
});
```

将本计划后续测试中的公开辅助函数 `readyPlayer()`、`interactiveSession()`、`partialSession()` 和 `midiOnlySession()` 统一定义在 `test/helpers/score_test_fixtures.dart`。会话由 `MusicXmlParser().parseDocumentString()` 解析 `test/fixtures/interactive_score.musicxml` 得到；partial 版本复制会话并把第 2 个 `ScoreMeasureBoundary.isInteractive` 设为 false；MIDI-only 版本使用 `ScoreSession.midiOnly(interactive.songData)`。文件内私有的 `_ReadyMidiPlaybackEngine implements MidiPlaybackEngine` 的 `isReady` 固定为 true，其余异步方法返回已完成 `Future<void>`；`readyPlayer()` 返回注入该引擎的 `MidiPlayerController`。各测试在 `addTearDown(player.dispose)` 注册释放，避免播放测试遗留 ticker。

- [ ] **Step 2: 运行测试确认播放器尚无会话导航 API**

Run: `flutter test test/score_measure_navigation_test.dart`

Expected: FAIL，包含 `loadScore` 或 `seekToMeasure` 未定义。

- [ ] **Step 3: 让 `MeasureMap` 支持显式小节边界**

构造函数改为：

```dart
final List<ScoreMeasureBoundary> scoreMeasures;

MeasureMap({
  required this.song,
  required this.tempoMap,
  this.scoreMeasures = const [],
});
```

`_buildMeasures()` 在 `scoreMeasures.isNotEmpty` 时先走：

```dart
return scoreMeasures.map((boundary) {
  return MeasureInfo(
    number: boundary.ordinal,
    label: boundary.label,
    startTick: boundary.startTick,
    endTick: boundary.endTick,
    startTime: tempoMap.tickToSeconds(boundary.startTick),
    endTime: tempoMap.tickToSeconds(boundary.endTick),
    numerator: _signatureAt(boundary.startTick).numerator,
    denominator: _signatureAt(boundary.startTick).denominator,
    isInteractive: boundary.isInteractive,
  );
}).toList(growable: false);
```

给 `MeasureInfo` 增加 `label` 与 `isInteractive`。新增安全查询，禁止现有 clamp 行为把非法小节悄悄映射到首尾：

```dart
double? tryMeasureToTime(int ordinal) {
  for (final measure in _measures) {
    if (measure.number == ordinal && measure.isInteractive) {
      return measure.startTime;
    }
  }
  return null;
}

int? previousInteractiveOrdinal(int ordinal) {
  for (var index = _measures.length - 1; index >= 0; index--) {
    final measure = _measures[index];
    if (measure.number < ordinal && measure.isInteractive) return measure.number;
  }
  return null;
}

int? nextInteractiveOrdinal(int ordinal) {
  for (final measure in _measures) {
    if (measure.number > ordinal && measure.isInteractive) return measure.number;
  }
  return null;
}
```

现有 MIDI-only 调用继续使用推算边界，行为不变。

- [ ] **Step 4: 播放器加载 `ScoreSession` 并公开小节 API**

在 `MidiPlayerController` 增加：

```dart
ScoreSession? _scoreSession;
MeasureMap? _measureMap;

ScoreSession? get scoreSession => _scoreSession;
MeasureMap? get measureMap => _measureMap;

int? get currentMeasureOrdinal {
  final map = _measureMap;
  if (map == null || _songData == null) return null;
  return map.timeToMeasureBeat(_currentTime).measureNumber;
}

void loadScore(ScoreSession session, {String? songId, String? filePath}) {
  _scoreSession = session;
  loadSong(session.songData, songId: songId, filePath: filePath);
  _measureMap = MeasureMap(
    song: session.songData,
    tempoMap: _tempoMap!,
    scoreMeasures: session.measures,
  );
  _notifyListenersIfActive();
}

bool seekToMeasure(int ordinal) {
  final seconds = _measureMap?.tryMeasureToTime(ordinal);
  if (seconds == null) return false;
  seekTo(seconds);
  return true;
}

bool seekToPreviousMeasure() {
  final current = currentMeasureOrdinal;
  final previous = current == null
      ? null
      : _measureMap?.previousInteractiveOrdinal(current);
  return previous != null && seekToMeasure(previous);
}

bool seekToNextMeasure() {
  final current = currentMeasureOrdinal;
  final next = current == null
      ? null
      : _measureMap?.nextInteractiveOrdinal(current);
  return next != null && seekToMeasure(next);
}
```

`loadSong()` 必须保持兼容：外部直接加载 MIDI 时设置 `_scoreSession = ScoreSession.midiOnly(song)`，并建立推算型 `MeasureMap`。为避免 `loadScore()` 被 `loadSong()` 覆盖，可将原实现抽到私有 `_loadSongData()`，两个公共入口分别设置会话后调用它。

- [ ] **Step 5: 运行导航与播放器回归测试**

Run: `flutter test test/score_measure_navigation_test.dart test/midi_player_controller_test.dart test/tempo_map_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交小节导航**

```bash
git add lib/core/midi/measure_map.dart lib/core/midi/midi_player.dart test/helpers/score_test_fixtures.dart test/score_measure_navigation_test.dart test/midi_player_controller_test.dart
git commit -m "feat: 接入真实小节播放导航"
```

---

### Task 4: 定义受控谱面消息协议与播放协调器

**Files:**
- Create: `lib/core/score/score_renderer_protocol.dart`
- Create: `lib/core/score/score_playback_coordinator.dart`
- Create: `test/helpers/score_renderer_test_fakes.dart`
- Create: `test/score_renderer_protocol_test.dart`
- Create: `test/score_playback_coordinator_test.dart`

**Interfaces:**
- Consumes: JSON 字符串、`MidiPlayerController`、`ScoreSession`。
- Produces: `ScoreMeasureRect`、`ScoreRendererMessage.parse()`、`ScoreRendererPort`、`ScoreMessageHandlingResult`、`ScorePlaybackCoordinator.handleMessage()`。

- [ ] **Step 1: 写协议白名单失败测试**

```dart
test('只接受已知消息与有限手势数据', () {
  final message = ScoreRendererMessage.parse(
    '{"type":"gestureEnd","x":120.5,"y":240,'
    '"travel":4,"durationMs":120,"pointerCount":1}',
  );
  expect(message.type, ScoreRendererMessageType.gestureEnd);
  expect(message.tapX, 120.5);
  expect(message.tapY, 240);
  expect(
    () => ScoreRendererMessage.parse(
      '{"type":"gestureEnd","x":-1,"y":20,'
      '"travel":4,"durationMs":120,"pointerCount":1}',
    ),
    throwsFormatException,
  );
  expect(
    () => ScoreRendererMessage.parse('{"type":"navigate","url":"https://x"}'),
    throwsFormatException,
  );
});

test('布局消息返回经校验的小节矩形', () {
  final message = ScoreRendererMessage.parse(
    '{"type":"layout","complete":true,"measures":['
    '{"ordinal":1,"left":10,"top":20,"width":100,"height":80}] }',
  );
  expect(message.layoutComplete, isTrue);
  expect(message.measureRects, const [
    ScoreMeasureRect(
      ordinal: 1,
      left: 10,
      top: 20,
      width: 100,
      height: 80,
    ),
  ]);
});

test('错误消息长度与文本受限', () {
  final message = ScoreRendererMessage.parse(
    '{"type":"error","message":"bad score"}',
  );
  expect(message.errorMessage, 'bad score');
  expect(
    () => ScoreRendererMessage.parse(
      jsonEncode({
        'type': 'error',
        'message': List<String>.filled(501, 'x').join(),
      }),
    ),
    throwsFormatException,
  );
});
```

- [ ] **Step 2: 写协调器失败测试**

```dart
test('Flutter 用上报矩形命中点击并调用统一播放器跳转', () {
  final port = RecordingRendererPort();
  final player = readyPlayer()..loadScore(interactiveSession());
  final coordinator = ScorePlaybackCoordinator(player: player, port: port);

  coordinator.handleMessage(const ScoreRendererMessage.layout(
    complete: true,
    measureRects: [
      ScoreMeasureRect(ordinal: 2, left: 0, top: 100, width: 200, height: 80),
    ],
  ));
  expect(
    coordinator.handleMessage(const ScoreRendererMessage.gestureEnd(
      x: 50,
      y: 120,
      travel: 4,
      durationMs: 120,
      pointerCount: 1,
    )),
    ScoreMessageHandlingResult.handled,
  );

  expect(player.currentMeasureOrdinal, 2);
});

test('不可映射的小节点击向页面返回失败', () {
  final port = RecordingRendererPort();
  final player = readyPlayer()..loadScore(partialSession());
  final coordinator = ScorePlaybackCoordinator(player: player, port: port);

  coordinator.handleMessage(const ScoreRendererMessage.layout(
    complete: true,
    measureRects: [
      ScoreMeasureRect(ordinal: 2, left: 0, top: 100, width: 200, height: 80),
    ],
  ));
  expect(
    coordinator.handleMessage(const ScoreRendererMessage.gestureEnd(
      x: 50,
      y: 120,
      travel: 4,
      durationMs: 120,
      pointerCount: 1,
    )),
    ScoreMessageHandlingResult.unmappableMeasure,
  );
  expect(player.currentMeasureOrdinal, 1);
});

test('相同小节不会重复发送高亮', () async {
  final port = RecordingRendererPort();
  final player = readyPlayer()..loadScore(interactiveSession());
  final coordinator = ScorePlaybackCoordinator(player: player, port: port);

  coordinator.syncFromPlayer();
  coordinator.syncFromPlayer();

  expect(port.highlighted, [1]);
});

test('手动浏览暂停自动滚动，恢复跟随后重新滚动', () {
  final port = RecordingRendererPort();
  final player = readyPlayer()..loadScore(interactiveSession());
  final coordinator = ScorePlaybackCoordinator(player: player, port: port);

  coordinator.handleMessage(const ScoreRendererMessage.gestureEnd(
    x: 50,
    y: 120,
    travel: 40,
    durationMs: 300,
    pointerCount: 1,
  ));
  player.seekToMeasure(2);
  coordinator.syncFromPlayer();
  expect(port.scrollFlags.last, isFalse);

  coordinator.resumeAutoFollow();
  coordinator.syncFromPlayer(force: true);
  expect(port.scrollFlags.last, isTrue);
});
```

`test/helpers/score_renderer_test_fakes.dart` 新增公开的 `RecordingRendererPort implements ScoreRendererPort`：`loadMusicXml()` 把原文加入 `loadedXml`，`highlightMeasure()` 分别把 ordinal 和 `scrollIntoView` 加入 `highlighted`、`scrollFlags`，`clearHighlight()` 递增 `clearCount`；所有方法返回完成的 `Future<void>`。Task 4 和 Task 5 测试只复用这个公开 fake。

- [ ] **Step 3: 运行测试确认协议和协调器缺失**

Run: `flutter test test/score_renderer_protocol_test.dart test/score_playback_coordinator_test.dart`

Expected: FAIL，包含目标类型未定义。

- [ ] **Step 4: 实现严格消息协议**

公共类型固定为：

```dart
enum ScoreRendererMessageType { ready, layout, gestureEnd, error }

class ScoreMeasureRect {
  final int ordinal;
  final double left;
  final double top;
  final double width;
  final double height;

  const ScoreMeasureRect({
    required this.ordinal,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  bool contains(double x, double y) =>
      x >= left && x <= left + width && y >= top && y <= top + height;

  @override
  bool operator ==(Object other) =>
      other is ScoreMeasureRect &&
      ordinal == other.ordinal &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(ordinal, left, top, width, height);
}

class ScoreRendererMessage {
  final ScoreRendererMessageType type;
  final double? tapX;
  final double? tapY;
  final double gestureTravel;
  final int gestureDurationMs;
  final int gesturePointerCount;
  final List<ScoreMeasureRect> measureRects;
  final String? errorMessage;
  final bool layoutComplete;

  const ScoreRendererMessage._(
    this.type, {
    this.tapX,
    this.tapY,
    this.gestureTravel = 0,
    this.gestureDurationMs = 0,
    this.gesturePointerCount = 0,
    this.measureRects = const [],
    this.errorMessage,
    this.layoutComplete = false,
  });

  const ScoreRendererMessage.gestureEnd({
    required double x,
    required double y,
    required double travel,
    required int durationMs,
    required int pointerCount,
  }) : this._(
         ScoreRendererMessageType.gestureEnd,
         tapX: x,
         tapY: y,
         gestureTravel: travel,
         gestureDurationMs: durationMs,
         gesturePointerCount: pointerCount,
       );
  const ScoreRendererMessage.ready()
      : this._(ScoreRendererMessageType.ready);
  const ScoreRendererMessage.layout({
    required bool complete,
    required List<ScoreMeasureRect> measureRects,
  }) : this._(
         ScoreRendererMessageType.layout,
         layoutComplete: complete,
         measureRects: measureRects,
       );
  const ScoreRendererMessage.error(String message)
      : this._(ScoreRendererMessageType.error, errorMessage: message);

  static ScoreRendererMessage parse(String raw) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Renderer message too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Renderer message must be an object');
    final json = Map<String, Object?>.from(decoded);
    return switch (json['type']) {
      'ready' => const ScoreRendererMessage.ready(),
      'layout' => _parseLayout(json),
      'gestureEnd' => _parseGestureEnd(json),
      'error' => _parseError(json['message']),
      _ => throw const FormatException('Unknown renderer message'),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ScoreRendererMessage &&
      type == other.type &&
      tapX == other.tapX &&
      tapY == other.tapY &&
      gestureTravel == other.gestureTravel &&
      gestureDurationMs == other.gestureDurationMs &&
      gesturePointerCount == other.gesturePointerCount &&
      listEquals(measureRects, other.measureRects) &&
      errorMessage == other.errorMessage &&
      layoutComplete == other.layoutComplete;

  @override
  int get hashCode => Object.hash(
        type,
        tapX,
        tapY,
        gestureTravel,
        gestureDurationMs,
        gesturePointerCount,
        Object.hashAll(measureRects),
        errorMessage,
        layoutComplete,
      );
}
```

`_parseGestureEnd` 只接受有限数值：`x/y/travel` 范围为 `0..10000000`，`durationMs` 为 `int 0..60000`，`pointerCount` 为 `int 1..10`。`_parseLayout` 只接受最多 10000 个矩形；ordinal 必须为不重复的 `int 1..100000`，left/top 为有限非负数，width/height 为 `(0, 10000000]`。错误文本只接受非空字符串且长度不超过 500。

- [ ] **Step 5: 实现播放协调器**

```dart
abstract class ScoreRendererPort {
  Future<void> loadMusicXml(String musicXml);
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView});
  Future<void> clearHighlight();
}

enum ScoreMessageHandlingResult { handled, ignored, unmappableMeasure }

class ScorePlaybackCoordinator {
  final MidiPlayerController player;
  final ScoreRendererPort port;
  int? _lastHighlightedOrdinal;
  bool _autoFollow = true;
  List<ScoreMeasureRect> _measureRects = const [];

  ScorePlaybackCoordinator({required this.player, required this.port});

  ScoreMessageHandlingResult handleMessage(ScoreRendererMessage message) {
    switch (message.type) {
      case ScoreRendererMessageType.layout:
        _measureRects = message.measureRects;
        return ScoreMessageHandlingResult.handled;
      case ScoreRendererMessageType.gestureEnd:
        final isTap = message.gesturePointerCount == 1 &&
            message.gestureTravel <= 10 &&
            message.gestureDurationMs <= 350;
        if (!isTap) {
          _autoFollow = false;
          return ScoreMessageHandlingResult.handled;
        }
        ScoreMeasureRect? hit;
        for (final rect in _measureRects) {
          if (rect.contains(message.tapX!, message.tapY!)) {
            hit = rect;
            break;
          }
        }
        if (hit == null) return ScoreMessageHandlingResult.ignored;
        final ordinal = hit.ordinal;
        final session = player.scoreSession;
        if (session != null &&
            session.isMeasureInteractive(ordinal) &&
            player.seekToMeasure(ordinal)) {
          syncFromPlayer(force: true);
          return ScoreMessageHandlingResult.handled;
        }
        return ScoreMessageHandlingResult.unmappableMeasure;
      case ScoreRendererMessageType.ready:
      case ScoreRendererMessageType.error:
        return ScoreMessageHandlingResult.handled;
    }
  }

  void resumeAutoFollow() => _autoFollow = true;

  void syncFromPlayer({bool force = false}) {
    final ordinal = player.currentMeasureOrdinal;
    if (ordinal == null) {
      unawaited(port.clearHighlight());
      return;
    }
    if (!force && ordinal == _lastHighlightedOrdinal) return;
    _lastHighlightedOrdinal = ordinal;
    unawaited(port.highlightMeasure(ordinal, scrollIntoView: _autoFollow));
  }
}
```

- [ ] **Step 6: 运行协议与协调器测试**

Run: `flutter test test/score_renderer_protocol_test.dart test/score_playback_coordinator_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交桥接领域层**

```bash
git add lib/core/score/score_renderer_protocol.dart lib/core/score/score_playback_coordinator.dart test/helpers/score_renderer_test_fakes.dart test/score_renderer_protocol_test.dart test/score_playback_coordinator_test.dart
git commit -m "feat: 定义谱面桥接与播放同步协议"
```

---

### Task 5: 构建离线 OSMD 页面与 WebView 适配器

**Files:**
- Create: `assets/score_renderer/index.html`
- Create: `assets/score_renderer/score_bridge.js`
- Create: `lib/ui/widgets/interactive_score_view.dart`
- Create: `test/interactive_score_view_test.dart`

**Interfaces:**
- Consumes: `ScoreSession.musicXml`、`ScoreRendererPort`、`ScoreRendererMessage.parse()`。
- Produces: `InteractiveScoreView`；本地 JS 全局接口 `scoreBridge.loadMusicXmlBase64()`、`highlightMeasure()`、`clearHighlight()`。

- [ ] **Step 1: 写组件状态失败测试**

```dart
testWidgets('没有 MusicXML 时不创建 WebView', (tester) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: InteractiveScoreView(
        musicXml: null,
        onMessage: (_) {},
      ),
    ),
  );
  expect(find.byKey(const Key('interactive-score-webview')), findsNothing);
  expect(find.text('仅伴奏'), findsOneWidget);
});

testWidgets('加载中和错误状态有稳定语义', (tester) async {
  final port = RecordingRendererPort();
  late ValueChanged<ScoreRendererMessage> emit;
  await tester.pumpWidget(
    CupertinoApp(
      home: InteractiveScoreView(
        musicXml: '<score-partwise/>',
        onMessage: (_) {},
        surfaceFactory: (onMessage) {
          emit = onMessage;
          return ScoreSurface(
            port: port,
            child: const SizedBox(key: Key('fake-score-surface')),
          );
        },
      ),
    ),
  );
  expect(find.text('正在排版乐谱'), findsOneWidget);
  emit(const ScoreRendererMessage.ready());
  await tester.pump();
  expect(find.text('正在排版乐谱'), findsNothing);
});
```

测试构造注入必须只暴露最小接口：

```dart
class ScoreSurface {
  final ScoreRendererPort port;
  final Widget child;

  const ScoreSurface({required this.port, required this.child});
}

typedef ScoreSurfaceFactory = ScoreSurface Function(
  ValueChanged<ScoreRendererMessage> onMessage,
);
```

- [ ] **Step 2: 运行测试确认组件缺失**

Run: `flutter test test/interactive_score_view_test.dart`

Expected: FAIL，包含 `InteractiveScoreView` 未定义。

- [ ] **Step 3: 创建离线 HTML 容器**

`assets/score_renderer/index.html` 固定结构：

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=0.6, maximum-scale=3, user-scalable=yes">
  <style>
    html, body { margin: 0; min-height: 100%; background: #f8f0dc; }
    body { overflow-x: hidden; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    #score-viewport { position: relative; width: 100%; min-height: 100vh; }
    #score { width: 100%; min-height: 100vh; padding: 12px 0 96px; box-sizing: border-box; }
    #measure-layer { position: absolute; inset: 0; pointer-events: none; z-index: 3; }
    .measure-hit { position: absolute; border-radius: 4px; background: transparent; transition: background-color 120ms ease; }
    .measure-hit.active { background: rgba(201, 160, 77, 0.18); box-shadow: inset 0 0 0 1px rgba(174, 128, 44, 0.35); }
  </style>
</head>
<body>
  <main id="score-viewport" aria-label="可交互五线谱">
    <div id="score"></div>
    <div id="measure-layer" aria-hidden="true"></div>
  </main>
  <script src="opensheetmusicdisplay.min.js"></script>
  <script src="score_bridge.js"></script>
</body>
</html>
```

- [ ] **Step 4: 实现 OSMD 渲染、点击与高亮桥**

`score_bridge.js` 必须包含以下完整行为：

```javascript
(() => {
  'use strict';
  const score = document.getElementById('score');
  const layer = document.getElementById('measure-layer');
  let osmd = null;
  let down = null;
  let maxTravel = 0;
  let activeOrdinal = null;
  let resizeTimer = null;

  const post = (type, payload = {}) => {
    if (window.ScoreBridge && window.ScoreBridge.postMessage) {
      window.ScoreBridge.postMessage(JSON.stringify({ type, ...payload }));
    }
  };

  const decodeUtf8 = (encoded) => {
    const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  };

  const measureRects = () => {
    const unit = opensheetmusicdisplay.EngravingRules.unit;
    return osmd.GraphicSheet.MeasureList.map((staffMeasures, index) => {
      const boxes = staffMeasures
        .filter(Boolean)
        .map((measure) => measure.PositionAndShape)
        .filter(Boolean);
      if (boxes.length === 0) return null;
      const left = Math.min(...boxes.map((box) => (box.AbsolutePosition.x + box.BorderLeft) * unit));
      const top = Math.min(...boxes.map((box) => (box.AbsolutePosition.y + box.BorderTop) * unit));
      const right = Math.max(...boxes.map((box) => (box.AbsolutePosition.x + box.BorderRight) * unit));
      const bottom = Math.max(...boxes.map((box) => (box.AbsolutePosition.y + box.BorderBottom) * unit));
      return { ordinal: index + 1, left, top, width: right - left, height: bottom - top };
    }).filter(Boolean);
  };

  const applyHighlight = (ordinal, scrollIntoView) => {
    layer.querySelectorAll('.active').forEach((element) => element.classList.remove('active'));
    const target = layer.querySelector(`[data-ordinal="${Number(ordinal)}"]`);
    if (!target) return;
    target.classList.add('active');
    if (scrollIntoView) {
      const rect = target.getBoundingClientRect();
      const visible = rect.top >= 48 && rect.bottom <= window.innerHeight - 96;
      if (!visible) target.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  };

  const rebuildLayer = (complete) => {
    layer.replaceChildren();
    const rects = measureRects();
    for (const rect of rects) {
      const hit = document.createElement('div');
      hit.className = 'measure-hit';
      hit.dataset.ordinal = String(rect.ordinal);
      hit.style.left = `${rect.left}px`;
      hit.style.top = `${rect.top}px`;
      hit.style.width = `${Math.max(1, rect.width)}px`;
      hit.style.height = `${Math.max(1, rect.height)}px`;
      layer.appendChild(hit);
    }
    layer.style.width = `${score.scrollWidth}px`;
    layer.style.height = `${score.scrollHeight}px`;
    if (activeOrdinal !== null) applyHighlight(activeOrdinal, false);
    post('layout', { complete, measures: rects });
  };

  const render = async (xml) => {
    osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(score, {
      backend: 'svg',
      autoResize: false,
      drawTitle: true,
      pageFormat: 'Endless',
      pageBackgroundColor: '#f8f0dc',
      drawUpToMeasureNumber: 12,
    });
    osmd.setLogLevel('warn');
    await osmd.load(xml);
    osmd.render();
    rebuildLayer(false);
    post('ready');
    await new Promise((resolve) => requestAnimationFrame(resolve));
    osmd.setOptions({ drawUpToMeasureNumber: 1000000 });
    osmd.renderAndScrollBack();
    rebuildLayer(true);
  };

  document.addEventListener('pointerdown', (event) => {
    down = {
      x: event.clientX,
      y: event.clientY,
      at: performance.now(),
      pointerCount: event.isPrimary ? 1 : 2,
    };
    maxTravel = 0;
  }, { passive: true });

  document.addEventListener('pointermove', (event) => {
    if (!down) return;
    maxTravel = Math.max(
      maxTravel,
      Math.hypot(event.clientX - down.x, event.clientY - down.y),
    );
  }, { passive: true });

  document.addEventListener('pointerup', (event) => {
    if (!down) return;
    const gesture = {
      x: event.clientX + window.scrollX,
      y: event.clientY + window.scrollY,
      travel: maxTravel,
      durationMs: Math.round(performance.now() - down.at),
      pointerCount: down.pointerCount,
    };
    down = null;
    post('gestureEnd', gesture);
  }, { passive: true });

  window.scoreBridge = Object.freeze({
    async loadMusicXmlBase64(encoded) {
      try { await render(decodeUtf8(encoded)); }
      catch (error) { post('error', { message: String(error).slice(0, 500) }); }
    },
    highlightMeasure(ordinal, scrollIntoView) {
      activeOrdinal = Number(ordinal);
      applyHighlight(activeOrdinal, scrollIntoView);
    },
    clearHighlight() {
      activeOrdinal = null;
      layer.querySelectorAll('.active').forEach((element) => element.classList.remove('active'));
    },
  });

  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (!osmd) return;
      osmd.renderAndScrollBack();
      rebuildLayer(true);
    }, 150);
  });

  window.addEventListener('error', (event) => {
    post('error', { message: String(event.message || '谱面脚本错误').slice(0, 500) });
  });
})();
```

执行真机前必须用至少一份真实双谱表 MusicXML 验证 `EngravingRules.unit` 与 `PositionAndShape` 的矩形换算；如果测试显示 OSMD 1.9.9 的边界属性语义不同，只允许调整 `measureRects()`，不得改变 Flutter 消息协议。

- [ ] **Step 5: 实现受控 WebView 适配器**

`InteractiveScoreView` 构造接口：

```dart
class InteractiveScoreView extends StatefulWidget {
  final String? musicXml;
  final ValueChanged<ScoreRendererMessage> onMessage;
  final ValueChanged<ScoreRendererPort>? onPortReady;
  final VoidCallback? onImportMusicXml;
  final ScoreSurfaceFactory? surfaceFactory;

  const InteractiveScoreView({
    super.key,
    required this.musicXml,
    required this.onMessage,
    this.onPortReady,
    this.onImportMusicXml,
    this.surfaceFactory,
  });
}
```

内部统一使用 `_acceptMessage()`：`ready` 时移除加载遮罩，`error` 时进入错误状态，然后再调用 `widget.onMessage(message)`。生产 WebView 和测试 `surfaceFactory` 都必须把消息送入同一个 `_acceptMessage()`，避免测试路径绕过状态机。`musicXml == null` 时不构建 WebView，并用 `onImportMusicXml` 渲染“导入 MusicXML”按钮。

生产适配器 `_WebViewScoreRendererPort`：

```dart
class _WebViewScoreRendererPort implements ScoreRendererPort {
  final WebViewController controller;

  _WebViewScoreRendererPort(this.controller);

  @override
  Future<void> loadMusicXml(String musicXml) {
    final encoded = base64Encode(utf8.encode(musicXml));
    return controller.runJavaScript(
      'window.scoreBridge.loadMusicXmlBase64(${jsonEncode(encoded)})',
    );
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    return controller.runJavaScript(
      'window.scoreBridge.highlightMeasure($ordinal, $scrollIntoView)',
    );
  }

  @override
  Future<void> clearHighlight() =>
      controller.runJavaScript('window.scoreBridge.clearHighlight()');
}
```

WebView 配置必须是：

```dart
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setBackgroundColor(const Color(0xFFF8F0DC))
  ..addJavaScriptChannel(
    'ScoreBridge',
    onMessageReceived: (message) {
      try {
        _acceptMessage(ScoreRendererMessage.parse(message.message));
      } on FormatException {
        // 丢弃非法本地桥接消息，不触发播放器操作。
      }
    },
  )
  ..setNavigationDelegate(
    NavigationDelegate(
      onNavigationRequest: (request) {
        final uri = Uri.tryParse(request.url);
        final isLocal = uri != null &&
            (uri.scheme == 'file' || uri.scheme == 'about');
        return request.isMainFrame && !isLocal
            ? NavigationDecision.prevent
            : NavigationDecision.navigate;
      },
    ),
  )
  ..loadFlutterAsset('assets/score_renderer/index.html');
```

`NavigationDelegate.onPageFinished` 后调用 `port.loadMusicXml()`；`didUpdateWidget` 仅在 MusicXML 内容变化后重新加载。组件用 `Key('interactive-score-webview')`，加载遮罩文案为“正在排版乐谱”，错误状态显示桥接返回的具体消息和“重新导入”。

- [ ] **Step 6: 运行组件与资源测试**

Run: `flutter test test/interactive_score_view_test.dart test/score_renderer_assets_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交离线谱面组件**

```bash
git add assets/score_renderer/index.html assets/score_renderer/score_bridge.js lib/ui/widgets/interactive_score_view.dart test/interactive_score_view_test.dart
git commit -m "feat: 增加离线可交互五线谱组件"
```

---

### Task 6: 重构练习页与底部控制栏

**Files:**
- Create: `lib/ui/widgets/score_transport_bar.dart`
- Modify: `lib/ui/pages/score_practice_page.dart`
- Create: `test/score_practice_page_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `ScoreSession`、`InteractiveScoreView`、`ScorePlaybackCoordinator`、播放器小节 API。
- Produces: 图 3 结构的 `ScorePracticePage`；`ScoreTransportBar`。

- [ ] **Step 1: 写新版页面失败测试**

```dart
testWidgets('MusicXML 页面只显示五线谱主视图和固定控制栏', (tester) async {
  final player = readyPlayer()..loadScore(interactiveSession());
  await tester.pumpWidget(_page(player));

  expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
  expect(find.byKey(const Key('score-transport-bar')), findsOneWidget);
  expect(find.byKey(const Key('pdf-score-viewer')), findsNothing);
  expect(find.byKey(const Key('midi-piano-roll')), findsNothing);
  expect(find.text('真实 MIDI 数据'), findsNothing);
});

testWidgets('仅 MIDI 曲目显示仅伴奏但保留播放控制', (tester) async {
  final player = readyPlayer()..loadScore(midiOnlySession());
  await tester.pumpWidget(_page(player));

  expect(find.text('仅伴奏'), findsOneWidget);
  expect(find.text('导入对应 MusicXML 以显示可交互乐谱'), findsOneWidget);
  expect(find.byKey(const Key('score-play-pause')), findsOneWidget);
});

testWidgets('播放控制和前后小节调用播放器', (tester) async {
  final player = readyPlayer()..loadScore(interactiveSession());
  await tester.pumpWidget(_page(player));

  await tester.tap(find.byKey(const Key('score-next-measure')));
  expect(player.currentMeasureOrdinal, 2);
  expect(player.isStopped, isTrue);

  await tester.tap(find.byKey(const Key('score-play-pause')));
  expect(player.isPlaying, isTrue);
});

testWidgets('AB 按钮依次设置 A、B 并在第三次清除', (tester) async {
  final player = readyPlayer()..loadScore(interactiveSession());
  await tester.pumpWidget(_page(player));

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
```

同一测试文件定义 `_page(MidiPlayerController player)`，用 `MultiProvider` 提供该 player 和注入 `MemorySettingsStorage` 的 `AppSettingsController`，并构建 `CupertinoApp(home: ScorePracticePage(...))`。`MemorySettingsStorage implements AppSettingsStorage` 放在 `test/helpers/score_test_fixtures.dart`，用内存 `Map<String, Object?>` 实现 `read()`/`write()`。测试页面元数据固定为标题 `Interactive Fixture`、空的 `assetPath`，`initialSession` 使用 `player.scoreSession`，并传入返回 `ScoreSurface(port: RecordingRendererPort(), child: SizedBox())` 的 fake surface factory，保证 widget test 不创建真实平台 WebView。

- [ ] **Step 2: 运行页面测试确认旧界面不满足要求**

Run: `flutter test test/score_practice_page_test.dart`

Expected: FAIL，找不到新版 keys，或仍发现旧 MIDI/PDF 文案。

- [ ] **Step 3: 实现固定底部控制栏**

`ScoreTransportBar` 公共接口：

```dart
class ScoreTransportBar extends StatefulWidget {
  final MidiPlayerController player;
  final VoidCallback onPlaybackInteraction;

  const ScoreTransportBar({
    super.key,
    required this.player,
    required this.onPlaybackInteraction,
  });
}
```

行为固定为：

- `score-previous-measure`：`player.seekToPreviousMeasure()`。
- `score-play-pause`：播放时 `pause()`，否则 `play()`。
- `score-next-measure`：`player.seekToNextMeasure()`。
- `score-speed`：弹出 `0.5x / 0.75x / 1.0x / 1.25x / 1.5x` Cupertino action sheet，调用 `setSpeed()`。
- `score-ab-loop`：无 A 时 `setLoopStart(currentTime)`；有 A 无 B 时仅当 `currentTime > A` 才设置 B 并启用；已有 A/B 时 `clearLoop()`。
- 每次用户主动操作播放或小节导航后调用 `onPlaybackInteraction()`，恢复自动跟随。

视觉：高度 84，背景 `Color(0xFF403640)`，中央白色圆形播放按钮直径 58，其他图标使用 Cupertino Icons 和浅金色 `Color(0xFFF2DEAA)`。

- [ ] **Step 4: 将练习页收敛为顶部—谱面—底栏结构**

删除 `score_practice_page.dart` 对 `MidiPianoRoll` 和 `PdfScoreViewer` 的引用以及 `_ScoreDocumentView`、`_PracticeTimeline`、`_PracticeOptions`、旧 `_PracticeToolbar`。

页面主体固定为：

```dart
return CupertinoPageScaffold(
  backgroundColor: const Color(0xFFF8F0DC),
  navigationBar: CupertinoNavigationBar(
    previousPageTitle: '乐库',
    middle: Text(score.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: _ScorePageActions(onOpenSettings: _openSettings),
  ),
  child: SafeArea(
    bottom: false,
    child: Column(
      children: [
        if (_hasComplexRepetition) const _ComplexRepeatBanner(),
        Expanded(
          child: KeyedSubtree(
            key: const Key('interactive-score-view'),
            child: InteractiveScoreView(
              musicXml: player.scoreSession?.musicXml,
              onMessage: _handleRendererMessage,
              onPortReady: _attachRendererPort,
              onImportMusicXml: _importMusicXmlForCurrentScore,
            ),
          ),
        ),
        ScoreTransportBar(
          key: const Key('score-transport-bar'),
          player: player,
          onPlaybackInteraction: _resumeScoreFollow,
        ),
      ],
    ),
  ),
);
```

`ScorePracticePage` 增加可选 `ScoreSession? initialSession` 和仅供测试替换平台视图的 `ScoreSurfaceFactory? surfaceFactory`；导入页传入现成会话，内置曲目仍在 `initState()` 解析后包装为 `ScoreSession.midiOnly(song)`。页面在首帧仅加载一次 `initialSession` 或内置会话，并在 `dispose()` 对称移除播放器监听。播放器 listener 调用 `coordinator.syncFromPlayer()`，不能在 `build()` 中反复注册 listener 或重新加载会话。端口变更时只重建协调器；MusicXML 的初次加载和内容更新由 `InteractiveScoreView` 独占，避免双重渲染。

`_handleRendererMessage()` 必须使用协调器枚举返回值：

```dart
void _handleRendererMessage(ScoreRendererMessage message) {
  final result = _coordinator?.handleMessage(message) ??
      ScoreMessageHandlingResult.ignored;
  if (result == ScoreMessageHandlingResult.unmappableMeasure) {
    _showTransientMessage('谱面与伴奏小节不一致，无法跳转到这一小节。');
  }
}
```

仅伴奏状态在 `InteractiveScoreView` 内显示“仅伴奏”和“导入对应 MusicXML 以显示可交互乐谱”，`onImportMusicXml` 触发页面选择 `.musicxml` / `.xml`。成功后 `player.loadScore(session, songId: score.title)`，不得改变用户已选择的播放速度。

- [ ] **Step 5: 加入复杂反复与映射异常提示**

`_ComplexRepeatBanner` 文案固定为：

```text
此乐谱包含复杂反复，当前按谱面顺序播放。
```

当 `seekToMeasure()` 返回 false 时，用非阻塞 Cupertino alert 或 2 秒浮层显示：

```text
谱面与伴奏小节不一致，无法跳转到这一小节。
```

- [ ] **Step 6: 运行页面和 App 冒烟测试**

Run: `flutter test test/score_practice_page_test.dart test/widget_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交新版练习页**

```bash
git add lib/ui/widgets/score_transport_bar.dart lib/ui/pages/score_practice_page.dart test/score_practice_page_test.dart test/widget_test.dart
git commit -m "feat: 重构交互五线谱练习页"
```

---

### Task 7: 更新乐库与导入导航

**Files:**
- Modify: `lib/ui/pages/home_page.dart`
- Create: `test/home_score_navigation_test.dart`
- Modify: `test/widget_test.dart`

**Interfaces:**
- Consumes: `ScoreImportService.importFile()` 返回的 `ScoreSession`。
- Produces: 所有导入格式进入 `ScorePracticePage`；内置 MIDI 卡片显示“仅伴奏”。

- [ ] **Step 1: 写乐库失败测试**

```dart
testWidgets('内置 MIDI 卡片显示仅伴奏且不宣传 PDF 分谱', (tester) async {
  await tester.pumpWidget(_appWithHome());
  expect(find.text('仅伴奏'), findsWidgets);
  expect(find.textContaining('PDF'), findsNothing);
});

testWidgets('MusicXML 导入后进入交互谱面页', (tester) async {
  final session = interactiveSession();
  final picker = _FakeScorePicker('/tmp/score.musicxml');
  final importer = _FakeScoreImportService(session);
  await tester.pumpWidget(_appWithHome(picker: picker, importer: importer));

  await tester.tap(find.byKey(const Key('import-score')));
  await tester.pumpAndSettle();

  expect(find.byType(ScorePracticePage), findsOneWidget);
  expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
});
```

为避免 widget test 调起系统文件选择器，`HomePage` 注入：

```dart
abstract class ScoreFilePicker {
  Future<String?> pickScorePath();
}

class HomePage extends StatefulWidget {
  final ScoreImportService? importService;
  final ScoreFilePicker? filePicker;
  final ScoreSurfaceFactory? practiceSurfaceFactory;

  const HomePage({
    super.key,
    this.importService,
    this.filePicker,
    this.practiceSurfaceFactory,
  });
}
```

`test/home_score_navigation_test.dart` 在本文件内定义 `_FakeScorePicker implements ScoreFilePicker` 和 `_FakeScoreImportService extends ScoreImportService`，后者覆盖 `importFile()` 返回构造时注入的 session。`_appWithHome()` 用 `MultiProvider` 提供 `readyPlayer()` 和内存设置，并给 `HomePage.practiceSurfaceFactory` 传入 Task 5 的 fake `ScoreSurface`，禁止 widget test 创建真实平台 WebView。

- [ ] **Step 2: 运行测试确认旧导航仍进入 `PlayerPage`**

Run: `flutter test test/home_score_navigation_test.dart`

Expected: FAIL，导入后找不到 `ScorePracticePage` 或卡片缺少“仅伴奏”。

- [ ] **Step 3: 更新导入导航与内置卡片元数据**

`_pickAndLoadScore()` 改为：

```dart
final session = await _scoreImportService.importFile(filePath);
if (!mounted) return;
await Navigator.of(context).push(
  CupertinoPageRoute<void>(
    builder: (_) => ScorePracticePage(
      score: PracticeScoreMetadata.imported(session.songData.fileName),
      initialSession: session,
      surfaceFactory: widget.practiceSurfaceFactory,
    ),
  ),
);
```

导入页不得提前调用 `player.loadScore()`；`ScorePracticePage.initialSession` 是唯一加载点，页面载入会话后再应用 `AppSettingsController.defaultPlaybackSpeed`。这样导航只触发一次停止、清循环与播放器通知。

删除 `_ScoreCardData` 与 `PracticeScoreMetadata` 中的 `pdfPageAssetPrefix`、`pdfPageCount` 和 `hasPdfScore`。所有含 `assetPath` 但没有内置 MusicXML 的卡片显示统一角标：

```text
仅伴奏
```

K.478 卡片不得再显示或传递 PDF 分谱信息。

- [ ] **Step 4: 运行乐库与 App 测试**

Run: `flutter test test/home_score_navigation_test.dart test/widget_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交导航更新**

```bash
git add lib/ui/pages/home_page.dart test/home_score_navigation_test.dart test/widget_test.dart
git commit -m "feat: 统一乐库到交互谱面导航"
```

---

### Task 8: 完成自动化回归与文档同步

**Files:**
- Modify: `README.md`
- Modify: `docs/release_checklist.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Tasks 1–7 的最终行为。
- Produces: 与实现一致的架构说明、回归套件和真机验收清单。

- [ ] **Step 1: 更新 README 功能与架构说明**

将“PDF/钢琴卷帘展示”描述替换为：

```markdown
- **交互五线谱** — MusicXML 在 App 内离线排版；点击小节可跳转，播放时高亮当前小节
- **统一导入管线** — MusicXML 直接进入交互谱面；PDF 经 OMR 转为 MusicXML；MIDI-only 曲目标记为“仅伴奏”
```

架构树加入：

```text
lib/core/score/             # 谱面桥接协议与播放同步
lib/models/score_session.dart
lib/ui/widgets/interactive_score_view.dart
assets/score_renderer/      # 离线 OSMD 运行时
```

- [ ] **Step 2: 更新 CLAUDE.md 架构快照**

明确记录：

```markdown
- `ScoreSession` 是谱面原文、播放数据与小节映射的唯一会话边界。
- `ScorePlaybackCoordinator` 是网页谱面事件进入播放器的唯一入口。
- OSMD 仅负责离线排版、命中候选与高亮；它不能直接调用播放器。
- 纯 MIDI 不自动转谱，只显示“仅伴奏”。
```

- [ ] **Step 3: 扩充真机发布清单**

在 `docs/release_checklist.md` 增加：

```markdown
## 可交互 MusicXML 谱面

- [ ] 断网后导入 MusicXML，谱面仍能显示
- [ ] 点击首、中、末小节，播放器跳到对应小节起点
- [ ] 播放中点击后继续播放，暂停中点击后保持暂停
- [ ] 连续播放跨小节时高亮只移动一次且必要时自动滚动
- [ ] 手动滚动后不会立刻被自动跟随拉回；再次播放操作后恢复跟随
- [ ] 双指缩放和纵向滚动不误触小节跳转
- [ ] 横竖屏切换后小节点击仍准确
- [ ] 后台切回后谱面与播放位置一致
- [ ] MIDI-only 曲目显示“仅伴奏”，播放功能仍可使用
- [ ] 复杂反复谱显示按谱面顺序播放提示
```

- [ ] **Step 4: 运行格式化与完整质量门禁**

```bash
dart format lib test
flutter analyze
flutter test
flutter build ios --debug --no-codesign
```

Expected:

- `flutter analyze`：`No issues found!`
- `flutter test`：全部测试通过，0 failures。
- iOS no-codesign build：exit code 0。

- [ ] **Step 5: 检查主界面不再引用旧视图**

Run:

```bash
rg -n "MidiPianoRoll|PdfScoreViewer|真实 MIDI 数据|公版 PDF" lib/ui/pages/score_practice_page.dart
```

Expected: 无输出，exit code 1。

- [ ] **Step 6: 提交文档与回归修正**

```bash
git add README.md docs/release_checklist.md CLAUDE.md
git commit -m "docs: 补充交互谱面验收说明"
```

提交前必须用 `git diff --cached --name-only` 确认没有暂存 `ios/Pods/`、本地 IDE 文件或无关改动。

---

### Task 9: iPhone 14 Pro 真机验证与视觉 QA

**Files:**
- Modify only if defects are found: Task 1–8 中对应的最小文件集。
- Evidence: 不提交含个人设备标识或签名团队信息的日志。

**Interfaces:**
- Consumes: 已完成的 Debug 构建、标准钢琴 MusicXML fixture 或用户提供的真实 MusicXML。
- Produces: 可复现的真机验收结论；发现缺陷时以单独测试和修复提交闭环。

- [ ] **Step 1: 确认真机和签名环境**

```bash
flutter devices
flutter doctor -v
```

Expected: iPhone 14 Pro 可见且开发者模式/信任状态正常。若签名团队与钥匙串证书不一致，停止部署并修复 Xcode 账户配置，不修改业务代码掩盖签名错误。

- [ ] **Step 2: 真机启动并保留日志**

```bash
flutter run -d "iPhone 14 Pro" --debug
```

Expected: 安装并进入新版练习页，无启动闪退；控制台没有未捕获 Dart、WKWebView 或 JavaScript 异常。

- [ ] **Step 3: 执行发布清单中的 MusicXML 验收**

逐项执行 Task 8 新增的十项检查。点击小节时同时观察：

- 高亮小节号。
- 播放器 `currentTime` 对应 `MeasureMap.tryMeasureToTime()`。
- 播放/暂停状态没有被意外切换。

- [ ] **Step 4: 对照图 3 做同视口视觉检查**

在 iPhone 14 Pro 竖屏同一状态截图，对照用户提供的图 3 检查：

- 顶部控制密度和曲名不挤压。
- 五线谱占据主要视口，没有 PDF 黑框、卷帘或 MIDI 数据卡片。
- 底部控制栏不遮挡当前小节。
- 高亮颜色不影响音符可读性。
- 安全区、横屏和大字号下无溢出。

P0/P1/P2 视觉或交互问题必须修复后重新截图与复测；P3 微调记录为后续项，不阻塞本版本。

- [ ] **Step 5: 若发现缺陷，执行独立红绿修复循环**

每个缺陷：先在最接近的测试文件中添加单一失败用例，运行确认失败，再修改最小实现，运行该测试与完整 `flutter test`。不得把多个不相关缺陷合入同一次修复提交。

- [ ] **Step 6: 最终验证工作区与提交历史**

```bash
flutter analyze
flutter test
flutter build ios --debug --no-codesign
git status --short --branch
git log --oneline -10
```

Expected: analyze、test、build 均成功；工作区干净；提交按任务边界排列。

---

## Plan Self-Review Record

- Spec coverage：页面结构、统一会话、离线 OSMD、小节点击、状态保持、高亮去重、自动滚动、仅伴奏、复杂反复、异常映射、安全边界、自动测试和真机验收均有对应任务。
- Scope：保留旧跟随页和旧资产但移除新版练习页引用；不夹带资产删除或 USB MIDI 跟随重构。
- Type consistency：`ScoreSession` → `MeasureMap` → `MidiPlayerController` → `ScorePlaybackCoordinator` → `InteractiveScoreView` → `ScorePracticePage` 的类型和方法名按任务顺序唯一声明。
- Placeholder scan：计划不含未定义的占位实现；真机发现的未知缺陷只允许按明确红绿循环处理。
