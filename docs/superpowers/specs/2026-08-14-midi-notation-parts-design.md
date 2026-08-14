# MIDI 自动五线谱与声部选择设计

日期：2026-08-14

## 1. 背景与问题

当前练习页只在 `ScoreSession.musicXml` 非空时创建 OSMD 交互谱面。内置曲目虽然已有 MIDI 资产，但 `ScoreSession.midiOnly()` 明确不生成谱面，因此页面显示“仅伴奏 / 导入 MusicXML”。这不符合产品目标：用户打开内置 MIDI 曲目时，应立即看到由真实 MIDI 音符生成的五线谱，并继续使用现有的小节点击、播放高亮、缩放与自动跟随。

Git 历史中曾出现过五线谱外观，但 `_PracticeScorePainter` 只按曲目 seed 生成固定示意音符，并不读取 MIDI；随后它被真实 MIDI 钢琴卷帘和 PDF 阅读器替换。此次不恢复示意谱、钢琴卷帘或 PDF，而是新增真实的 MIDI → MusicXML 离线记谱管线。

## 2. 目标

- 内置或用户导入的 MIDI 自动生成可见、可点击的五线谱，不再进入“仅伴奏”空态。
- 首次打开默认显示钢琴声部的双谱表；没有钢琴声部时回退为全部有音符声部。
- 用户可多选声部，并把多个声部组合为同一份总谱。
- 用户可保存全局默认声部类别，也可为单首曲目保存具体默认声部组合；曲目设置优先。
- 切换显示声部时不重新加载或修改原 MIDI 播放数据，保持当前时间、速度、AB 循环和播放/暂停状态。
- 继续复用离线 OSMD、统一 `MeasureMap`、小节点击和播放高亮协议。

## 3. 不在本次范围

- 专业制谱编辑、手动改音符、歌词、指法、连奏线编辑或分页排版控制。
- 把 MIDI 量化结果写回原文件或改变播放节奏。
- 自动区分同一钢琴音轨中真实的演奏手指。
- 在移动端追求出版级碰撞消除；目标是忠实、清晰、可交互的练习谱。
- 为没有 MIDI 资产的纯展示卡片伪造五线谱。这些卡片继续标为“仅预览”，进入时提供导入文件入口。

## 4. 方案选择

采用“Flutter 内离线 MIDI 分析和 MusicXML 生成 + 现有 OSMD 渲染”。

### 4.1 选择原因

- `MidiSongData` 已包含轨道、通道、GM program、真实音符、tempo、拍号和 tick，可在本地确定声部、小节与记谱事件。
- OSMD 已实现 MusicXML 排版、小节矩形、点击、高亮、缩放与重排；只需为 MIDI 会话补齐显示用 MusicXML。
- 原 MIDI 仍是播放真值，生成谱只承担显示，不会让量化误差进入声音。
- 同一转换管线同时覆盖内置 MIDI 和用户导入 MIDI。

### 4.2 未选方案

- Flutter 原生绘谱：需要重做符干、符尾、连线、和弦、休止、碰撞和点击几何，风险与维护成本最高。
- 只为内置曲目预生成 MusicXML：不能覆盖用户导入 MIDI，每增加曲目都需要额外资产。
- 恢复 `_PracticeScorePainter`：它的音符与真实 MIDI 无关，属于误导性假谱。

## 5. 领域模型

### 5.1 术语

- **MIDI 轨道**：MIDI 文件内的原始 `MidiTrackInfo`。
- **可选声部**：用户在声部面板中看到的选择项。一个可选声部可对应一个轨道，也可把多个钢琴轨道组合成一个“钢琴”项。
- **显示选择**：当前被选中的可选声部 ID 集合。
- **全局默认规则**：跨曲目保存的乐器类别集合，例如钢琴、弦乐；作用于第一次打开且没有曲目默认的曲目。
- **曲目默认**：按曲目指纹保存的具体可选声部 ID 集合，优先级高于全局规则。
- **显示会话**：包含原 `songData`、生成 MusicXML 和生成谱小节边界的 `ScoreSession`；播放器的原始 MIDI 时间线不变。

### 5.2 主要类型

新增 `MidiPartKind`：`piano`、`strings`、`woodwind`、`brass`、`guitar`、`bass`、`percussion`、`voice`、`synth`、`other`。

新增 `MidiScorePart`，至少包含：

- `id`：由曲目内轨道索引、通道和组合规则稳定生成。
- `label`：优先使用非空轨道名，否则使用 GM 乐器名或“轨道 N”。
- `kind`：乐器类别。
- `sources`：该选择项覆盖的 `(trackIndex, channel set)` 切片；Format 0 单轨多通道不能被整体误判或整体选中。
- `noteCount`：有效音符数。
- `staffMode`：`grandStaff`、`singleStaff` 或 `percussionStaff`。

新增 `MidiScoreCatalog`，包含曲目指纹、全部可选声部、推荐默认 ID 集合和推荐原因。

新增 `MidiNotationResult`，包含 `musicXml`、与播放器 tick 对齐的 `ScoreMeasureBoundary`、所选声部 ID 和量化警告；上层记谱服务再用它和原 `MidiSongData` 构造最终 `ScoreSession`。

## 6. 声部分析与默认选择

### 6.1 识别顺序

分析器先把每个含音符轨道按 MIDI channel 切成稳定来源，再按以下证据从强到弱识别来源：

1. MIDI 通道 10（零基索引 9）识别为打击乐。
2. 单通道轨道的明确轨道名关键字，例如 `piano`、`upper`、`lower`、`right hand`、`left hand`、`violin`、`cello`；多通道混合轨道的通用名字不能覆盖 channel 的 GM program 证据。
3. `programByChannel` 的 General MIDI program 区间。
4. 音域只作为弱证据，不单独把未知轨道判成钢琴。

同一曲目内多个钢琴来源组合成一个“钢琴”可选声部，并输出 `grandStaff`。只有一个钢琴来源时也输出双谱表，再按音高和声部连续性拆分左右手。非钢琴来源默认各自成为一个可选声部；名称重复时追加序号。转换器同时按 track 和 channel 过滤音符，不能把同一原轨中的未选 channel 混入总谱。

### 6.2 推荐默认

选择优先级：

1. 存在有效曲目默认时，使用曲目默认。
2. 否则选择匹配全局默认类别的声部。
3. 若无匹配，选择钢琴声部。
4. 若没有钢琴，选择全部有音符声部，但打击乐默认不选。
5. 若仅有打击乐，选择打击乐。

曲目默认中的声部 ID 在文件变更后可能失效；失效 ID 被忽略，若结果为空则重新执行上述回退，不显示空谱。

### 6.3 曲目指纹

内置曲目使用稳定 `asset:<assetPath>`；用户导入 MIDI 使用文件内容哈希，不使用会变化的临时路径。指纹只用于本机设置，不上传。

## 7. MIDI → MusicXML 记谱

### 7.1 播放与显示分离

原 `MidiSongData` 始终是播放真值。转换器生成的 MusicXML 只用于 OSMD 显示；播放器不得改用量化后的音符。转换后的 `ScoreMeasureBoundary` 直接来自原 MIDI 的 tick 小节边界，因此点击小节仍映射到原播放时间。

### 7.2 小节

- 使用 `MeasureMap` 相同的拍号变化和 PPQ 规则计算小节边界。
- 首小节若音符在标准小节长度前结束，仍保留完整 MIDI 时间轴；不猜测弱起语义。
- 拍号变化只在有效边界输出；异常 MIDI 的中途拍号变化截断当前小节并记录警告。
- MusicXML 中每个 part 输出相同数量和相同序号的小节，保证 OSMD 图形小节与播放器 ordinal 一致。

### 7.3 量化与音符

- 量化网格候选包含全音符、二分、四分、八分、十六分、三十二分、附点时值和三连音。
- 起点与时值分别取误差最小的可表示值；误差只影响显示。
- 同一 onset 的音符输出为和弦；重叠的独立旋律分配至最多四个 voice。
- 空白区间补 MusicXML rest；跨小节音符拆分并用 tie 连接。
- 钢琴 grand staff 的分配以中央 C 附近为初始分割，再用相邻音符走向减少左右手来回跳动；同一和弦不被拆散，除非跨度明显跨越两谱表。
- 非打击乐输出标准音高谱表；大提琴、贝斯等低音乐器优先低音谱号，其余默认高音谱号。
- 打击乐使用 percussion clef 和无音高音符；默认不选，但允许加入总谱。
- tempo、拍号、GM 乐器名和曲名写入 MusicXML；第一版不推断调号，默认无升降号并使用临时升降记号。

### 7.4 安全与复杂度上限

- 转换在 isolate 中执行，避免长 MIDI 阻塞 UI。
- 最多接受 64 个有音符轨道、单曲 500,000 个音符；超限时给出明确错误并保留当前可用谱面。
- 生成 XML 使用结构化转义，轨道名、文件名等不能注入标签。
- 输出继续进入现有本地 WebView；不增加远程脚本或网络请求。

## 8. 设置持久化

`AppSettingsController.settingsSchemaVersion` 升级，并保存：

- `defaultScorePartKinds`：全局默认 `MidiPartKind` 名称数组，初始为 `["piano"]`。
- `songScorePartSelections`：曲目指纹到具体声部 ID 数组的映射。

接口：

- `Set<MidiPartKind> get defaultScorePartKinds`
- `Set<String>? scorePartSelectionForSong(String fingerprint)`
- `void setDefaultScorePartKinds(Set<MidiPartKind> kinds)`
- `void setScorePartSelectionForSong(String fingerprint, Set<String> partIds)`
- `void clearScorePartSelectionForSong(String fingerprint)`

集合保存前排序以获得稳定 JSON。读取时拒绝未知类别、空 ID、超量曲目或超量声部，损坏数据回退为钢琴默认而不影响其他设置。

## 9. 界面与交互

### 9.1 练习页

- 右上角从单一设置按钮变为“声部”按钮和设置菜单，保持标题单行截断。
- MIDI 载入后先显示“正在生成五线谱”，完成后直接显示现有 `InteractiveScoreView`。
- 用户导入 MusicXML 时保持原有谱面原文，不再对其提供 MIDI 声部重选；“声部”入口仅在会话由 MIDI 自动记谱时可用。
- 无 MIDI 资产的预览卡片仍显示导入文件提示；有 MIDI 的曲目不得出现“仅伴奏”。

### 9.2 声部多选面板

使用 Cupertino 底部 Action Sheet 风格的可滚动面板：

- 标题“选择显示声部”。
- 每项显示复选标记、声部名、乐器类别、音符数和“钢琴双谱表”等谱表说明。
- 支持“全选”和“清除”；清除到零时“应用”禁用，并显示“至少选择一个有音符声部”。
- “应用”只改变当前显示；不会自动覆盖任何默认。
- 次级操作“设为本曲默认”保存具体声部 ID；“设为全局默认”保存当前所选声部的类别集合。
- 清晰显示当前来源：“使用本曲默认”“使用全局默认”或“自动选择钢琴”。

### 9.3 切换状态

应用新选择前记录当前时间、速度、AB 点和是否播放。只替换 `ScoreSession.musicXml` 与显示小节边界，不调用重新导入原 MIDI；`songData` 对象和播放器状态保持不变。OSMD ready 后强制同步当前小节高亮。

转换失败、无有效音符或生成结果非法时：

- 保留上一份可用谱面和选择。
- 显示可读错误，不回到“仅伴奏”。
- 默认设置不写入失败选择。

若首次生成时还没有上一份谱面，则显示独立“无法生成五线谱”状态，保留当前 MIDI 的固定播放控制，并提供“重试”和“导入文件”；不得泄漏上一曲、无限加载或显示“仅伴奏”。

## 10. 数据流

1. 首页载入内置或用户导入的 MIDI，产生原始 `MidiSongData`。
2. `MidiPartAnalyzer.analyze(song, fingerprint)` 产生 `MidiScoreCatalog`。
3. `MidiScoreSelectionResolver` 按曲目默认、全局规则和回退顺序选出 part IDs。
4. 播放器加载一次 `ScoreSession.midiOnly(song)`，建立原 MIDI 的 `TempoMap` 和 `MeasureMap`。
5. `MidiToMusicXmlConverter.convert(song, catalog, selectedIds)` 在 isolate 生成显示 MusicXML 和与原 tick 对齐的小节边界。
6. 页面构造显示 `ScoreSession`，其 `songData` 与播放器相同，但 `sourceType` 标记为 MIDI 自动记谱并含生成的 MusicXML。
7. `InteractiveScoreView` 和 `ScorePlaybackCoordinator` 沿用现有协议完成点击、高亮和滚动。
8. 声部切换只重复步骤 5–7，不重复步骤 4。

为避免把自动生成谱误认为用户提供的权威谱，`ScoreSourceType` 新增 `midiNotation`；界面可显示轻量“由 MIDI 生成”说明。

## 11. 错误与警告

新增可面向用户的记谱警告：

- 节奏已近似量化。
- 轨道名或乐器未知，已按独立声部显示。
- 拍号变化不在标准小节边界。
- 音符密度过高，谱面可能拥挤。

警告不改变播放；练习页只显示简短非阻断提示，详细原因在声部面板或谱面信息中查看。

## 12. 测试与验收

### 12.1 自动测试

- 轨道名、GM program、通道 10 和回退逻辑产生稳定声部类别。
- K.478 多轨 MIDI 默认只选择钢琴组合，并输出双谱表。
- 单钢琴轨按音高输出高低音谱表。
- 多选钢琴与弦乐后输出同一总谱且所有 part 小节数一致。
- 和弦、休止、跨小节 tie、附点、三连音和拍号变化生成可被现有 `MusicXmlParser` 与 OSMD 接受的 MusicXML。
- 生成小节的 start/end tick 与原 MIDI `MeasureMap` 一致。
- 声部选择优先级为曲目默认 > 全局类别 > 钢琴 > 非打击乐全部 > 打击乐。
- 设置 schema 迁移、非法值回退、稳定排序和持久化通过。
- 切换声部时播放器的 songData、currentTime、speed、AB 和播放/暂停状态不变。
- MIDI 曲目页面不再显示“仅伴奏”，转换失败保留上一份谱面。
- MusicXML / PDF OMR 原有流程不受影响。

### 12.2 真机验收

- iPhone 14 Pro 打开 K.478，默认直接显示钢琴双谱表。
- 打开声部面板，勾选弦乐后形成多声部总谱；取消后回到钢琴双谱表。
- 保存本曲默认，退出重进仍使用该组合。
- 保存全局默认，打开另一首无曲目默认的 MIDI 时按类别匹配。
- 点击首、中、末小节，跳转到原 MIDI 对应起点；播放/暂停状态保持。
- 播放跨小节时高亮与自动滚动正确。
- 变速和 AB 循环在切换声部前后保持。
- 竖屏、横屏、大字号、后台恢复无溢出或空白；底栏不遮挡当前小节。
- 对照用户图 3：五线谱是主视口，不出现 PDF 黑框、钢琴卷帘或 MIDI 数据卡片。

## 13. 完成标准

- 所有带 MIDI 资产的内置曲目和用户导入 MIDI 都能离线生成真实音符五线谱。
- 默认钢琴双谱表、多选总谱、全局默认和曲目默认均可用并持久化。
- 原 MIDI 播放真值和全部播放状态在显示切换中保持。
- 小节点击与高亮继续使用与原 MIDI 对齐的统一 `MeasureMap`。
- 不恢复假谱、卷帘或 PDF 主视图。
- `flutter analyze`、完整 `flutter test`、iOS Debug 无签名构建、iPhone 14 Pro 真机交互与视觉 QA 全部通过。
