# OMR 服务端交接文档

> 状态：开发交接材料，不是生产部署批准。对外开放前必须设计并验证认证/授权、限流、TLS、恶意文件防护、访问日志、数据保留和删除流程；当前产品边界见 [`../../docs/product/release_scope.md`](../../docs/product/release_scope.md)。

## 目标

给 Flutter App 提供 PDF 钢琴谱识谱服务。

App 端只依赖 HTTP 协议，不依赖服务端内部实现。服务端可以用 Audiveris、
商业 OMR、人工校对流水线或混合方案，只要满足本文接口即可。

第一版目标谱种：

- 清晰扫描或电子版钢琴五线谱。
- 钢琴独奏。
- 高质量钢琴二重奏，按 Primo / Secondo 或多个 MusicXML part 输出。

暂不承诺：

- 手写谱。
- 吉他谱、简谱、管弦乐总谱。
- 低清、歪斜、裁切严重的扫描件。

## App 端配置

Flutter 构建/运行时配置：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=http://服务地址:8080
```

真机调试时，`OMR_SERVICE_BASE_URL` 不能写电脑自己的 `127.0.0.1`，要写手机能访问到的局域网 IP、AutoDL 公网代理地址或正式域名。

## 必须实现的接口

### 健康检查

`GET /healthz`

成功响应：

```json
{
  "ok": true
}
```

### 创建识谱任务

`POST /v1/omr/jobs`

请求类型：`multipart/form-data`

字段：

- `file`：PDF 文件

成功响应：

```json
{
  "jobId": "abc123"
}
```

### 查询识谱任务

`GET /v1/omr/jobs/{jobId}`

排队：

```json
{
  "status": "queued"
}
```

运行中：

```json
{
  "status": "running"
}
```

成功，直接返回 MusicXML：

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
  "downloadUrl": "https://example.com/v1/omr/jobs/abc123/musicxml"
}
```

失败：

```json
{
  "status": "failed",
  "message": "未检测到稳定的五线谱系统"
}
```

App 端只识别四种任务状态：`queued`、`running`、`succeeded`、`failed`。

## 当前代码位置

- API 骨架：`server/omr_service/app.py`
- Python 依赖：`server/omr_service/requirements.txt`
- Dockerfile：`server/omr_service/Dockerfile`
- Compose 示例：`server/omr_service/docker-compose.yml`
- 环境变量示例：`server/omr_service/.env.example`
- App 端 HTTP 客户端：`lib/core/import/pdf_omr_client.dart`
- App 端导入分流：`lib/core/import/score_import_service.dart`

## 当前服务端骨架行为

当前 `app.py` 已经实现：

- 接收 PDF 上传。
- 限制上传大小，默认 30MB。
- 创建异步任务。
- 后台调用 `audiveris -batch -transcribe -export -output ... input.pdf`。
- 查找导出的 `.musicxml`、`.xml` 或 `.mxl`。
- 如果是 `.mxl`，解包读取内部 MusicXML。
- 返回 MusicXML 字符串。
- 保存 Audiveris stdout/stderr 日志。
- 按 TTL 清理任务目录，默认 24 小时。

当前未实现：

- 用户鉴权。
- 持久化任务数据库。
- 多 worker 队列。
- HTTPS/Nginx。
- 自动安装 Audiveris。
- 谱面预览和人工校对。

## 本地 Docker 骨架启动

```bash
cd server/omr_service
cp .env.example .env
docker compose up --build
```

注意：当前 Dockerfile 只装 Python API 依赖，不内置 Audiveris。服务端同事需要选择一种方式补齐：

1. 在 Dockerfile 里安装 Audiveris 和它需要的 Java/字体/图像依赖。
2. 把已有 Audiveris 可执行文件挂载进容器，并设置 `AUDIVERIS_BIN`。
3. 不用 Audiveris，改 `_run_omr_job()` 调自己的 OMR 服务，但保持 HTTP 接口不变。

## AutoDL 测试建议

AutoDL 上可以先用 Compose 跑服务，然后通过 AutoDL 的公网访问方式或 SSH 隧道暴露 8080。

App 端配置示例：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=http://AutoDL可访问地址:8080
```

如果走 HTTPS 反代，App 端改成：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=https://omr.example.com
```

## 服务端验收标准

服务端交付给 App 前，至少要满足：

- `GET /healthz` 返回 `{"ok": true}`。
- 上传一份清晰钢琴 PDF 后，`POST /v1/omr/jobs` 返回 `jobId`。
- 轮询任务最终返回 `status=succeeded` 和非空 MusicXML。
- 返回的 MusicXML 能被 App 的 `MusicXmlParser` 转成包含原文、`MidiSongData` 和真实小节边界的 `ScoreSession`，并在离线 OSMD 中排版。
- 失败 PDF 返回 `status=failed` 和用户可读 `message`，不能让任务无限 running。
- 单个任务失败时不能影响后续任务。
- 任务目录能自动清理。

## 推荐默认限制

- PDF 大小：30MB。
- 单任务超时：10 分钟。
- 任务结果保留：24 小时。
- MVP 并发：先单机低并发，后续再上队列。

## 和 App 的责任边界

服务端负责：

- PDF 识谱。
- 输出尽可能规范的 MusicXML。
- 失败原因可读。
- 控制任务资源和清理。

App 负责：

- 上传 PDF。
- 轮询任务。
- 保留 MusicXML 原文给离线 OSMD 显示，并从同一原文解析播放数据与小节边界。
- 播放，以及在提供高级演奏台入口时执行跟随；当前首页练习页不暴露 USB MIDI 跟随入口。

App 不负责：

- 在手机本地跑 OMR。
- 修复服务端识别错误。
- 理解服务端内部任务队列。

## 后续增强建议

1. 增加服务端任务队列，比如 Redis/RQ 或 Celery。
2. 增加 MusicXML 质量检查，过滤空谱、无音符谱、异常时长。
3. 增加谱面预览，让用户确认识谱结果。
4. 增加人工校对入口。
5. 增加鉴权和限流，避免公开接口被滥用。
