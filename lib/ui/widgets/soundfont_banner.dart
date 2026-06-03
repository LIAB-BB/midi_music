import 'package:flutter/cupertino.dart';

import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import 'player_display_data.dart';

/// SoundFont 加载状态横幅
class SoundfontBanner extends StatelessWidget {
  final MidiPlayerController player;

  const SoundfontBanner({super.key, required this.player});

  @override
  Widget build(BuildContext context) {
    final data = SoundfontStatusData.fromPlayer(player);

    return LuxuryPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Icon(data.bannerIcon, color: data.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              data.bannerText,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: LuxuryPalette.textMuted,
              ),
            ),
          ),
          if (data.canRetry) ...[
            const SizedBox(width: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              onPressed: player.retrySoundfontSetup,
              child: const Text(
                '重试',
                style: TextStyle(fontSize: 13, color: LuxuryPalette.goldBright),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
