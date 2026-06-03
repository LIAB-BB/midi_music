import 'package:flutter/cupertino.dart';

import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import 'player_display_data.dart';
import 'player_helpers.dart';

/// 运输控制按钮
class TransportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlighted;
  final bool large;
  final Key? buttonKey;

  const TransportButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
    this.large = false,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 72.0 : 56.0;
    final iconSize = large ? 28.0 : 20.0;
    final enabled = onPressed != null;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled && highlighted
                ? const LinearGradient(
                    colors: [Color(0xFFE7CF99), Color(0xFFC5964F)],
                  )
                : const LinearGradient(
                    colors: [LuxuryPalette.panelRaised, LuxuryPalette.panel],
                  ),
            border: Border.all(
              color: enabled && highlighted
                  ? LuxuryPalette.goldBright
                  : LuxuryPalette.divider,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    (enabled && highlighted
                            ? LuxuryPalette.gold
                            : CupertinoColors.black)
                        .withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: CupertinoButton(
            key: buttonKey,
            padding: EdgeInsets.zero,
            minimumSize: Size.square(size),
            borderRadius: BorderRadius.circular(size / 2),
            onPressed: onPressed,
            child: Icon(
              icon,
              size: iconSize,
              color: enabled
                  ? (highlighted
                        ? CupertinoColors.black
                        : LuxuryPalette.textPrimary)
                  : LuxuryPalette.textSubtle,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: enabled ? LuxuryPalette.textMuted : LuxuryPalette.textSubtle,
          ),
        ),
      ],
    );
  }
}

/// 控制台注释条
class ConsoleNote extends StatelessWidget {
  final String label;
  final String value;

  const ConsoleNote({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.03),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LuxuryPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 运输控制区
class TransportDeck extends StatelessWidget {
  final MidiPlayerController player;
  final ValueChanged<double>? onSeek;

  const TransportDeck({super.key, required this.player, this.onSeek});

  @override
  Widget build(BuildContext context) {
    final data = TransportDeckData.fromPlayer(player);
    final transportButtons = [
      TransportButton(
        buttonKey: PlayerUiKeys.transportStopButton,
        icon: CupertinoIcons.stop_fill,
        label: '停止',
        onPressed: data.canPlay ? player.stop : null,
      ),
      TransportButton(
        buttonKey: PlayerUiKeys.transportBackwardButton,
        icon: CupertinoIcons.gobackward_10,
        label: '回退',
        onPressed: data.canPlay ? () => _seekTo(data.currentTime - 10) : null,
      ),
      TransportButton(
        buttonKey: PlayerUiKeys.transportPlayPauseButton,
        icon: data.isPlaying
            ? CupertinoIcons.pause_fill
            : CupertinoIcons.play_fill,
        label: data.isPlaying ? '暂停' : '播放',
        highlighted: true,
        large: true,
        onPressed: data.canPlay
            ? () {
                if (data.isPlaying) {
                  player.pause();
                } else {
                  player.play();
                }
              }
            : null,
      ),
      TransportButton(
        buttonKey: PlayerUiKeys.transportForwardButton,
        icon: CupertinoIcons.goforward_10,
        label: '快进',
        onPressed: data.canPlay ? () => _seekTo(data.currentTime + 10) : null,
      ),
      TransportButton(
        buttonKey: PlayerUiKeys.transportResetButton,
        icon: CupertinoIcons.arrow_counterclockwise,
        label: '归零',
        onPressed: data.canPlay ? () => _seekTo(0) : null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 360) {
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      transportButtons[0],
                      transportButtons[1],
                      transportButtons[2],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [transportButtons[3], transportButtons[4]],
                  ),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: transportButtons,
            );
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ConsoleNote(label: data.toneLabel, value: data.toneValue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ConsoleNote(label: 'Mode', value: data.modeValue),
            ),
          ],
        ),
      ],
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
