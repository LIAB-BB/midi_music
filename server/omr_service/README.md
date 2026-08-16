# OMR Service

> 状态：仅供本地或受控开发的服务骨架，不属于当前默认试用范围，也不能直接公开部署。它没有完整的用户鉴权/授权、TLS 终止、限流、持久化审计和正式数据保留/删除机制。产品边界见 [`../../docs/product/release_scope.md`](../../docs/product/release_scope.md)。

这是 App 端 PDF 导入的最小服务端。它接收 PDF，后台调用 Audiveris，导出 MusicXML，然后按 App 约定返回结果。App 保留返回的 MusicXML 原文用于离线 OSMD 显示，并独立解析播放时间线；不会将 OMR 结果再经过 MIDI 自动记谱。

完整交接说明见 [`HANDOFF.md`](HANDOFF.md)。

## 运行前提

服务运行环境需要能执行 `audiveris` 命令。可以通过环境变量指定路径：

```bash
export AUDIVERIS_BIN=/path/to/audiveris
```

如果用 Docker，需要在镜像中自行加入 Audiveris，或把宿主机的 Audiveris
可执行文件和运行时挂载进容器。当前 Dockerfile 只提供 Python API 服务骨架。

## 本地运行

```bash
pip install -r requirements.txt
AUDIVERIS_BIN=/path/to/audiveris uvicorn app:app --host 0.0.0.0 --port 8080
```

## Docker Compose

```bash
cp .env.example .env
docker compose up --build
```

健康检查：

```bash
curl http://127.0.0.1:8080/healthz
```

App 侧配置：

```bash
flutter run --dart-define=OMR_SERVICE_BASE_URL=http://127.0.0.1:8080
```

真机调试时不要用 `127.0.0.1` 指向电脑服务，应改成电脑局域网 IP 或公网地址。

## API

接口与 App 端约定见：

```text
docs/omr_service_contract.md
```

## MVP 边界

优先处理清晰钢琴独奏谱和高质量钢琴二重奏。OMR 结果不保证 100% 准确，
后续应增加谱面预览和人工校对。

当前目录只是单机低并发骨架，没有鉴权、持久化任务库、多 worker 队列、HTTPS 反代或内置 Audiveris；不应在未补齐这些能力前直接公网生产部署。
