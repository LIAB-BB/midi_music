import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/input/midi_keyboard_input.dart';
import '../../core/input/performance_input.dart';
import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import '../widgets/luxury_controls.dart';
import '../widgets/player_display_data.dart';
import '../widgets/player_helpers.dart';

const _kAppVersionLabel = '1.0.0+1';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final MidiKeyboardInput _midiInput = MidiKeyboardInput();

  StreamSubscription<MidiInputSnapshot>? _midiSubscription;
  PermissionStatus? _microphoneStatus;
  SoundfontCacheInfo? _soundfontCacheInfo;
  MidiInputSnapshot _midiSnapshot = const MidiInputSnapshot();
  bool _isRefreshingPermission = false;
  bool _isStartingMidi = false;

  @override
  void initState() {
    super.initState();
    _midiSubscription = _midiInput.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() => _midiSnapshot = snapshot);
    });
    _refreshPermissionStatus();
    _refreshSoundfontCacheInfo();
  }

  @override
  void dispose() {
    unawaited(_midiSubscription?.cancel());
    unawaited(_midiInput.dispose());
    super.dispose();
  }

  Future<void> _refreshPermissionStatus() async {
    setState(() => _isRefreshingPermission = true);
    final status = await Permission.microphone.status;
    if (!mounted) return;
    setState(() {
      _microphoneStatus = status;
      _isRefreshingPermission = false;
    });
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
    if (!mounted) return;
    await _refreshPermissionStatus();
  }

  Future<void> _refreshSoundfontCacheInfo() async {
    final player = context.read<MidiPlayerController>();
    final cacheInfo = await player.inspectSoundfontCache();
    if (!mounted) return;
    setState(() => _soundfontCacheInfo = cacheInfo);
  }

  Future<void> _retrySoundfontSetup(MidiPlayerController player) async {
    await player.retrySoundfontSetup();
    if (!mounted) return;
    await _refreshSoundfontCacheInfo();
  }

  Future<void> _startMidiProbe() async {
    setState(() => _isStartingMidi = true);
    await _midiInput.start();
    if (!mounted) return;
    setState(() => _isStartingMidi = false);
  }

  Future<void> _confirmClearSoundfontCache(MidiPlayerController player) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('清理音色缓存？'),
        content: const Text('这会删除本地 SoundFont 文件。下次准备音色时需要重新下载或重新加载。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await player.clearSoundfontCache();
    if (!mounted) return;
    await _refreshSoundfontCacheInfo();
  }

  Future<void> _copyDiagnosticsReport(
    MidiPlayerController player,
    SoundfontStatusData soundfont,
    _PermissionDisplayData permission,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: _buildDiagnosticsReport(
          player: player,
          soundfont: soundfont,
          permission: permission,
          cacheInfo: _soundfontCacheInfo,
          midiSnapshot: _midiSnapshot,
        ),
      ),
    );
    if (!mounted) return;

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('已复制'),
        content: const Text('诊断信息已复制到剪贴板，可以直接粘贴给测试负责人。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  String _buildDiagnosticsReport({
    required MidiPlayerController player,
    required SoundfontStatusData soundfont,
    required _PermissionDisplayData permission,
    required SoundfontCacheInfo? cacheInfo,
    required MidiInputSnapshot midiSnapshot,
  }) {
    final song = player.songData;
    return [
      'MIDI 伴奏 App 诊断信息',
      '版本: $_kAppVersionLabel',
      '音色状态: ${soundfont.bannerText}',
      '音色进度: ${(player.soundfontDownloadProgress * 100).round()}%',
      if (player.soundfontErrorMessage != null)
        '音色错误: ${player.soundfontErrorMessage}',
      '音色缓存: ${_formatCacheExists(cacheInfo)}',
      '音色缓存大小: ${_formatCacheSize(cacheInfo)}',
      if (cacheInfo?.path != null) '音色缓存路径: ${cacheInfo!.path}',
      if (cacheInfo?.errorMessage != null) '音色缓存错误: ${cacheInfo!.errorMessage}',
      '麦克风权限: ${permission.label}',
      'MIDI 输入状态: ${_formatMidiStatus(midiSnapshot)}',
      'MIDI 设备数: ${midiSnapshot.devices.length}',
      if (midiSnapshot.connectedDeviceName != null)
        'MIDI 已连接设备: ${midiSnapshot.connectedDeviceName}',
      if (midiSnapshot.lastEvent != null)
        'MIDI 最近事件: ${_formatMidiEvent(midiSnapshot.lastEvent!)}',
      if (midiSnapshot.lastError != null) 'MIDI 错误: ${midiSnapshot.lastError}',
      '当前曲目: ${song?.fileName ?? '未载入'}',
      '轨道数: ${song?.noteTracks.length ?? 0}',
      '曲目时长: ${formatClock(player.totalDuration)}',
      '播放状态: ${_playbackStateLabel(player.state)}',
      '播放位置: ${formatClock(player.currentTime)}',
      '音频上传: 不会上传麦克风音频',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MidiPlayerController>();
    final soundfont = SoundfontStatusData.fromPlayer(player);
    final permission = _PermissionDisplayData.fromStatus(_microphoneStatus);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        border: null,
        previousPageTitle: '首页',
        middle: Text('诊断'),
      ),
      child: LuxuryBackdrop(
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LuxuryPanel(
                  highlighted: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionEyebrow(label: 'APP DIAGNOSTICS'),
                      const SizedBox(height: 12),
                      Text(
                        '测试前检查',
                        style: luxuryDisplayStyle(context, size: 32),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '把这些状态截图或复制给开发者，可以更快定位播放、音色或麦克风问题。',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: LuxuryPalette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LuxuryActionButton(
                        key: DiagnosticsUiKeys.copyReportButton,
                        label: '复制诊断信息',
                        icon: CupertinoIcons.doc_on_clipboard,
                        onPressed: () => _copyDiagnosticsReport(
                          player,
                          soundfont,
                          permission,
                        ),
                        primary: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DiagnosticSection(
                  title: '音色引擎',
                  icon: soundfont.bannerIcon,
                  accent: soundfont.accent,
                  children: [
                    _DiagnosticRow(label: '状态', value: soundfont.bannerText),
                    _DiagnosticRow(
                      label: '进度',
                      value:
                          '${(player.soundfontDownloadProgress * 100).round()}%',
                    ),
                    if (player.soundfontErrorMessage != null)
                      _DiagnosticRow(
                        label: '错误',
                        value: player.soundfontErrorMessage!,
                      ),
                    _DiagnosticRow(
                      label: '缓存',
                      value: _formatCacheExists(_soundfontCacheInfo),
                    ),
                    _DiagnosticRow(
                      label: '大小',
                      value: _formatCacheSize(_soundfontCacheInfo),
                    ),
                    if (_soundfontCacheInfo?.path != null)
                      _DiagnosticRow(
                        label: '路径',
                        value: _soundfontCacheInfo!.path!,
                      ),
                    if (_soundfontCacheInfo?.errorMessage != null)
                      _DiagnosticRow(
                        label: '缓存错误',
                        value: _soundfontCacheInfo!.errorMessage!,
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LuxuryActionButton(
                            key: DiagnosticsUiKeys.soundfontRetryButton,
                            label: soundfont.canRetry ? '重试音色准备' : '重新检查音色',
                            icon: CupertinoIcons.arrow_clockwise,
                            onPressed: () => _retrySoundfontSetup(player),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LuxuryActionButton(
                            key: DiagnosticsUiKeys.soundfontClearCacheButton,
                            label: '清理缓存',
                            icon: CupertinoIcons.trash,
                            onPressed: () =>
                                _confirmClearSoundfontCache(player),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DiagnosticSection(
                  title: '麦克风权限',
                  icon: permission.icon,
                  accent: permission.accent,
                  children: [
                    _DiagnosticRow(label: '状态', value: permission.label),
                    const _DiagnosticRow(label: '用途', value: '跟随模式识别演奏起拍和速度'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: LuxuryActionButton(
                            key: DiagnosticsUiKeys.permissionRefreshButton,
                            label: _isRefreshingPermission ? '检查中' : '刷新状态',
                            icon: CupertinoIcons.arrow_clockwise,
                            onPressed: _refreshPermissionStatus,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LuxuryActionButton(
                            key: DiagnosticsUiKeys.openSettingsButton,
                            label: '系统设置',
                            icon: CupertinoIcons.settings_solid,
                            onPressed: _openSystemSettings,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DiagnosticSection(
                  title: 'MIDI 输入',
                  icon: CupertinoIcons.keyboard,
                  accent: _midiSnapshot.lastError == null
                      ? LuxuryPalette.emerald
                      : LuxuryPalette.ruby,
                  children: [
                    _DiagnosticRow(
                      label: '状态',
                      value: _formatMidiStatus(_midiSnapshot),
                    ),
                    _DiagnosticRow(
                      label: '设备',
                      value: _formatMidiDevices(_midiSnapshot.devices),
                    ),
                    _DiagnosticRow(
                      label: '连接',
                      value: _midiSnapshot.connectedDeviceName ?? '未连接',
                    ),
                    _DiagnosticRow(
                      label: '最近事件',
                      value: _midiSnapshot.lastEvent == null
                          ? '暂无'
                          : _formatMidiEvent(_midiSnapshot.lastEvent!),
                    ),
                    if (_midiSnapshot.lastError != null)
                      _DiagnosticRow(
                        label: '错误',
                        value: _midiSnapshot.lastError!,
                      ),
                    const SizedBox(height: 12),
                    LuxuryActionButton(
                      key: DiagnosticsUiKeys.midiProbeButton,
                      label: _isStartingMidi ? '检查中' : '检查 MIDI',
                      icon: CupertinoIcons.arrow_clockwise,
                      onPressed: _startMidiProbe,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _DiagnosticSection(
                  title: '当前曲目',
                  icon: CupertinoIcons.music_note_list,
                  accent: player.songData == null
                      ? LuxuryPalette.textSubtle
                      : LuxuryPalette.goldBright,
                  children: [
                    _DiagnosticRow(
                      label: '文件',
                      value: player.songData?.fileName ?? '未载入',
                    ),
                    _DiagnosticRow(
                      label: '轨道',
                      value: '${player.songData?.noteTracks.length ?? 0}',
                    ),
                    _DiagnosticRow(
                      label: '时长',
                      value: formatClock(player.totalDuration),
                    ),
                    _DiagnosticRow(
                      label: '播放状态',
                      value: _playbackStateLabel(player.state),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _DiagnosticSection(
                  title: '构建信息',
                  icon: CupertinoIcons.info_circle_fill,
                  accent: LuxuryPalette.emerald,
                  children: [
                    _DiagnosticRow(label: '版本', value: _kAppVersionLabel),
                    _DiagnosticRow(
                      label: '质量门禁',
                      value: 'flutter analyze / flutter test',
                    ),
                    _DiagnosticRow(label: '音频上传', value: '不会上传麦克风音频'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatCacheExists(SoundfontCacheInfo? info) {
  if (info == null) return '检查中';
  if (info.exists && !info.isUsable) return '疑似损坏';
  if (info.errorMessage != null) return '读取失败';
  return info.exists ? '已缓存' : '未缓存';
}

String _formatCacheSize(SoundfontCacheInfo? info) {
  final sizeBytes = info?.sizeBytes;
  if (sizeBytes == null) return '未知';
  if (sizeBytes < 1024) return '$sizeBytes B';
  final sizeKb = sizeBytes / 1024;
  if (sizeKb < 1024) return '${sizeKb.toStringAsFixed(1)} KB';
  return '${(sizeKb / 1024).toStringAsFixed(1)} MB';
}

String _formatMidiStatus(MidiInputSnapshot snapshot) {
  if (snapshot.lastError != null) return '读取失败';
  if (snapshot.isListening) return '监听中';
  return '未启动';
}

String _formatMidiDevices(List<MidiInputDeviceInfo> devices) {
  if (devices.isEmpty) return '未发现';
  return devices
      .map((device) {
        final suffix = device.connected ? '已连接' : device.type;
        return '${device.name} ($suffix)';
      })
      .join(', ');
}

String _formatMidiEvent(PerformanceInputEvent event) {
  final channelLabel = 'ch ${event.channel + 1}';
  return switch (event.type) {
    PerformanceInputEventType.noteOn =>
      'Note On ${event.midiNote} v${event.velocity} $channelLabel',
    PerformanceInputEventType.noteOff =>
      'Note Off ${event.midiNote} v${event.velocity} $channelLabel',
    PerformanceInputEventType.sustain =>
      'Sustain ${event.sustain == true ? 'down' : 'up'} $channelLabel',
    PerformanceInputEventType.pitch =>
      'Pitch ${event.pitchHz?.toStringAsFixed(1) ?? '未知'}Hz $channelLabel',
  };
}

String _playbackStateLabel(PlaybackState state) {
  return switch (state) {
    PlaybackState.playing => '播放中',
    PlaybackState.paused => '已暂停',
    PlaybackState.stopped => '已停止',
  };
}

class _PermissionDisplayData {
  final String label;
  final Color accent;
  final IconData icon;

  const _PermissionDisplayData({
    required this.label,
    required this.accent,
    required this.icon,
  });

  factory _PermissionDisplayData.fromStatus(PermissionStatus? status) {
    return switch (status) {
      PermissionStatus.granted => const _PermissionDisplayData(
        label: '已授权',
        accent: LuxuryPalette.emerald,
        icon: CupertinoIcons.check_mark_circled_solid,
      ),
      PermissionStatus.denied => const _PermissionDisplayData(
        label: '未授权',
        accent: LuxuryPalette.goldBright,
        icon: CupertinoIcons.mic_slash_fill,
      ),
      PermissionStatus.permanentlyDenied => const _PermissionDisplayData(
        label: '已拒绝，需要去系统设置开启',
        accent: LuxuryPalette.ruby,
        icon: CupertinoIcons.exclamationmark_triangle_fill,
      ),
      PermissionStatus.restricted => const _PermissionDisplayData(
        label: '系统限制',
        accent: LuxuryPalette.ruby,
        icon: CupertinoIcons.exclamationmark_triangle_fill,
      ),
      PermissionStatus.limited => const _PermissionDisplayData(
        label: '受限授权',
        accent: LuxuryPalette.goldBright,
        icon: CupertinoIcons.mic_fill,
      ),
      PermissionStatus.provisional => const _PermissionDisplayData(
        label: '临时授权',
        accent: LuxuryPalette.goldBright,
        icon: CupertinoIcons.mic_fill,
      ),
      null => const _PermissionDisplayData(
        label: '检查中',
        accent: LuxuryPalette.textSubtle,
        icon: CupertinoIcons.clock_fill,
      ),
    };
  }
}

class _DiagnosticSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  const _DiagnosticSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: LuxuryPalette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  final String label;
  final String value;

  const _DiagnosticRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: LuxuryPalette.textSubtle,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: LuxuryPalette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
