import 'package:flutter/cupertino.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';
import 'player_display_data.dart';
import 'transport_deck.dart';

/// 仪表盘数字显示
class StageDial extends StatelessWidget {
  final String value;
  final String caption;
  final Color accent;

  const StageDial({
    super.key,
    required this.value,
    required this.caption,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF241C16), Color(0xFF130F0D)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: luxuryDisplayStyle(
                context,
                size: 22,
                color: LuxuryPalette.goldBright,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                color: LuxuryPalette.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 指标卡片（BPM / 时长 / 轨道数）
class StageMetric extends StatelessWidget {
  final String label;
  final String value;

  const StageMetric({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              color: LuxuryPalette.textSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: LuxuryPalette.goldBright,
            ),
          ),
        ],
      ),
    );
  }
}

/// 舞台控制台：曲名、进度、BPM、运输按钮
class StageConsole extends StatelessWidget {
  final MidiPlayerController player;
  final bool isFollowMode;
  final FollowModeState followState;
  final double followSpeedFactor;
  final ValueChanged<double>? onSeek;

  const StageConsole({
    super.key,
    required this.player,
    required this.isFollowMode,
    required this.followState,
    required this.followSpeedFactor,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final song = player.songData;
    if (song == null) return const SizedBox.shrink();

    final data = StageConsoleData.fromPlayer(
      player: player,
      isFollowMode: isFollowMode,
      followState: followState,
      followSpeedFactor: followSpeedFactor,
    );

    return LuxuryPanel(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionEyebrow(label: 'NOCTURNE STAGE'),
              const Spacer(),
              StatusBadge(label: data.statusLabel, color: data.accent),
            ],
          ),
          const SizedBox(height: 22),
          const OrnamentLine(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: luxuryDisplayStyle(context, size: data.titleSize),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '黑金排练控制台',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 1.5,
                        color: LuxuryPalette.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              StageDial(
                value: data.speedLabel,
                caption: data.speedCaption,
                accent: data.accent,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              StageMetric(label: 'BPM', value: data.bpmLabel),
              StageMetric(label: '时长', value: data.durationLabel),
              StageMetric(label: '轨道', value: data.trackCountLabel),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: CupertinoColors.white.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: LuxuryPalette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '场次进度',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: LuxuryPalette.textSubtle,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      data.remainingLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CupertinoSlider(
                  key: PlayerUiKeys.stageProgressSlider,
                  value: data.progress,
                  onChanged: (value) => _seekTo(value * data.totalDuration),
                ),
                Row(
                  children: [
                    Text(
                      data.currentTimeLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: LuxuryPalette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      data.totalDurationLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TransportDeck(player: player, onSeek: onSeek),
        ],
      ),
    );
  }

  void _seekTo(double seconds) {
    final seek = onSeek;
    if (seek != null) {
      seek(seconds);
    } else {
      player.seekTo(seconds);
    }
  }
}
