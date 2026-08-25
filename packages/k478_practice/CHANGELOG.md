## 0.1.0

- 建立独立的 K.478 iOS USB MIDI 候选功能包；
- 迁移 MIDI 解析、TempoMap、USB 跟随和 K.478 演奏界面；
- 使用 `flutter_midi_pro 4.0.4`，显式设置 iOS playback audio session；
- 添加钢琴轨永久音频过滤的回归测试；
- 加入经过授权、哈希锁定且由 Apple sampler 离线渲染验证的 Violin/Cello
  单预设 SoundFont，并按 Program 将 MIDI channel 路由到对应音色库。
