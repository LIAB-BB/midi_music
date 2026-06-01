import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/follow/follow_mode_controller.dart';
import '../../core/follow/follow_mode_session.dart';
import '../../core/midi/midi_player.dart';
import '../../models/midi_track.dart';
import '../theme/luxury_theme.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        previousPageTitle: '乐库',
        middle: Consumer<MidiPlayerController>(
          builder: (_, player, _) => Text(
            player.songData == null
                ? 'Nocturne Stage'
                : _displaySongTitle(player.songData!.fileName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      child: LuxuryBackdrop(
        child: SafeArea(
          bottom: false,
          child: Consumer<MidiPlayerController>(
            builder: (context, player, _) {
              if (!player.isReady && player.songData == null) {
                return const _EmptyStage();
              }
              return _PlayerBody(player: player);
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LuxuryPanel(
          highlighted: true,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionEyebrow(label: 'NO SCORE LOADED'),
              const SizedBox(height: 18),
              Text(
                '先导入一份 MIDI 乐谱。',
                style: luxuryDisplayStyle(context, size: 30),
              ),
              const SizedBox(height: 10),
              const Text(
                '播放器已经就位，但当前还没有可演出的曲目。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: LuxuryPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerBody extends StatefulWidget {
  final MidiPlayerController player;

  const _PlayerBody({required this.player});

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> {
  FollowModeSession? _followSession;
  bool _isFollowMode = false;
  FollowModeState _followState = FollowModeState.idle;
  double _followSpeedFactor = 1.0;
  int? _melodyTrackIndex;

  @override
  void dispose() {
    unawaited(_releaseFollowResources().catchError((Object _) {}));
    super.dispose();
  }

  void _setMelodyTrack(int trackIndex) {
    setState(() => _melodyTrackIndex = trackIndex);
  }

  Future<void> _toggleFollowMode() async {
    if (_isFollowMode) {
      await _stopFollowMode();
      return;
    }

    if (_melodyTrackIndex == null) {
      _showAlert('请先选择主旋律轨道', '先在轨道列表中指定主旋律，再开启实时跟随。');
      return;
    }

    final granted = await _requestMicPermission();
    if (!granted) return;

    try {
      await _startFollowMode();
      if (mounted) {
        setState(() => _isFollowMode = true);
      }
    } catch (e) {
      await _stopFollowMode(updateUi: false);
      if (mounted) {
        setState(() {
          _isFollowMode = false;
          _followState = FollowModeState.idle;
          _followSpeedFactor = 1.0;
        });
        _showAlert('跟随模式启动失败', '无法启动麦克风检测：$e');
      }
    }
  }

  Future<bool> _requestMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (mounted) {
      _showAlert('需要麦克风权限', '跟随模式会通过麦克风识别起拍和速度，请在系统设置中允许访问。');
    }
    return false;
  }

  Future<void> _startFollowMode() async {
    final player = widget.player;
    final song = player.songData;
    final melodyTrackIndex = _melodyTrackIndex;
    if (song == null) {
      throw StateError('未加载 MIDI 乐谱');
    }
    if (melodyTrackIndex == null) {
      throw StateError('未选择主旋律轨道');
    }

    final melodyTrack = FollowModeSession.findMelodyTrack(
      song,
      melodyTrackIndex,
    );
    if (melodyTrack == null) {
      throw StateError('主旋律轨道不存在');
    }

    await _releaseFollowResources(resetPlayerSpeed: false);

    final session = FollowModeSession.forMidi(
      player: player,
      melodyTrack: melodyTrack,
    );
    _followSession = session;

    session.onSpeedChanged = (speed) {
      if (mounted) {
        // 确保在主线程更新UI
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _followSpeedFactor = speed);
          }
        });
      }
    };
    session.onStateChanged = (state) {
      if (mounted) {
        // 确保在主线程更新UI
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _followState = state;
              if (state == FollowModeState.idle) {
                _isFollowMode = false;
                _followSpeedFactor = 1.0;
              }
            });
            if (state == FollowModeState.idle) {
              unawaited(_releaseFollowResources().catchError((Object _) {}));
            }
          }
        });
      }
    };

    try {
      await session.start();
    } catch (_) {
      if (_followSession == session) {
        _followSession = null;
      }
      rethrow;
    }
  }

  Future<void> _stopFollowMode({bool updateUi = true}) async {
    await _releaseFollowResources();

    if (mounted && updateUi) {
      setState(() {
        _isFollowMode = false;
        _followState = FollowModeState.idle;
        _followSpeedFactor = 1.0;
      });
    }
  }

  Future<void> _releaseFollowResources({bool resetPlayerSpeed = true}) async {
    final session = _followSession;
    _followSession = null;
    if (session != null) {
      await session.dispose(resetPlayerSpeed: resetPlayerSpeed);
    }
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final song = player.songData;
    if (song == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!player.isSoundfontReady) ...[
            _SoundfontBanner(player: player),
            const SizedBox(height: 14),
          ],
          _StageConsole(
            player: player,
            isFollowMode: _isFollowMode,
            followState: _followState,
            followSpeedFactor: _followSpeedFactor,
          ),
          const SizedBox(height: 14),
          _PerformanceConsole(
            player: player,
            isFollowMode: _isFollowMode,
            followState: _followState,
            followSpeedFactor: _followSpeedFactor,
            melodyTrackIndex: _melodyTrackIndex,
            onToggleFollow: _toggleFollowMode,
          ),
          const SizedBox(height: 14),
          _TrackSalon(
            player: player,
            melodyTrackIndex: _melodyTrackIndex,
            onSetMelody: _setMelodyTrack,
          ),
        ],
      ),
    );
  }
}

class _SoundfontBanner extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontBanner({required this.player});

  @override
  Widget build(BuildContext context) {
    final progressPercent = (player.soundfontDownloadProgress * 100)
        .clamp(0, 100)
        .round();
    final message = switch (player.soundfontState) {
      SoundfontSetupState.downloading => '正在自动下载演出音色 $progressPercent%',
      SoundfontSetupState.failed =>
        player.soundfontErrorMessage ?? '演出音色下载失败，请稍后重试。',
      SoundfontSetupState.checking => '正在检查本地演出音色。',
      SoundfontSetupState.idle => '正在准备演出音色。',
      SoundfontSetupState.ready => '演出音色已就绪。',
    };
    final accent = switch (player.soundfontState) {
      SoundfontSetupState.failed => LuxuryPalette.ruby,
      SoundfontSetupState.ready => LuxuryPalette.emerald,
      _ => LuxuryPalette.goldBright,
    };
    final icon = switch (player.soundfontState) {
      SoundfontSetupState.failed =>
        CupertinoIcons.exclamationmark_triangle_fill,
      SoundfontSetupState.ready => CupertinoIcons.check_mark_circled_solid,
      _ => CupertinoIcons.cloud_download_fill,
    };

    return LuxuryPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: LuxuryPalette.textMuted,
              ),
            ),
          ),
          if (player.soundfontState == SoundfontSetupState.failed) ...[
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

class _StageConsole extends StatelessWidget {
  final MidiPlayerController player;
  final bool isFollowMode;
  final FollowModeState followState;
  final double followSpeedFactor;

  const _StageConsole({
    required this.player,
    required this.isFollowMode,
    required this.followState,
    required this.followSpeedFactor,
  });

  @override
  Widget build(BuildContext context) {
    final song = player.songData;
    if (song == null) return const SizedBox.shrink();

    final accent = _followAccent(isFollowMode, followState, player.isPlaying);
    final accentLabel = _followLabel(
      isFollowMode,
      followState,
      player.isPlaying,
    );
    final displaySpeed = isFollowMode
        ? followSpeedFactor
        : player.playbackSpeed;
    final displayTitle = _displaySongTitle(song.fileName);
    final remaining = (player.totalDuration - player.currentTime).clamp(
      0.0,
      player.totalDuration,
    );
    final titleSize = displayTitle.length > 24
        ? 26.0
        : (displayTitle.length > 16 ? 30.0 : 34.0);

    return LuxuryPanel(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionEyebrow(label: 'NOCTURNE STAGE'),
              const Spacer(),
              _StatusBadge(label: accentLabel, color: accent),
            ],
          ),
          const SizedBox(height: 22),
          const _OrnamentLine(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: luxuryDisplayStyle(context, size: titleSize),
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
              _StageDial(
                value: '${displaySpeed.toStringAsFixed(2)}x',
                caption: isFollowMode ? 'FOLLOW' : 'TEMPO',
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StageMetric(
                label: 'BPM',
                value: player.currentBpm.toStringAsFixed(0),
              ),
              _StageMetric(
                label: '时长',
                value: _formatClock(song.totalDuration),
              ),
              _StageMetric(label: '轨道', value: '${song.noteTracks.length}'),
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
                      '-${_formatClock(remaining)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CupertinoSlider(
                  value: player.progress,
                  onChanged: (value) =>
                      player.seekTo(value * player.totalDuration),
                ),
                Row(
                  children: [
                    Text(
                      _formatClock(player.currentTime),
                      style: const TextStyle(
                        fontSize: 13,
                        color: LuxuryPalette.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatClock(player.totalDuration),
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
          _TransportDeck(player: player),
        ],
      ),
    );
  }
}

class _TransportDeck extends StatelessWidget {
  final MidiPlayerController player;

  const _TransportDeck({required this.player});

  @override
  Widget build(BuildContext context) {
    final canPlay = player.isSoundfontReady && player.songData != null;
    final transportButtons = [
      _TransportButton(
        icon: CupertinoIcons.stop_fill,
        label: '停止',
        onPressed: canPlay ? player.stop : null,
      ),
      _TransportButton(
        icon: CupertinoIcons.gobackward_10,
        label: '回退',
        onPressed: canPlay
            ? () => player.seekTo(player.currentTime - 10)
            : null,
      ),
      _TransportButton(
        icon: player.isPlaying
            ? CupertinoIcons.pause_fill
            : CupertinoIcons.play_fill,
        label: player.isPlaying ? '暂停' : '播放',
        highlighted: true,
        large: true,
        onPressed: canPlay
            ? () {
                if (player.isPlaying) {
                  player.pause();
                } else {
                  player.play();
                }
              }
            : null,
      ),
      _TransportButton(
        icon: CupertinoIcons.goforward_10,
        label: '快进',
        onPressed: canPlay
            ? () => player.seekTo(player.currentTime + 10)
            : null,
      ),
      _TransportButton(
        icon: CupertinoIcons.arrow_counterclockwise,
        label: '归零',
        onPressed: canPlay ? () => player.seekTo(0) : null,
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
              child: _ConsoleNote(
                label: canPlay ? 'Tone Ready' : 'Tone Pending',
                value: canPlay ? '可直接演奏' : '等待音色加载',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ConsoleNote(
                label: 'Mode',
                value: player.isPlaying ? '舞台运行中' : '待机',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PerformanceConsole extends StatelessWidget {
  final MidiPlayerController player;
  final bool isFollowMode;
  final FollowModeState followState;
  final double followSpeedFactor;
  final int? melodyTrackIndex;
  final Future<void> Function() onToggleFollow;

  const _PerformanceConsole({
    required this.player,
    required this.isFollowMode,
    required this.followState,
    required this.followSpeedFactor,
    required this.melodyTrackIndex,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final followAccent = _followAccent(
      isFollowMode,
      followState,
      player.isPlaying,
    );
    final followNote = switch (followState) {
      FollowModeState.following => '伴奏正在贴合你的演奏速度。',
      FollowModeState.waitingForOnset => '已进入跟随模式，等待新的起拍。',
      FollowModeState.idle => isFollowMode ? '跟随已开启，等待演奏输入。' : '当前为手动排练模式。',
    };

    return LuxuryPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SectionEyebrow(label: 'PERFORMANCE'),
                  SizedBox(height: 10),
                ],
              ),
              const Spacer(),
              CupertinoSwitch(
                value: isFollowMode,
                onChanged: (_) => onToggleFollow(),
              ),
            ],
          ),
          Text('跟随与排练', style: luxuryDisplayStyle(context, size: 28)),
          const SizedBox(height: 8),
          Text(
            followNote,
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
                child: _ConsoleCard(
                  label: '主旋律',
                  value: melodyTrackIndex == null
                      ? '未指定'
                      : 'Track ${melodyTrackIndex! + 1}',
                  accent: melodyTrackIndex == null
                      ? LuxuryPalette.ruby
                      : LuxuryPalette.goldBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ConsoleCard(
                  label: isFollowMode ? '跟随倍率' : '速度倍率',
                  value: isFollowMode
                      ? '${followSpeedFactor.toStringAsFixed(2)}x'
                      : '${player.playbackSpeed.toStringAsFixed(2)}x',
                  accent: followAccent,
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
                      color: followAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: followAccent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.waveform_path_ecg,
                          size: 18,
                          color: followAccent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _followLabel(true, followState, player.isPlaying),
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

class _TrackSalon extends StatelessWidget {
  final MidiPlayerController player;
  final int? melodyTrackIndex;
  final ValueChanged<int> onSetMelody;

  const _TrackSalon({
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SectionEyebrow(label: 'TRACK SALON'),
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
                return _TrackTile(
                  track: track,
                  isMelody: track.index == melodyTrackIndex,
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

class _TrackTile extends StatelessWidget {
  final MidiTrackInfo track;
  final bool isMelody;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onSetMelody;

  const _TrackTile({
    required this.track,
    required this.isMelody,
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
        color: isMelody
            ? LuxuryPalette.gold.withValues(alpha: 0.08)
            : CupertinoColors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isMelody
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
                color: isMelody
                    ? LuxuryPalette.gold.withValues(alpha: 0.16)
                    : CupertinoColors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                onPressed: onSetMelody,
                child: Text(
                  isMelody ? '主旋律' : '设为主旋律',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMelody
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

class _SectionEyebrow extends StatelessWidget {
  final String label;

  const _SectionEyebrow({required this.label});

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

class _OrnamentLine extends StatelessWidget {
  const _OrnamentLine();

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

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

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

class _StageDial extends StatelessWidget {
  final String value;
  final String caption;
  final Color accent;

  const _StageDial({
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

class _StageMetric extends StatelessWidget {
  final String label;
  final String value;

  const _StageMetric({required this.label, required this.value});

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

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlighted;
  final bool large;

  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
    this.large = false,
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

class _ConsoleNote extends StatelessWidget {
  final String label;
  final String value;

  const _ConsoleNote({required this.label, required this.value});

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

class _ConsoleCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _ConsoleCard({
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

Color _followAccent(bool isFollowMode, FollowModeState state, bool isPlaying) {
  if (!isFollowMode) {
    return isPlaying ? LuxuryPalette.goldBright : LuxuryPalette.gold;
  }
  return switch (state) {
    FollowModeState.following => LuxuryPalette.emerald,
    FollowModeState.waitingForOnset => LuxuryPalette.ruby,
    FollowModeState.idle => LuxuryPalette.goldBright,
  };
}

String _followLabel(bool isFollowMode, FollowModeState state, bool isPlaying) {
  if (!isFollowMode) {
    return isPlaying ? '手动播放' : '待机';
  }
  return switch (state) {
    FollowModeState.following => '实时跟随',
    FollowModeState.waitingForOnset => '等待起拍',
    FollowModeState.idle => '跟随待命',
  };
}

String _formatClock(double seconds) {
  final totalSeconds = seconds.clamp(0.0, double.infinity).round();
  final minutes = totalSeconds ~/ 60;
  final remainSeconds = totalSeconds % 60;
  return '$minutes:${remainSeconds.toString().padLeft(2, '0')}';
}

String _displaySongTitle(String fileName) {
  final stripped = fileName.replaceAll(
    RegExp(r'\.mid$', caseSensitive: false),
    '',
  );
  final normalized = stripped.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  return normalized.isEmpty ? fileName : normalized;
}
