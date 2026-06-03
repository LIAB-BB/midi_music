import 'package:flutter/cupertino.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../../core/midi/midi_player.dart';
import '../../models/midi_track.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';

class StageConsoleData {
  final String title;
  final String statusLabel;
  final Color accent;
  final String speedLabel;
  final String speedCaption;
  final String bpmLabel;
  final String durationLabel;
  final String trackCountLabel;
  final String currentTimeLabel;
  final String totalDurationLabel;
  final String remainingLabel;
  final double progress;
  final double totalDuration;

  const StageConsoleData({
    required this.title,
    required this.statusLabel,
    required this.accent,
    required this.speedLabel,
    required this.speedCaption,
    required this.bpmLabel,
    required this.durationLabel,
    required this.trackCountLabel,
    required this.currentTimeLabel,
    required this.totalDurationLabel,
    required this.remainingLabel,
    required this.progress,
    required this.totalDuration,
  });

  factory StageConsoleData.fromPlayer({
    required MidiPlayerController player,
    required bool isFollowMode,
    required FollowModeState followState,
    required double followSpeedFactor,
  }) {
    final song = player.songData;
    if (song == null) {
      throw StateError('StageConsoleData requires a loaded song');
    }

    final accent = followAccent(isFollowMode, followState, player.isPlaying);
    final speed = isFollowMode ? followSpeedFactor : player.playbackSpeed;
    final remaining = (player.totalDuration - player.currentTime).clamp(
      0.0,
      player.totalDuration,
    );

    return StageConsoleData(
      title: displaySongTitle(song.fileName),
      statusLabel: followLabel(isFollowMode, followState, player.isPlaying),
      accent: accent,
      speedLabel: '${speed.toStringAsFixed(2)}x',
      speedCaption: isFollowMode ? 'FOLLOW' : 'TEMPO',
      bpmLabel: player.currentBpm.toStringAsFixed(0),
      durationLabel: formatClock(song.totalDuration),
      trackCountLabel: '${song.noteTracks.length}',
      currentTimeLabel: formatClock(player.currentTime),
      totalDurationLabel: formatClock(player.totalDuration),
      remainingLabel: '-${formatClock(remaining)}',
      progress: player.progress,
      totalDuration: player.totalDuration,
    );
  }

  double get titleSize {
    if (title.length > 24) return 26.0;
    if (title.length > 16) return 30.0;
    return 34.0;
  }
}

class PerformanceConsoleData {
  final Color accent;
  final String note;
  final String melodyLabel;
  final String speedLabel;
  final String speedMetricLabel;
  final String liveStatusLabel;

  const PerformanceConsoleData({
    required this.accent,
    required this.note,
    required this.melodyLabel,
    required this.speedLabel,
    required this.speedMetricLabel,
    required this.liveStatusLabel,
  });

  factory PerformanceConsoleData.fromPlayer({
    required MidiPlayerController player,
    required bool isFollowMode,
    required FollowModeState followState,
    required double followSpeedFactor,
    required int? melodyTrackIndex,
  }) {
    final accent = followAccent(isFollowMode, followState, player.isPlaying);
    final note = switch (followState) {
      FollowModeState.following => '伴奏正在贴合你的演奏速度。',
      FollowModeState.waitingForOnset => '已进入跟随模式，等待新的起拍。',
      FollowModeState.idle => isFollowMode ? '跟随已开启，等待演奏输入。' : '当前为手动排练模式。',
    };

    return PerformanceConsoleData(
      accent: accent,
      note: note,
      melodyLabel: melodyTrackIndex == null
          ? '未指定'
          : 'Track ${melodyTrackIndex + 1}',
      speedLabel: isFollowMode
          ? '${followSpeedFactor.toStringAsFixed(2)}x'
          : '${player.playbackSpeed.toStringAsFixed(2)}x',
      speedMetricLabel: isFollowMode ? '跟随倍率' : '速度倍率',
      liveStatusLabel: followLabel(true, followState, player.isPlaying),
    );
  }
}

class TransportDeckData {
  final bool canPlay;
  final bool isPlaying;
  final double currentTime;
  final String toneLabel;
  final String toneValue;
  final String modeValue;

  const TransportDeckData({
    required this.canPlay,
    required this.isPlaying,
    required this.currentTime,
    required this.toneLabel,
    required this.toneValue,
    required this.modeValue,
  });

  factory TransportDeckData.fromPlayer(MidiPlayerController player) {
    final canPlay = player.isSoundfontReady && player.songData != null;
    return TransportDeckData(
      canPlay: canPlay,
      isPlaying: player.isPlaying,
      currentTime: player.currentTime,
      toneLabel: canPlay ? 'Tone Ready' : 'Tone Pending',
      toneValue: canPlay ? '可直接演奏' : '等待音色加载',
      modeValue: player.isPlaying ? '舞台运行中' : '待机',
    );
  }
}

class SoundfontStatusData {
  final String pillText;
  final String lineText;
  final String bannerText;
  final Color accent;
  final IconData bannerIcon;
  final bool canRetry;

  const SoundfontStatusData({
    required this.pillText,
    required this.lineText,
    required this.bannerText,
    required this.accent,
    required this.bannerIcon,
    required this.canRetry,
  });

  factory SoundfontStatusData.fromPlayer(MidiPlayerController player) {
    final progressPercent = (player.soundfontDownloadProgress * 100)
        .clamp(0, 100)
        .round();
    final lineText = switch (player.soundfontState) {
      SoundfontSetupState.downloading => '正在自动下载音色库 $progressPercent%',
      SoundfontSetupState.failed => player.soundfontErrorMessage ?? '音色库自动下载失败',
      SoundfontSetupState.checking => '正在检查本地音色库',
      SoundfontSetupState.idle => '正在准备音色库',
      SoundfontSetupState.ready => '音色库已就绪',
    };

    return SoundfontStatusData(
      pillText: switch (player.soundfontState) {
        SoundfontSetupState.ready => '音色已就绪',
        SoundfontSetupState.failed => '下载失败',
        SoundfontSetupState.downloading => '下载中',
        SoundfontSetupState.checking => '检查中',
        SoundfontSetupState.idle => '准备中',
      },
      lineText: lineText,
      bannerText: switch (player.soundfontState) {
        SoundfontSetupState.downloading => '正在自动下载演出音色 $progressPercent%',
        SoundfontSetupState.failed =>
          player.soundfontErrorMessage ?? '演出音色下载失败，请稍后重试。',
        SoundfontSetupState.checking => '正在检查本地演出音色。',
        SoundfontSetupState.idle => '正在准备演出音色。',
        SoundfontSetupState.ready => '演出音色已就绪。',
      },
      accent: switch (player.soundfontState) {
        SoundfontSetupState.ready => LuxuryPalette.emerald,
        SoundfontSetupState.failed => LuxuryPalette.ruby,
        SoundfontSetupState.downloading => LuxuryPalette.goldBright,
        _ => LuxuryPalette.gold,
      },
      bannerIcon: switch (player.soundfontState) {
        SoundfontSetupState.failed =>
          CupertinoIcons.exclamationmark_triangle_fill,
        SoundfontSetupState.ready => CupertinoIcons.check_mark_circled_solid,
        _ => CupertinoIcons.cloud_download_fill,
      },
      canRetry: player.soundfontState == SoundfontSetupState.failed,
    );
  }
}

class TrackTileData {
  final int index;
  final String title;
  final String subtitle;
  final bool isMuted;
  final double volume;
  final bool isMelody;
  final String muteStatusLabel;
  final String melodyActionLabel;
  final String volumeLabel;

  const TrackTileData({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.isMuted,
    required this.volume,
    required this.isMelody,
    required this.muteStatusLabel,
    required this.melodyActionLabel,
    required this.volumeLabel,
  });

  factory TrackTileData.fromTrack({
    required MidiTrackInfo track,
    required bool isMelody,
  }) {
    final title = track.name.isNotEmpty ? track.name : '轨道 ${track.index + 1}';
    final channels = track.channels.toList()..sort();
    final channelText = channels.isEmpty ? '无通道' : 'CH ${channels.join(', ')}';

    return TrackTileData(
      index: track.index,
      title: title,
      subtitle: '$channelText · ${track.noteCount} 音符',
      isMuted: track.isMuted,
      volume: track.volume,
      isMelody: isMelody,
      muteStatusLabel: track.isMuted ? '静音中' : '已开启',
      melodyActionLabel: isMelody ? '主旋律' : '设为主旋律',
      volumeLabel: '${(track.volume * 100).round()}%',
    );
  }
}
