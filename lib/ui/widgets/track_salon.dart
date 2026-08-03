import 'package:flutter/cupertino.dart';

import '../../core/midi/midi_player.dart';
import '../../models/midi_track.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';

/// 单条轨道磁贴
class TrackTile extends StatelessWidget {
  final MidiTrackInfo track;
  final bool isPerformerTrack;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSetMelody;

  const TrackTile({
    super.key,
    required this.track,
    required this.isPerformerTrack,
    required this.onToggleMute,
    required this.onVolumeChanged,
    required this.onSetMelody,
  });

  @override
  Widget build(BuildContext context) {
    final title = track.name.isNotEmpty ? track.name : '轨道 ${track.index + 1}';
    final channels = track.channels.toList()..sort();
    final channelText = channels.isEmpty ? '无通道' : 'CH ${channels.join(', ')}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: isPerformerTrack
            ? LuxuryPalette.gold.withValues(alpha: 0.08)
            : CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPerformerTrack
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
                padding: EdgeInsets.zero,
                minimumSize: const Size(34, 34),
                onPressed: onToggleMute,
                child: Icon(
                  track.isMuted
                      ? CupertinoIcons.speaker_slash_fill
                      : CupertinoIcons.speaker_2_fill,
                  size: 18,
                  color: track.isMuted
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
                      title,
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
                      '$channelText · ${track.noteCount} 音符',
                      style: const TextStyle(
                        fontSize: 12,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(30, 30),
                color: isPerformerTrack
                    ? LuxuryPalette.gold.withValues(alpha: 0.16)
                    : CupertinoColors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                onPressed: onSetMelody,
                child: Text(
                  isPerformerTrack ? '电子琴声部' : '加入电子琴声部',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPerformerTrack
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
                  track.isMuted ? '静音中' : '已开启',
                  style: TextStyle(
                    fontSize: 11,
                    color: track.isMuted
                        ? LuxuryPalette.textSubtle
                        : LuxuryPalette.goldBright,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoSlider(
                  value: track.isMuted ? 0.0 : track.volume,
                  onChanged: track.isMuted ? null : onVolumeChanged,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(track.volume * 100).round()}%',
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

/// 轨道总谱：轨道列表、静音/音量和电子琴声部组管理
class TrackSalon extends StatelessWidget {
  final MidiPlayerController player;
  final Set<int> performerTrackIndices;
  final ValueChanged<int> onSetMelody;

  const TrackSalon({
    super.key,
    required this.player,
    required this.performerTrackIndices,
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
          Text('轨道', style: luxuryDisplayStyle(context, size: 28)),
          const SizedBox(height: 8),
          const Text(
            '选择一个或多个由电子琴演奏的轨道；跟随时这些轨道会一起静音。',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          if (tracks.isEmpty)
            const Text(
              '当前曲目没有音符轨道。',
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
                return TrackTile(
                  track: track,
                  isPerformerTrack: performerTrackIndices.contains(track.index),
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
