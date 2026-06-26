# MusicXML / MXL 集成计划

本文记录 MusicXML 与 MXL 接入路线。目标是让 App 能导入、显示、播放并跟随标准乐谱文件，同时不打乱现有 MIDI 播放链路。

## 1. 当前结论

短期采用以下架构：

```text
.musicxml / .xml / .mxl
        |
        v
MusicXML 读取与解析
        |
        v
ScoreDocument 语义模型
        |
        +--> PerformanceTimeline：播放、跟随、光标、测试
        |
        +--> OSMD / WebView：标准乐谱渲染
```

不建议短期自己用 Flutter 完整绘制标准五线谱。MusicXML 排版包含谱号、调号、临时升降号、连线、装饰音、跨小节连音、多声部、多谱表、反复和跳房子等复杂规则，自己绘制会显著拖慢核心功能推进。

## 2. 已完成基础

当前分支已经恢复并新增以下能力：

- `ScoreDocument`：独立的乐谱语义模型，包含 part、measure、voice、note、rest、pitch、source reference。
- `PerformanceTimeline`：从乐谱事件展开 note-on / note-off / rest，用于后续播放、跟随和光标。
- `PerformanceInput`：统一演奏输入事件，支持 note-on、note-off、pitch、sustain。
- `MusicXmlScoreParser`：解析 `score-partwise` 子集到 `ScoreDocument`。
- 测试覆盖：score 展开、MIDI 输入事件、MusicXML 基础解析、和弦起点、连音语义。

当前 `MusicXmlScoreParser` 支持：

- `score-partwise`
- `part-list` / `score-part`
- `part` / `measure`
- `attributes/divisions`
- `time/beats` / `time/beat-type`
- `note/pitch`
- `note/rest`
- `note/chord`
- `backup` / `forward`
- `tie type="start|stop"`
- `notations/tied type="start|stop"`
- `grace`

## 3. 近期目标

### 阶段 A：解析层补齐

目标：让常见单谱表和钢琴谱 MusicXML 可以稳定转成 `ScoreDocument`。

待补能力：

- key signature：`attributes/key/fifths`、大小调模式。
- clef：`attributes/clef/sign`、`line`、多谱表编号。
- staff：`note/staff`，用于区分钢琴左右手谱表。
- tempo：`direction/sound tempo`、`direction/metronome`。
- dynamics：`direction/direction-type/dynamics`，先保留 source 信息，不必参与播放。
- slur：`notations/slur`，先作为显示/跟随辅助语义，不改变 note-on/off。
- tuplet：`time-modification`，影响 duration 与显示语义。
- pickup measure：弱起小节 duration 小于拍号默认长度时，不应强行扩成完整小节。
- repeat / ending：`barline/repeat`、`ending`，先建模，后续再决定展开策略。

验收：

- 新增 5-8 个 fixture，覆盖单声部、钢琴双谱表、连音、装饰音、变拍号、弱起、反复。
- `flutter test test/music_xml_parser_test.dart test/score_document_test.dart` 通过。
- `flutter analyze` 通过。

### 阶段 B：MXL 解包

目标：支持 `.mxl` 文件。

当前状态：基础解包层已完成，`MxlScoreParser` 可以读取 MXL zip、解析 `META-INF/container.xml`、找到 rootfile，并复用 `MusicXmlScoreParser` 生成 `ScoreDocument`。

实现方式：

- [x] 读取 MXL zip。
- [x] 解析 `META-INF/container.xml`。
- [x] 找到 `<rootfile full-path="...">` 指向的 MusicXML 主文件。
- [x] 将主文件内容交给 `MusicXmlScoreParser`。
- [ ] 用真实 `.mxl` fixture 做兼容性回归。
- [ ] 将 `.mxl` 接入文件导入链路。

依赖建议：

- 已使用 `archive` 处理 zip。
- XML 解析如果继续扩大范围，建议引入 `package:xml` 替换当前内部轻量 parser。
- 引入依赖时必须同步提交 `pubspec.lock`。

验收：

- `.musicxml` 与 `.mxl` 同一首曲子解析结果一致。
- 异常 MXL：缺少 container、缺少 rootfile、rootfile 指向不存在，都有明确异常。

### 阶段 C：导入链路

目标：文件导入支持 MIDI 与乐谱文件并存。

文件类型：

- MIDI：`.mid`、`.midi`
- MusicXML：`.musicxml`、`.xml`
- Compressed MusicXML：`.mxl`

建议新增导入模型：

```text
ImportedScore
  - id
  - title
  - sourcePath
  - sourceType: midi | musicXml | mxl
  - midiSongData?
  - scoreDocument?
```

处理策略：

- MIDI 文件继续走现有 `MidiFileParser` 和 `MidiPlayerController`。
- MusicXML / MXL 先生成 `ScoreDocument`。
- 若 MusicXML 没有关联 MIDI，先只进入乐谱查看 / 跟随准备态，不假装可以用现有 MIDI 引擎完整播放。
- 后续可加入 MusicXML -> MIDI event synthesis，或要求曲库素材同时提供 MIDI + MusicXML。

验收：

- 文件选择器能选 `.musicxml/.xml/.mxl`。
- 解析成功进入乐谱页。
- 解析失败给出明确错误，不崩溃。
- MIDI 导入回归不受影响。

### 阶段 D：渲染层

目标：短期用 OSMD 显示标准乐谱。

建议方案：

- Flutter 使用 WebView 承载 OSMD。
- 将 MusicXML 字符串传给 WebView。
- WebView 返回 measure / cursor 所需的布局信息，或由 Flutter 根据 `ScoreDocument` 时间线驱动光标。

边界：

- OSMD 负责排版和视觉渲染。
- Flutter 原生负责播放状态、跟随状态、控制栏、曲库、设置。
- `ScoreDocument` 是业务语义源，不依赖 OSMD。

验收：

- iOS 真机可加载本地 MusicXML 并显示。
- 可根据当前 beat 高亮小节或光标。
- 页面返回、切曲、重复进入不泄漏 WebView 状态。

### 阶段 E：时间线与跟随

目标：将 `ScoreDocument` 和现有跟随模式连接起来。

核心任务：

- 将 tempo/direction 影响纳入 `PerformanceTimeline`。
- 建立 `score position -> wall clock / playback time` 映射。
- 对 repeat / ending 做展开，或明确 MVP 阶段暂不展开。
- 将 `PerformanceInputEvent` 与 `PerformanceTimeline` 做匹配，得到 `ScoreTrackingState`。
- 处理长休止、低置信度、恢复、跳奏等边界。

验收：

- 使用测试 fixture 回放输入事件，能定位到预期小节范围。
- 长休止不误判为丢失。
- 连音不重复触发目标音。
- 和弦可按多个同时音进行匹配。

## 4. 数据模型建议

后续建议逐步扩展 `ScoreDocument`，避免把 MusicXML 原始标签泄漏到业务层。

建议新增：

- `ScoreKeySignature`
- `ScoreClef`
- `ScoreTimeSignature`
- `ScoreTempoMark`
- `ScoreStaff`
- `ScoreDirection`
- `ScoreSlur`
- `ScoreTuplet`
- `ScoreRepeat`
- `ScoreEnding`

原则：

- parser 可以保留 `SourceReference` 指向原始位置。
- 业务层只消费稳定语义模型。
- 复杂显示细节优先交给 OSMD。

## 5. 风险

- MusicXML 标准覆盖面很大，不能一次性承诺完整兼容。
- OSMD/WebView 在 iOS 上需要做本地资源加载、安全策略和生命周期验证。
- MusicXML 没有音色和演奏细节时，直接合成 MIDI 播放的效果可能弱于原始 MIDI。
- 反复、跳房子、DS/DC 等会影响时间线展开，是跟随准确性的高风险点。
- 多谱表、多声部和跨小节连音会影响光标和输入匹配。

## 6. 下一步建议

优先顺序：

1. 引入真实 MusicXML fixture，覆盖钢琴双谱表和弱起小节。
2. 修正弱起小节 duration 策略，不再总是扩成拍号默认长度。
3. 加入 `staff`、`clef`、`key`、`tempo` 的模型和解析。
4. 实现 MXL 解包。
5. 扩展文件导入验证到 `.musicxml/.xml/.mxl`。
6. 做 OSMD/WebView 技术 spike。
