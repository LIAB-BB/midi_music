import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../theme/luxury_theme.dart';
import '../widgets/luxury_controls.dart';
import '../widgets/player_display_data.dart';
import '../widgets/player_helpers.dart';
import 'diagnostics_page.dart';
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

  Future<void> _loadDemoSong(_DemoSong demo) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final songData = await _parser.parseAsset(
        demo.assetPath,
        fileName: demo.fileName,
      );
      if (!mounted) return;

      final player = context.read<MidiPlayerController>();
      player.loadSong(songData);
      _openPlayer();
    } catch (e) {
      if (!mounted) return;
      _showError('无法载入示例曲目: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        trailing: _DiagnosticsNavButton(),
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
                    onLoadDemoSong: _loadDemoSong,
                  ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosticsNavButton extends StatelessWidget {
  const _DiagnosticsNavButton();

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: HomeUiKeys.diagnosticsButton,
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(32),
      onPressed: () {
        unawaited(
          Navigator.of(context).push(
            CupertinoPageRoute<void>(builder: (_) => const DiagnosticsPage()),
          ),
        );
      },
      child: const Icon(
        CupertinoIcons.waveform_path_ecg,
        size: 20,
        color: LuxuryPalette.goldBright,
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final MidiPlayerController player;
  final VoidCallback onImportMidi;
  final VoidCallback onOpenPlayer;
  final ValueChanged<_DemoSong> onLoadDemoSong;

  const _HomeContent({
    required this.player,
    required this.onImportMidi,
    required this.onOpenPlayer,
    required this.onLoadDemoSong,
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
          const SizedBox(height: 14),
          _DemoSongPanel(onLoadDemoSong: onLoadDemoSong),
        ],
      ),
    );
  }
}

class _DemoSong {
  final String title;
  final String composer;
  final String fileName;
  final String assetPath;

  const _DemoSong({
    required this.title,
    required this.composer,
    required this.fileName,
    required this.assetPath,
  });
}

const _demoSongs = [
  _DemoSong(
    title: '月光奏鸣曲',
    composer: 'Beethoven',
    fileName: 'Beethoven-Moonlight-Sonata.mid',
    assetPath: 'assets/midi/Beethoven-Moonlight-Sonata.mid',
  ),
  _DemoSong(
    title: 'C 大调前奏曲',
    composer: 'Bach',
    fileName: 'bach_wtc1_prelude.mid',
    assetPath: 'assets/midi/bach_wtc1_prelude.mid',
  ),
  _DemoSong(
    title: '钢琴奏鸣曲 K545',
    composer: 'Mozart',
    fileName: 'mozart_k545.mid',
    assetPath: 'assets/midi/mozart_k545.mid',
  ),
];

class _DemoSongPanel extends StatelessWidget {
  final ValueChanged<_DemoSong> onLoadDemoSong;

  const _DemoSongPanel({required this.onLoadDemoSong});

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow(label: 'DEMO SCORES'),
          const SizedBox(height: 10),
          Text('示例曲目', style: luxuryDisplayStyle(context, size: 26)),
          const SizedBox(height: 8),
          const Text(
            '无需准备文件，直接载入内置 MIDI 检查播放、轨道和跟随模式。',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final demo in _demoSongs)
            _DemoSongTile(demo: demo, onPressed: () => onLoadDemoSong(demo)),
        ],
      ),
    );
  }
}

class _DemoSongTile extends StatelessWidget {
  final _DemoSong demo;
  final VoidCallback onPressed;

  const _DemoSongTile({required this.demo, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      key: HomeUiKeys.demoSongButton(demo.fileName),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: CupertinoColors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LuxuryPalette.divider),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.music_note_2,
              size: 17,
              color: LuxuryPalette.goldBright,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    demo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LuxuryPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    demo.composer,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LuxuryPalette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 15,
              color: LuxuryPalette.textSubtle,
            ),
          ],
        ),
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
    final data = SoundfontStatusData.fromPlayer(player);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: data.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(data.pillText, style: TextStyle(fontSize: 12, color: data.accent)),
      ],
    );
  }
}

class _SoundfontStatusLine extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontStatusLine({required this.player});

  @override
  Widget build(BuildContext context) {
    final data = SoundfontStatusData.fromPlayer(player);

    return Row(
      children: [
        Expanded(
          child: Text(
            data.lineText,
            style: const TextStyle(
              fontSize: 13,
              color: LuxuryPalette.textMuted,
            ),
          ),
        ),
        if (data.canRetry) ...[
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
