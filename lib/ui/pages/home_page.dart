import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import '../widgets/luxury_controls.dart';
import '../widgets/player_helpers.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MidiFileParser _parser = MidiFileParser();
  bool _isLoading = false;

  Future<void> _pickAndLoadMidi() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final songData = await _parser.parseFile(filePath);
      if (!mounted) return;

      final player = context.read<MidiPlayerController>();
      player.loadSong(songData);

      unawaited(
        Navigator.of(
          context,
        ).push(CupertinoPageRoute<void>(builder: (_) => const PlayerPage())),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('无法解析 MIDI 文件: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _openPlayer() {
    unawaited(
      Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const PlayerPage())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MidiPlayerController>();
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        border: null,
        middle: Text('MIDI 伴奏'),
      ),
      child: LuxuryBackdrop(
        child: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _isLoading
                ? const Center(
                    key: ValueKey('loading'),
                    child: CupertinoActivityIndicator(radius: 18),
                  )
                : _HomeContent(
                    player: player,
                    onImportMidi: _pickAndLoadMidi,
                    onOpenPlayer: _openPlayer,
                  ),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final MidiPlayerController player;
  final VoidCallback onImportMidi;
  final VoidCallback onOpenPlayer;

  const _HomeContent({
    required this.player,
    required this.onImportMidi,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('home'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HeaderBlock(),
          const SizedBox(height: 14),
          _HomeHeroPanel(
            player: player,
            onImportMidi: onImportMidi,
            onOpenPlayer: onOpenPlayer,
          ),
          const SizedBox(height: 14),
          const _BottomFeatureStrip(),
        ],
      ),
    );
  }
}

class _HomeHeroPanel extends StatelessWidget {
  final MidiPlayerController player;
  final VoidCallback onImportMidi;
  final VoidCallback onOpenPlayer;

  const _HomeHeroPanel({
    required this.player,
    required this.onImportMidi,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final song = player.songData;
    return LuxuryPanel(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _TinyStatus(label: 'Nocturne Edition'),
              const Spacer(),
              _SoundfontPill(player: player),
            ],
          ),
          const SizedBox(height: 28),
          const OrnamentLine(),
          const SizedBox(height: 22),
          Text('黑金伴奏厅', style: luxuryDisplayStyle(context, size: 38)),
          const SizedBox(height: 12),
          const Text(
            '为古典排练准备的 MIDI 伴奏与实时跟随。',
            style: TextStyle(fontSize: 14, color: LuxuryPalette.textMuted),
          ),
          if (!player.isSoundfontReady) ...[
            const SizedBox(height: 14),
            _SoundfontStatusLine(player: player),
          ],
          if (song != null) ...[
            const SizedBox(height: 14),
            _LoadedScoreLine(fileName: song.fileName),
          ],
          const SizedBox(height: 22),
          LuxuryActionButton(
            key: HomeUiKeys.importMidiButton,
            label: '导入 MIDI 乐谱',
            icon: CupertinoIcons.arrow_down_doc_fill,
            onPressed: onImportMidi,
            primary: true,
          ),
          if (song != null) ...[
            const SizedBox(height: 12),
            LuxuryActionButton(
              key: HomeUiKeys.continueSongButton,
              label: '继续当前曲目',
              icon: CupertinoIcons.play_arrow_solid,
              onPressed: onOpenPlayer,
            ),
          ],
          const SizedBox(height: 22),
          _HomeMetricRow(hasSong: song != null),
        ],
      ),
    );
  }
}

class _HomeMetricRow extends StatelessWidget {
  final bool hasSong;

  const _HomeMetricRow({required this.hasSong});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: LuxuryMetricTile(
            label: '当前曲目',
            value: hasSong ? '已就绪' : '未载入',
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: LuxuryMetricTile(label: '控制能力', value: '轨道 / 跟随'),
        ),
      ],
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'NOCTURNE EDITION',
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 2.2,
                color: LuxuryPalette.textSubtle,
              ),
            ),
            Spacer(),
            Icon(
              CupertinoIcons.music_note,
              size: 15,
              color: LuxuryPalette.goldDim,
            ),
          ],
        ),
      ],
    );
  }
}

class _TinyStatus extends StatelessWidget {
  final String label;

  const _TinyStatus({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: LuxuryPalette.gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.0,
          color: LuxuryPalette.goldBright,
        ),
      ),
    );
  }
}

class _SoundfontPill extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontPill({required this.player});

  @override
  Widget build(BuildContext context) {
    final color = switch (player.soundfontState) {
      SoundfontSetupState.ready => LuxuryPalette.emerald,
      SoundfontSetupState.failed => LuxuryPalette.ruby,
      SoundfontSetupState.downloading => LuxuryPalette.goldBright,
      _ => LuxuryPalette.gold,
    };
    final text = switch (player.soundfontState) {
      SoundfontSetupState.ready => '音色已就绪',
      SoundfontSetupState.failed => '下载失败',
      SoundfontSetupState.downloading => '下载中',
      SoundfontSetupState.checking => '检查中',
      SoundfontSetupState.idle => '准备中',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _SoundfontStatusLine extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontStatusLine({required this.player});

  @override
  Widget build(BuildContext context) {
    final progressPercent = (player.soundfontDownloadProgress * 100)
        .clamp(0, 100)
        .round();
    final message = switch (player.soundfontState) {
      SoundfontSetupState.downloading => '正在自动下载音色库 $progressPercent%',
      SoundfontSetupState.failed => player.soundfontErrorMessage ?? '音色库自动下载失败',
      SoundfontSetupState.checking => '正在检查本地音色库',
      SoundfontSetupState.idle => '正在准备音色库',
      SoundfontSetupState.ready => '音色库已就绪',
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: LuxuryPalette.textMuted,
            ),
          ),
        ),
        if (player.soundfontState == SoundfontSetupState.failed) ...[
          const SizedBox(width: 12),
          CupertinoButton(
            key: HomeUiKeys.soundfontRetryButton,
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
    );
  }
}

class _LoadedScoreLine extends StatelessWidget {
  final String fileName;

  const _LoadedScoreLine({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.music_note_list,
            size: 16,
            color: LuxuryPalette.goldBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: LuxuryPalette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomFeatureStrip extends StatelessWidget {
  const _BottomFeatureStrip();

  @override
  Widget build(BuildContext context) {
    return const LuxuryPanel(
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ValueItem(title: '导入', subtitle: 'MIDI'),
          _ValueItem(title: '控制', subtitle: '轨道'),
          _ValueItem(title: '跟随', subtitle: '实时'),
        ],
      ),
    );
  }
}

class _ValueItem extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ValueItem({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: LuxuryPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: LuxuryPalette.textMuted),
        ),
      ],
    );
  }
}
