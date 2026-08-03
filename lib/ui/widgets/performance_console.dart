import 'package:flutter/cupertino.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../../core/midi/midi_player.dart';
import '../../core/midi_input/midi_input.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';

/// 控制台卡片
class ConsoleCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const ConsoleCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: LuxuryPalette.textSubtle,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 演奏控制台：跟随模式开关、手动速度滑块
class PerformanceConsole extends StatelessWidget {
  final MidiPlayerController player;
  final bool isFollowMode;
  final FollowModeState followState;
  final double followSpeedFactor;
  final Set<int> performerTrackIndices;
  final MidiInputState midiInputState;
  final Future<void> Function() onToggleFollow;

  const PerformanceConsole({
    super.key,
    required this.player,
    required this.isFollowMode,
    required this.followState,
    required this.followSpeedFactor,
    required this.performerTrackIndices,
    required this.midiInputState,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final followAccentColor = followAccent(
      isFollowMode,
      followState,
      player.isPlaying,
    );
    final followNote = switch (followState) {
      FollowModeState.following => '伴奏正在跟随你的速度。',
      FollowModeState.waitingForOnset => '等待下一次起拍。',
      FollowModeState.idle =>
        isFollowMode
            ? '跟随已开启，等待电子琴输入。'
            : midiInputState.isConnected
            ? 'USB MIDI 已就绪，可开启跟随。'
            : '请将电子琴通过 USB MIDI 连接到 iPhone。',
    };
    final midiName = midiInputState.primaryDeviceName;
    final midiConnected = midiInputState.isConnected;

    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionEyebrow(label: 'PERFORMANCE'),
                  SizedBox(height: 10),
                ],
              ),
              const Spacer(),
              CupertinoSwitch(
                value: isFollowMode,
                onChanged: (_) => onToggleFollow(),
              ),
            ],
          ),
          Text('跟随排练', style: luxuryDisplayStyle(context, size: 28)),
          const SizedBox(height: 8),
          Text(
            followNote,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color:
                  (midiConnected ? LuxuryPalette.emerald : LuxuryPalette.ruby)
                      .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    (midiConnected ? LuxuryPalette.emerald : LuxuryPalette.ruby)
                        .withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  midiConnected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.link,
                  size: 17,
                  color: midiConnected
                      ? LuxuryPalette.emerald
                      : LuxuryPalette.ruby,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    midiConnected
                        ? 'USB MIDI · $midiName'
                        : midiInputState.errorMessage ?? 'USB MIDI · 未检测到设备',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: LuxuryPalette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ConsoleCard(
                  label: '电子琴声部',
                  value: performerTrackIndices.isEmpty
                      ? '未指定'
                      : '${performerTrackIndices.length} 条轨道',
                  accent: performerTrackIndices.isEmpty
                      ? LuxuryPalette.ruby
                      : LuxuryPalette.goldBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ConsoleCard(
                  label: isFollowMode ? '跟随倍率' : '速度倍率',
                  value: isFollowMode
                      ? '${followSpeedFactor.toStringAsFixed(2)}x'
                      : '${player.playbackSpeed.toStringAsFixed(2)}x',
                  accent: followAccentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: isFollowMode
                ? Container(
                    key: const ValueKey('follow-live'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: followAccentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: followAccentColor.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.waveform_path_ecg,
                          size: 18,
                          color: followAccentColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            followLabel(true, followState, player.isPlaying),
                            style: const TextStyle(
                              fontSize: 14,
                              color: LuxuryPalette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    key: const ValueKey('manual-slider'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: LuxuryPalette.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '手动速度',
                              style: TextStyle(
                                fontSize: 12,
                                letterSpacing: 1.2,
                                color: LuxuryPalette.textSubtle,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${player.playbackSpeed.toStringAsFixed(2)}x',
                              style: const TextStyle(
                                fontSize: 13,
                                color: LuxuryPalette.goldBright,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        CupertinoSlider(
                          value: player.playbackSpeed,
                          min: 0.25,
                          max: 4.0,
                          divisions: 15,
                          onChanged: player.setSpeed,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
