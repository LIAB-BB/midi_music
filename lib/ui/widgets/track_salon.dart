import 'package:flutter/cupertino.dart';

import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import 'player_display_data.dart';
import 'player_helpers.dart';

/// 单条轨道磁贴
class TrackTile extends StatelessWidget {
  final TrackTileData data;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSetMelody;

  const TrackTile({
    super.key,
    required this.data,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onSetMelody,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: PlayerUiKeys.trackTile(data.index),
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: data.isMelody
            ? LuxuryPalette.gold.withValues(alpha: 0.08)
            : CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: data.isMelody
              ? LuxuryPalette.gold.withValues(alpha: 0.4)
              : LuxuryPalette.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CupertinoButton(
                key: PlayerUiKeys.trackMuteButton(data.index),
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                onPressed: onToggleMute,
                child: Icon(
                  data.isMuted
                      ? CupertinoIcons.speaker_slash_fill
                      : CupertinoIcons.speaker_2_fill,
                  size: 18,
                  color: data.isMuted
                      ? LuxuryPalette.textSubtle
                      : LuxuryPalette.goldBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: LuxuryPalette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                key: PlayerUiKeys.trackMelodyButton(data.index),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(30, 30),
                color: data.isMelody
                    ? LuxuryPalette.gold.withValues(alpha: 0.16)
                    : CupertinoColors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                onPressed: onSetMelody,
                child: Text(
                  data.melodyActionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: data.isMelody
                        ? LuxuryPalette.goldBright
                        : LuxuryPalette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: LuxuryPalette.divider),
                ),
                child: Text(
                  data.muteStatusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: data.isMuted
                        ? LuxuryPalette.textSubtle
                        : LuxuryPalette.goldBright,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoSlider(
                  key: PlayerUiKeys.trackVolumeSlider(data.index),
                  value: data.isMuted ? 0.0 : data.volume,
                  onChanged: data.isMuted ? null : onVolumeChanged,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                data.volumeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: LuxuryPalette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 轨道总谱：轨道列表、静音/音量/主旋律管理
class TrackSalon extends StatelessWidget {
  final MidiPlayerController player;
  final int? melodyTrackIndex;
  final ValueChanged<int> onSetMelody;

  const TrackSalon({
    super.key,
    required this.player,
    required this.melodyTrackIndex,
    required this.onSetMelody,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = player.songData?.noteTracks ?? [];

    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionEyebrow(label: 'TRACK SALON'),
                  SizedBox(height: 10),
                ],
              ),
              const Spacer(),
              Text(
                '${tracks.length} 条',
                style: const TextStyle(
                  fontSize: 13,
                  color: LuxuryPalette.textMuted,
                ),
              ),
            ],
          ),
          Text('轨道总谱', style: luxuryDisplayStyle(context, size: 28)),
          const SizedBox(height: 8),
          const Text(
            '在这里处理主旋律、静音和混音平衡。',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          if (tracks.isEmpty)
            const Text(
              '当前曲目没有可控制的音符轨道。',
              style: TextStyle(color: LuxuryPalette.textMuted),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tracks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final track = tracks[index];
                final data = TrackTileData.fromTrack(
                  track: track,
                  isMelody: track.index == melodyTrackIndex,
                );
                return TrackTile(
                  data: data,
                  onToggleMute: () => player.toggleTrackMute(track.index),
                  onVolumeChanged: (value) =>
                      player.setTrackVolume(track.index, value),
                  onSetMelody: () => onSetMelody(track.index),
                );
              },
            ),
        ],
      ),
    );
  }
}
