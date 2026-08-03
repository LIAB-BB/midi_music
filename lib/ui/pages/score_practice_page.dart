import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../../core/settings/app_settings.dart';
import '../../models/midi_track.dart';
import '../widgets/midi_piano_roll.dart';
import '../widgets/pdf_score_viewer.dart';
import '../widgets/player_helpers.dart';
import 'player_page.dart';
import 'settings_page.dart';

class PracticeScoreMetadata {
  final String title;
  final String composer;
  final String category;
  final String level;
  final String duration;
  final String saves;
  final Color accent;
  final int seed;
  final String? assetPath;
  final String? pdfPageAssetPrefix;
  final int? pdfPageCount;

  const PracticeScoreMetadata({
    required this.title,
    required this.composer,
    required this.category,
    required this.level,
    required this.duration,
    required this.saves,
    required this.accent,
    required this.seed,
    this.assetPath,
    this.pdfPageAssetPrefix,
    this.pdfPageCount,
  });

  bool get hasPdfScore =>
      pdfPageAssetPrefix != null && pdfPageCount != null && pdfPageCount! > 0;
}

class ScorePracticePage extends StatefulWidget {
  final PracticeScoreMetadata score;

  const ScorePracticePage({super.key, required this.score});

  @override
  State<ScorePracticePage> createState() => _ScorePracticePageState();
}

class _ScorePracticePageState extends State<ScorePracticePage> {
  final MidiFileParser _parser = MidiFileParser();
  var _isLoadingScore = false;

  @override
  void initState() {
    super.initState();
    if (widget.score.assetPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadAssetScore());
      });
    }
  }

  bool _isScoreLoaded(MidiPlayerController player) {
    return player.songData != null &&
        player.currentSongId == widget.score.title;
  }

  Future<bool> _loadAssetScore() async {
    final assetPath = widget.score.assetPath;
    if (assetPath == null) return false;

    final player = context.read<MidiPlayerController>();
    if (_isScoreLoaded(player)) return true;
    if (_isLoadingScore) return false;

    setState(() => _isLoadingScore = true);
    try {
      final data = await rootBundle.load(assetPath);
      final song = _parser.parseBytes(
        data.buffer.asUint8List(),
        fileName: assetPath.split('/').last,
      );
      if (!mounted) return false;

      final settings = context.read<AppSettingsController>();
      player.loadSong(song, songId: widget.score.title);
      player.setSpeed(settings.defaultPlaybackSpeed);
      return true;
    } catch (error) {
      if (mounted) {
        _showAlert('载入失败', '无法载入内置 MIDI：$error');
      }
      return false;
    } finally {
      if (mounted) setState(() => _isLoadingScore = false);
    }
  }

  Future<void> _togglePlayback(MidiPlayerController player) async {
    if (!_isScoreLoaded(player)) {
      final loaded = await _loadAssetScore();
      if (!loaded || !mounted) return;
    }
    if (player.isPlaying) {
      player.pause();
      return;
    }
    if (!player.isSoundfontReady) {
      _showAlert('音色库未就绪', '请等待音色库准备完成后再播放。');
      return;
    }
    player.play();
  }

  void _seek(MidiPlayerController player, double value) {
    if (_isScoreLoaded(player)) {
      player.seekTo(value * player.totalDuration);
    }
  }

  void _setTempo(MidiPlayerController player, double value) {
    if (_isScoreLoaded(player)) player.setSpeed(value);
  }

  void _openPlayer(MidiPlayerController player) {
    if (!_isScoreLoaded(player)) {
      _showAlert('请先载入 MIDI', '曲目载入后才能进入 USB MIDI 演奏台。');
      return;
    }
    unawaited(
      Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const PlayerPage())),
    );
  }

  void _showAlert(String title, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF5EBD7),
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: const Color(0xFFF5EBD7).withValues(alpha: 0.92),
        previousPageTitle: '乐库',
        middle: Text(
          score.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF2A2118)),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          onPressed: () => unawaited(
            Navigator.of(context).push(
              CupertinoPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
          child: const Icon(
            CupertinoIcons.gear_alt_fill,
            size: 18,
            color: Color(0xFF5F4A35),
          ),
        ),
      ),
      child: Consumer<MidiPlayerController>(
        builder: (context, player, _) {
          final hasLoadedSong = _isScoreLoaded(player);
          final song = hasLoadedSong ? player.songData : null;
          final progress = hasLoadedSong && player.totalDuration > 0
              ? (player.currentTime / player.totalDuration).clamp(0.0, 1.0)
              : 0.0;

          return Stack(
            children: [
              SafeArea(
                bottom: false,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _PracticeHeader(
                        score: score,
                        hasLoadedSong: hasLoadedSong,
                        isLoading: _isLoadingScore,
                        onLoadAssetScore: _loadAssetScore,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _ScoreDocumentView(
                        score: score,
                        song: song,
                        currentTime: hasLoadedSong ? player.currentTime : 0,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _PracticeTimeline(
                        player: player,
                        isScoreLoaded: hasLoadedSong,
                        progress: progress,
                        onSeek: (value) => _seek(player, value),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 142),
                      sliver: SliverToBoxAdapter(
                        child: _PracticeOptions(
                          tempo: hasLoadedSong ? player.playbackSpeed : 1.0,
                          enabled: hasLoadedSong,
                          currentBpm: hasLoadedSong ? player.currentBpm : null,
                          onTempoChanged: (value) => _setTempo(player, value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _PracticeToolbar(
                  isPlaying: hasLoadedSong && player.isPlaying,
                  canOpenPlayer: hasLoadedSong,
                  onPlayPause: () => _togglePlayback(player),
                  onOpenPlayer: () => _openPlayer(player),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PracticeHeader extends StatelessWidget {
  final PracticeScoreMetadata score;
  final bool hasLoadedSong;
  final bool isLoading;
  final Future<bool> Function() onLoadAssetScore;

  const _PracticeHeader({
    required this.score,
    required this.hasLoadedSong,
    required this.isLoading,
    required this.onLoadAssetScore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF241A11),
                    fontFamily: 'Georgia',
                    fontFamilyFallback: ['Times New Roman', 'Noto Serif'],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${score.composer} · ${score.level} · ${score.duration}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7E6C55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _LoadScoreButton(
            hasAsset: score.assetPath != null,
            hasLoadedSong: hasLoadedSong,
            isLoading: isLoading,
            onPressed: onLoadAssetScore,
          ),
        ],
      ),
    );
  }
}

class _LoadScoreButton extends StatelessWidget {
  final bool hasAsset;
  final bool hasLoadedSong;
  final bool isLoading;
  final Future<bool> Function() onPressed;

  const _LoadScoreButton({
    required this.hasAsset,
    required this.hasLoadedSong,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = !hasAsset ? '无 MIDI' : (hasLoadedSong ? '已载入' : '载入');
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      minimumSize: const Size(0, 0),
      borderRadius: BorderRadius.circular(999),
      color: hasAsset
          ? (hasLoadedSong ? const Color(0xFF385F4D) : const Color(0xFF2D241B))
          : const Color(0xFF9A8971),
      onPressed: !hasAsset || isLoading ? null : () => unawaited(onPressed()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const CupertinoActivityIndicator(radius: 8)
          else
            Icon(
              hasAsset
                  ? (hasLoadedSong
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.arrow_down_doc_fill)
                  : CupertinoIcons.exclamationmark_circle,
              size: 15,
              color: CupertinoColors.white,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: CupertinoColors.white),
          ),
        ],
      ),
    );
  }
}

class _ScoreDocumentView extends StatelessWidget {
  final PracticeScoreMetadata score;
  final MidiSongData? song;
  final double currentTime;

  const _ScoreDocumentView({
    required this.score,
    required this.song,
    required this.currentTime,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF9F1DF),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: score.hasPdfScore
              ? AspectRatio(
                  aspectRatio: 595 / 842,
                  child: PdfScoreViewer(
                    pageAssetPrefix: score.pdfPageAssetPrefix!,
                    pageCount: score.pdfPageCount!,
                    label: '公版 PDF 钢琴分谱',
                  ),
                )
              : AspectRatio(
                  aspectRatio: 1.16,
                  child: song == null
                      ? _MissingMidiView(hasAsset: score.assetPath != null)
                      : MidiPianoRoll(
                          song: song!,
                          currentTime: currentTime,
                          accent: score.accent,
                        ),
                ),
        ),
      ),
    );
  }
}

class _MissingMidiView extends StatelessWidget {
  final bool hasAsset;

  const _MissingMidiView({required this.hasAsset});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE9DDC6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD3C09B)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasAsset
                    ? CupertinoIcons.arrow_down_doc
                    : CupertinoIcons.exclamationmark_triangle,
                color: const Color(0xFF715B41),
                size: 30,
              ),
              const SizedBox(height: 12),
              Text(
                hasAsset ? '正在读取真实 MIDI 音符…' : '此卡片尚未接入真实 MIDI',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF443421),
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                '不会再以示意谱面替代真实曲目。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF7E6C55)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeTimeline extends StatelessWidget {
  final MidiPlayerController player;
  final bool isScoreLoaded;
  final double progress;
  final ValueChanged<double> onSeek;

  const _PracticeTimeline({
    required this.player,
    required this.isScoreLoaded,
    required this.progress,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final hasSong = isScoreLoaded && player.totalDuration > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      child: Column(
        children: [
          CupertinoSlider(
            value: progress,
            min: 0,
            max: 1,
            activeColor: const Color(0xFF5C4A36),
            thumbColor: const Color(0xFF2D241B),
            onChanged: hasSong ? onSeek : null,
          ),
          Row(
            children: [
              Text(
                hasSong ? formatClock(player.currentTime) : '0:00',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7E6C55)),
              ),
              const Spacer(),
              Text(
                hasSong ? formatClock(player.totalDuration) : '等待 MIDI',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7E6C55)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PracticeOptions extends StatelessWidget {
  final double tempo;
  final bool enabled;
  final double? currentBpm;
  final ValueChanged<double> onTempoChanged;

  const _PracticeOptions({
    required this.tempo,
    required this.enabled,
    required this.currentBpm,
    required this.onTempoChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4C4A7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '真实 MIDI 数据',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2A2118),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              enabled
                  ? '播放位置会驱动卷帘高亮与时间窗口。当前 ${currentBpm!.toStringAsFixed(0)} BPM。'
                  : '载入 MIDI 后将显示音符、时值、轨道和真实播放位置。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF7E6C55)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(CupertinoIcons.metronome, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${tempo.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A2118),
                  ),
                ),
                Expanded(
                  child: CupertinoSlider(
                    value: tempo.clamp(0.5, 1.5),
                    min: 0.5,
                    max: 1.5,
                    divisions: 20,
                    activeColor: const Color(0xFF5C4A36),
                    onChanged: enabled ? onTempoChanged : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeToolbar extends StatelessWidget {
  final bool isPlaying;
  final bool canOpenPlayer;
  final VoidCallback onPlayPause;
  final VoidCallback onOpenPlayer;

  const _PracticeToolbar({
    required this.isPlaying,
    required this.canOpenPlayer,
    required this.onPlayPause,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF3E3540).withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 78,
          child: Row(
            children: [
              const _ToolbarItem(
                icon: CupertinoIcons.music_note_list,
                label: '真实 MIDI',
                selected: true,
                onPressed: null,
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                onPressed: onPlayPause,
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 28,
                    color: const Color(0xFF2D241B),
                  ),
                ),
              ),
              _ToolbarItem(
                icon: CupertinoIcons.music_note_2,
                label: '演奏台',
                selected: canOpenPlayer,
                onPressed: canOpenPlayer ? onOpenPlayer : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  const _ToolbarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 7),
        minimumSize: const Size(0, 0),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? const Color(0xFFF4DFAE)
                  : CupertinoColors.white.withValues(alpha: 0.64),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? const Color(0xFFF4DFAE)
                    : CupertinoColors.white.withValues(alpha: 0.64),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
