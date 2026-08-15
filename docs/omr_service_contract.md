# PDF OMR 服务接口约定

目标链路：

```text
PDF 钢琴谱 -> 服务端 OMR -> MusicXML -> App 保留原文显示
                                            -> 解析播放时间线与真实小节边界
```

第一版仅承诺支持清晰扫描或电子版钢琴五线谱。钢琴二重奏按多个
MusicXML part 转为多轨道；手写谱、吉他谱、管弦乐总谱和严重歪斜/低清
扫描件不纳入 MVP。

## App 配置

构建或运行时通过 Dart define 配置服务端地址：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=https://your-api.example.com
```

未配置 `OMR_SERVICE_BASE_URL` 时，App 仍可导入 MIDI/MusicXML；选择 PDF 会
明确提示需要配置 PDF 识谱服务。

App 不会把 OMR MusicXML 再送入 MIDI 自动记谱转换器；同一份服务端原文直接交给离线 OSMD，同时由 `MusicXmlParser` 生成播放数据和书写顺序小节映射。

## 服务端接口

### 创建识谱任务

`POST /v1/omr/jobs`

请求：`multipart/form-data`

字段：

- `file`：PDF 文件，Content-Type 为 `application/pdf`

响应：

```json
{
  "jobId": "job-20260702-0001"
}
```

### 查询任务状态

`GET /v1/omr/jobs/{jobId}`

排队或运行中：

```json
{
  "status": "running"
}
```

成功，可以直接返回 MusicXML：

```json
{
  "status": "succeeded",
  "musicXml": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>..."
}
```

成功，也可以返回下载地址：

```json
{
  "status": "succeeded",
  "downloadUrl": "https://your-api.example.com/v1/omr/jobs/job-20260702-0001/musicxml"
}
```

失败：

```json
{
  "status": "failed",
  "message": "未检测到稳定的五线谱系统，请换一份更清晰的 PDF"
}
```

App 识别的状态值只有：`queued`、`running`、`succeeded`、`failed`。

### 健康检查

`GET /healthz`

```json
{
  "ok": true
}
```

## 服务端处理建议

服务端可用 Audiveris 做第一版 OMR。本仓库提供一个最小 FastAPI 服务端骨架：
`server/omr_service`。给服务端同事交接时优先看
`server/omr_service/HANDOFF.md`。

```bash
audiveris -batch -transcribe -export -output /work/out /work/input.pdf
```

实现要点：

- 每个任务放在独立临时目录，避免并发任务互相覆盖。
- 限制 PDF 页数、文件大小和任务超时时间。
- 识谱产物统一转为 MusicXML，App 端不直接处理 PDF。
- 保存原始 PDF、导出的 MusicXML、日志和失败原因，方便调试。
- 对用户展示“自动识谱可能需要人工校对”，避免承诺 100% 准确。

## MVP 谱种边界

优先支持：

- 清晰扫描或电子版 PDF。
- 独奏钢琴谱：高音谱号 + 低音谱号。
- 高质量钢琴二重奏：Primo / Secondo 多 part。

暂不承诺：

- 手写谱。
- 吉他谱、简谱、总谱。
- 大量装饰音、复杂跨谱表连线、极多反复跳转的谱面。
