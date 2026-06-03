import 'package:flutter/cupertino.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../theme/luxury_theme.dart';

class PlayerUiKeys {
  const PlayerUiKeys._();

  static const stageProgressSlider = ValueKey<String>(
    'player.stage.progressSlider',
  );
  static const transportStopButton = ValueKey<String>('player.transport.stop');
  static const transportBackwardButton = ValueKey<String>(
    'player.transport.backward',
  );
  static const transportPlayPauseButton = ValueKey<String>(
    'player.transport.playPause',
  );
  static const transportForwardButton = ValueKey<String>(
    'player.transport.forward',
  );
  static const transportResetButton = ValueKey<String>(
    'player.transport.reset',
  );
  static const followModeSwitch = ValueKey<String>('player.follow.switch');
  static const manualSpeedSlider = ValueKey<String>('player.speed.slider');

  static ValueKey<String> trackTile(int trackIndex) =>
      ValueKey<String>('player.track.$trackIndex.tile');

  static ValueKey<String> trackMuteButton(int trackIndex) =>
      ValueKey<String>('player.track.$trackIndex.mute');

  static ValueKey<String> trackMelodyButton(int trackIndex) =>
      ValueKey<String>('player.track.$trackIndex.melody');

  static ValueKey<String> trackVolumeSlider(int trackIndex) =>
      ValueKey<String>('player.track.$trackIndex.volume');
}

class HomeUiKeys {
  const HomeUiKeys._();

  static const diagnosticsButton = ValueKey<String>('home.diagnostics');
  static const importMidiButton = ValueKey<String>('home.importMidi');
  static const continueSongButton = ValueKey<String>('home.continueSong');
  static const soundfontRetryButton = ValueKey<String>('home.soundfont.retry');

  static ValueKey<String> demoSongButton(String fileName) =>
      ValueKey<String>('home.demo.$fileName');
}

class DiagnosticsUiKeys {
  const DiagnosticsUiKeys._();

  static const soundfontRetryButton = ValueKey<String>(
    'diagnostics.soundfont.retry',
  );
  static const permissionRefreshButton = ValueKey<String>(
    'diagnostics.permission.refresh',
  );
  static const openSettingsButton = ValueKey<String>(
    'diagnostics.permission.settings',
  );
}

/// 跟随状态对应的强调色
Color followAccent(bool isFollowMode, FollowModeState state, bool isPlaying) {
  if (!isFollowMode) {
    return isPlaying ? LuxuryPalette.goldBright : LuxuryPalette.gold;
  }
  return switch (state) {
    FollowModeState.following => LuxuryPalette.emerald,
    FollowModeState.waitingForOnset => LuxuryPalette.ruby,
    FollowModeState.idle => LuxuryPalette.goldBright,
  };
}

/// 跟随状态对应的中文标签
String followLabel(bool isFollowMode, FollowModeState state, bool isPlaying) {
  if (!isFollowMode) {
    return isPlaying ? '手动播放' : '待机';
  }
  return switch (state) {
    FollowModeState.following => '实时跟随',
    FollowModeState.waitingForOnset => '等待起拍',
    FollowModeState.idle => '跟随待命',
  };
}

/// 秒数格式化为 m:ss
String formatClock(double seconds) {
  final totalSeconds = seconds.clamp(0.0, double.infinity).round();
  final minutes = totalSeconds ~/ 60;
  final remainSeconds = totalSeconds % 60;
  return '$minutes:${remainSeconds.toString().padLeft(2, '0')}';
}

/// 从文件名提取可读曲名
String displaySongTitle(String fileName) {
  final stripped = fileName.replaceAll(
    RegExp(r'\.mid$', caseSensitive: false),
    '',
  );
  final normalized = stripped.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return normalized.isEmpty ? fileName : normalized;
}

/// 通用小节标签
class SectionEyebrow extends StatelessWidget {
  final String label;

  const SectionEyebrow({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 2.1,
        color: LuxuryPalette.textSubtle,
      ),
    );
  }
}

/// 装饰分隔线
class OrnamentLine extends StatelessWidget {
  const OrnamentLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 36, height: 2, color: LuxuryPalette.goldBright),
        const SizedBox(width: 10),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: LuxuryPalette.goldBright,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: LuxuryPalette.divider)),
      ],
    );
  }
}

/// 状态徽章
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
