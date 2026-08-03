import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/diagnostics/app_error.dart';
import '../../core/diagnostics/diagnostic_logger.dart';
import '../../core/midi/midi_player.dart';
import '../../core/settings/app_settings.dart';
import '../theme/luxury_theme.dart';
import '../widgets/player_helpers.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        border: null,
        previousPageTitle: '返回',
        middle: Text('设置'),
      ),
      child: LuxuryBackdrop(
        child: SafeArea(
          bottom: false,
          child: Consumer2<AppSettingsController, MidiPlayerController>(
            builder: (context, settings, player, _) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SettingsHeader(),
                    const SizedBox(height: 14),
                    _SoundfontSettingsCard(player: player),
                    const SizedBox(height: 14),
                    _PlaybackSettingsCard(settings: settings, player: player),
                    const SizedBox(height: 14),
                    _FollowSettingsCard(settings: settings),
                    const SizedBox(height: 14),
                    const _MidiInputCard(),
                    const SizedBox(height: 14),
                    _DiagnosticsCard(logger: DiagnosticLogger.instance),
                    const SizedBox(height: 14),
                    _ResetCard(settings: settings),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow(label: 'SETUP'),
          const SizedBox(height: 14),
          Text('排练偏好', style: luxuryDisplayStyle(context, size: 34)),
          const SizedBox(height: 10),
          const Text(
            '集中管理播放、音色和 USB MIDI 跟随参数。设置会在下次开启跟随时生效。',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: LuxuryPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundfontSettingsCard extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontSettingsCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final progressPercent = (player.soundfontDownloadProgress * 100)
        .clamp(0, 100)
        .round();
    final accent = switch (player.soundfontState) {
      SoundfontSetupState.ready => LuxuryPalette.emerald,
      SoundfontSetupState.failed => LuxuryPalette.ruby,
      _ => LuxuryPalette.goldBright,
    };
    final stateText = switch (player.soundfontState) {
      SoundfontSetupState.ready => '已就绪',
      SoundfontSetupState.failed => '下载失败',
      SoundfontSetupState.downloading => '下载中 $progressPercent%',
      SoundfontSetupState.checking => '检查中',
      SoundfontSetupState.idle => '准备中',
    };
    final detailText = switch (player.soundfontState) {
      SoundfontSetupState.ready => '本地音色已就绪，可以直接播放 MIDI。',
      SoundfontSetupState.failed =>
        player.soundfontErrorMessage ?? '音色库准备失败，请检查网络后重试。',
      SoundfontSetupState.downloading => '正在下载 TimGM6mb.sf2。',
      SoundfontSetupState.checking => '正在检查本地音色。',
      SoundfontSetupState.idle => '等待准备音色。',
    };

    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(
            label: 'SOUNDFONT',
            title: '音色库',
            badge: StatusBadge(label: stateText, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            detailText,
            style: const TextStyle(
              fontSize: 14,
              height: 1.45,
              color: LuxuryPalette.textMuted,
            ),
          ),
          if (player.soundfontState == SoundfontSetupState.downloading) ...[
            const SizedBox(height: 14),
            _ProgressBar(progress: player.soundfontDownloadProgress),
          ],
          if (player.soundfontState == SoundfontSetupState.failed) ...[
            const SizedBox(height: 14),
            _SmallActionButton(
              label: '重新准备',
              icon: CupertinoIcons.arrow_clockwise,
              onPressed: player.retrySoundfontSetup,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaybackSettingsCard extends StatelessWidget {
  final AppSettingsController settings;
  final MidiPlayerController player;

  const _PlaybackSettingsCard({required this.settings, required this.player});

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(label: 'PLAYBACK', title: '播放'),
          const SizedBox(height: 14),
          _ValueSlider(
            title: '默认速度',
            description: '新曲目的初始播放倍率。',
            value: settings.defaultPlaybackSpeed,
            min: 0.25,
            max: 4.0,
            divisions: 15,
            valueText: '${settings.defaultPlaybackSpeed.toStringAsFixed(2)}x',
            onChanged: settings.setDefaultPlaybackSpeed,
          ),
          const SizedBox(height: 12),
          _SmallActionButton(
            label: '应用到当前曲目',
            icon: CupertinoIcons.slider_horizontal_3,
            onPressed: () => player.setSpeed(settings.defaultPlaybackSpeed),
          ),
        ],
      ),
    );
  }
}

class _FollowSettingsCard extends StatelessWidget {
  final AppSettingsController settings;

  const _FollowSettingsCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(label: 'FOLLOW', title: '实时跟随'),
          const SizedBox(height: 14),
          _ValueSlider(
            title: '音符匹配容差',
            description: 'USB MIDI 默认精确匹配；调高会放宽错音判定。',
            value: settings.noteMatchTolerance.toDouble(),
            min: 0,
            max: 4,
            divisions: 4,
            valueText: '${settings.noteMatchTolerance} 半音',
            onChanged: (value) => settings.setNoteMatchTolerance(value.round()),
          ),
          const SizedBox(height: 16),
          _SettingsSwitchRow(
            title: '允许跨八度匹配',
            description: '开启后，同名音跨八度也会被视为匹配。',
            value: settings.allowOctaveError,
            onChanged: (value) => settings.setAllowOctaveError(value: value),
          ),
          const SizedBox(height: 16),
          _ValueSlider(
            title: '可信速度下限',
            description: '低于该倍率的测量会被忽略。',
            value: settings.minMeasuredSpeedFactor,
            min: 0.4,
            max: 1.0,
            divisions: 12,
            valueText: '${settings.minMeasuredSpeedFactor.toStringAsFixed(2)}x',
            onChanged: settings.setMinMeasuredSpeedFactor,
          ),
          const SizedBox(height: 16),
          _ValueSlider(
            title: '可信速度上限',
            description: '高于该倍率的测量会被忽略。',
            value: settings.maxMeasuredSpeedFactor,
            min: 1.0,
            max: 2.2,
            divisions: 12,
            valueText: '${settings.maxMeasuredSpeedFactor.toStringAsFixed(2)}x',
            onChanged: settings.setMaxMeasuredSpeedFactor,
          ),
          const SizedBox(height: 16),
          _ValueSlider(
            title: '休止等待阈值',
            description: '谱面间隔超过该时长时，暂停等待下一次起拍。',
            value: settings.restThresholdSeconds,
            min: 0.5,
            max: 3.0,
            divisions: 10,
            valueText: '${settings.restThresholdSeconds.toStringAsFixed(1)} 秒',
            onChanged: settings.setRestThresholdSeconds,
          ),
        ],
      ),
    );
  }
}

class _MidiInputCard extends StatelessWidget {
  const _MidiInputCard();

  @override
  Widget build(BuildContext context) {
    return const LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(label: 'MIDI INPUT', title: '电子琴输入'),
          SizedBox(height: 12),
          Text(
            '当前 demo 仅使用 iOS USB MIDI。电子琴自行发声，App 接收按键并播放其余伴奏，不采集麦克风音频。',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: LuxuryPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  final DiagnosticLogger logger;

  const _DiagnosticsCard({required this.logger});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: logger,
      builder: (context, _) {
        final latestError = logger.latestError;
        final errorCount = logger.recentErrors.length;
        final accent = _diagnosticAccent(latestError);
        final statusText = errorCount == 0 ? '无异常' : '$errorCount 条';

        return LuxuryPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(
                label: 'DIAGNOSTICS',
                title: '诊断',
                badge: StatusBadge(label: statusText, color: accent),
              ),
              const SizedBox(height: 12),
              Text(
                latestError == null
                    ? '暂无诊断记录。导入、播放或跟随异常会显示在这里。'
                    : latestError.userMessage,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: LuxuryPalette.textMuted,
                ),
              ),
              if (latestError != null) ...[
                const SizedBox(height: 10),
                _DiagnosticMeta(error: latestError),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _SmallActionButton(
                    label: '复制诊断',
                    icon: CupertinoIcons.doc_on_clipboard,
                    onPressed: () => unawaited(_copyDiagnostics(context)),
                  ),
                  _SmallActionButton(
                    label: '清空记录',
                    icon: CupertinoIcons.trash,
                    onPressed: errorCount == 0
                        ? () => _showDiagnosticsDialog(
                            context,
                            '暂无记录',
                            '当前没有可清空的诊断记录。',
                          )
                        : () => unawaited(_clearDiagnostics(context)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '诊断只包含错误代码、时间和脱敏技术信息，不包含录音或 MIDI 内容。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: LuxuryPalette.textSubtle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyDiagnostics(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: logger.exportText()));
    if (!context.mounted) return;
    _showDiagnosticsDialog(context, '诊断已复制', '可粘贴到反馈或问题报告中。');
  }

  Future<void> _clearDiagnostics(BuildContext context) async {
    await logger.clear();
    if (!context.mounted) return;
    _showDiagnosticsDialog(context, '已清空诊断', '最近错误记录已清空。');
  }

  Color _diagnosticAccent(AppError? error) {
    if (error == null) return LuxuryPalette.emerald;
    return switch (error.severity) {
      AppErrorSeverity.info => LuxuryPalette.emerald,
      AppErrorSeverity.warning => LuxuryPalette.goldBright,
      AppErrorSeverity.error || AppErrorSeverity.fatal => LuxuryPalette.ruby,
    };
  }
}

class _DiagnosticMeta extends StatelessWidget {
  final AppError error;

  const _DiagnosticMeta({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.code,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: LuxuryPalette.goldBright,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${error.source.name} · ${error.severity.name} · ${_formatDiagnosticTime(error.timestamp)}',
            style: const TextStyle(
              fontSize: 11,
              height: 1.35,
              color: LuxuryPalette.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDiagnosticTime(DateTime timestamp) {
  final local = timestamp.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

void _showDiagnosticsDialog(
  BuildContext context,
  String title,
  String message,
) {
  unawaited(
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    ),
  );
}

class _ResetCard extends StatelessWidget {
  final AppSettingsController settings;

  const _ResetCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '跟随参数调乱时，可恢复推荐默认值。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: LuxuryPalette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 14),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: LuxuryPalette.ruby.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            onPressed: () => _confirmReset(context),
            child: const Text(
              '恢复默认',
              style: TextStyle(fontSize: 13, color: LuxuryPalette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('恢复默认设置？'),
        content: const Text('这会重置播放默认速度和跟随模式参数。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('恢复'),
            onPressed: () {
              settings.resetToDefaults();
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String label;
  final String title;
  final Widget? badge;

  const _SectionHeading({required this.label, required this.title, this.badge});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionEyebrow(label: label),
              const SizedBox(height: 10),
              Text(title, style: luxuryDisplayStyle(context, size: 26)),
            ],
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 12), badge!],
      ],
    );
  }
}

class _ValueSlider extends StatelessWidget {
  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;

  const _ValueSlider({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LuxuryPalette.textPrimary,
                  ),
                ),
              ),
              Text(
                valueText,
                style: const TextStyle(
                  fontSize: 13,
                  color: LuxuryPalette.goldBright,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: LuxuryPalette.textSubtle,
            ),
          ),
          const SizedBox(height: 8),
          CupertinoSlider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LuxuryPalette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: LuxuryPalette.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SmallActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _SmallActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LuxuryPalette.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxuryPalette.gold.withValues(alpha: 0.28)),
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: BorderRadius.circular(18),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: LuxuryPalette.goldBright),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: LuxuryPalette.goldBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  double get _safeProgress {
    if (progress < 0.0) return 0.0;
    if (progress > 1.0) return 1.0;
    return progress;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 7,
        color: CupertinoColors.white.withValues(alpha: 0.06),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: _safeProgress,
            child: Container(color: LuxuryPalette.goldBright),
          ),
        ),
      ),
    );
  }
}
