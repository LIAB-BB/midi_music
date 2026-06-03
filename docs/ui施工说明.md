# UI 施工说明

这份文档给人工前端、Claude Code 和 Codex 共用。目标是让界面可以继续大胆调整，但不误伤 MIDI 播放、跟随模式和音频资源生命周期。

## 当前 UI 边界

主要入口：

- `lib/ui/pages/home_page.dart`：首页，负责选择 MIDI 文件、加载曲目、跳转播放页。
- `lib/ui/pages/player_page.dart`：播放页容器，负责跟随模式生命周期、麦克风权限、播放错误提示。
- `lib/ui/theme/luxury_theme.dart`：全局视觉主题，颜色、背景、面板、展示字体。
- `lib/ui/widgets/stage_console.dart`：主舞台区，曲名、BPM、进度、运输控制入口。
- `lib/ui/widgets/transport_deck.dart`：播放/暂停/停止/快进/回退/归零。
- `lib/ui/widgets/performance_console.dart`：跟随模式开关、速度显示、手动速度滑块。
- `lib/ui/widgets/track_salon.dart`：轨道列表、静音、音量、设为主旋律。
- `lib/ui/widgets/soundfont_banner.dart`：SoundFont 下载状态和重试入口。
- `lib/ui/widgets/player_display_data.dart`：给 UI 用的展示数据，不直接画界面。
- `lib/ui/widgets/player_helpers.dart`：通用格式化、状态标签、小组件和稳定测试 Key。

## 推荐施工顺序

1. 先改 `luxury_theme.dart`，统一视觉基调。
2. 再改 `stage_console.dart` 和 `transport_deck.dart`，这是用户最常操作的区域。
3. 然后改 `performance_console.dart`，确保跟随模式开关和手动速度仍清楚。
4. 最后改 `track_salon.dart`，轨道列表可以重排成混音台、分组列表或紧凑表格。
5. 首页 `home_page.dart` 可以单独改，不要和播放器页大改混在一个提交里。

## 不要轻易改的逻辑

`player_page.dart` 里的这些函数属于行为层，视觉施工时不要改：

- `_toggleFollowMode()`
- `_requestMicPermission()`
- `_startFollowMode()`
- `_stopFollowMode()`
- `_releaseFollowResources()`
- `_seekTo()`

如果必须改，先补测试，再跑 `flutter analyze && flutter test`。

## 必须保留的交互语义

- 播放/暂停：继续调用 `player.play()` / `player.pause()`。
- 停止：继续调用 `player.stop()`。
- 快进/回退/归零：继续走 `onSeek`，不要直接绕过播放页的 `_seekTo()`。
- 进度条拖动：继续走 `onSeek`。
- 手动速度：继续调用 `player.setSpeed()`。
- 跟随开关：继续调用 `onToggleFollow()`。
- 轨道静音：继续调用 `player.toggleTrackMute(track.index)`。
- 轨道音量：继续调用 `player.setTrackVolume(track.index, value)`。
- 设置主旋律：继续调用 `onSetMelody(track.index)`。

## 稳定 Key

关键控件的 Key 统一定义在 `PlayerUiKeys`，后续测试和人工重排都应复用：

- `PlayerUiKeys.stageProgressSlider`
- `PlayerUiKeys.transportStopButton`
- `PlayerUiKeys.transportBackwardButton`
- `PlayerUiKeys.transportPlayPauseButton`
- `PlayerUiKeys.transportForwardButton`
- `PlayerUiKeys.transportResetButton`
- `PlayerUiKeys.followModeSwitch`
- `PlayerUiKeys.manualSpeedSlider`
- `PlayerUiKeys.trackTile(trackIndex)`
- `PlayerUiKeys.trackMuteButton(trackIndex)`
- `PlayerUiKeys.trackMelodyButton(trackIndex)`
- `PlayerUiKeys.trackVolumeSlider(trackIndex)`

## 验收命令

```bash
flutter analyze
flutter test
```

UI 只改布局也要跑这两条。播放器和跟随模式依赖异步生命周期，肉眼看起来正常不等于行为没坏。
