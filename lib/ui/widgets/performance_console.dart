import 'package:flutter/cupertino.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import 'player_display_data.dart';
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
  final int? melodyTrackIndex;
  final Future<void> Function() onToggleFollow;

  const PerformanceConsole({
    super.key,
    required this.player,
    required this.isFollowMode,
    required this.followState,
    required this.followSpeedFactor,
    required this.melodyTrackIndex,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final data = PerformanceConsoleData.fromPlayer(
      player: player,
      isFollowMode: isFollowMode,
      followState: followState,
      followSpeedFactor: followSpeedFactor,
      melodyTrackIndex: melodyTrackIndex,
    );

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
                key: PlayerUiKeys.followModeSwitch,
                value: isFollowMode,
                onChanged: (_) => onToggleFollow(),
              ),
            ],
          ),
          Text('跟随与排练', style: luxuryDisplayStyle(context, size: 28)),
          const SizedBox(height: 8),
          Text(
            data.note,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ConsoleCard(
                  label: '主旋律',
                  value: data.melodyLabel,
                  accent: melodyTrackIndex == null
                      ? LuxuryPalette.ruby
                      : LuxuryPalette.goldBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ConsoleCard(
                  label: data.speedMetricLabel,
                  value: data.speedLabel,
                  accent: data.accent,
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
                      color: data.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: data.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.waveform_path_ecg,
                          size: 18,
                          color: data.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data.liveStatusLabel,
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
                          key: PlayerUiKeys.manualSpeedSlider,
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
