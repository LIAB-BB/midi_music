import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../../core/settings/app_settings.dart';
import '../theme/luxury_theme.dart';
import '../widgets/player_helpers.dart';
import 'player_page.dart';
import 'score_practice_page.dart';
import 'settings_page.dart';

const _k478MidiAsset = 'assets/midi/mozart_k478_piano_quartet.mid';

const _k478Score = PracticeScoreMetadata(
  title: '钢琴四重奏 K.478',
  composer: 'W. A. Mozart',
  category: '室内乐',
  level: '进阶',
  duration: '8:00',
  saves: '试用曲目',
  accent: Color(0xFF8B6F9E),
  seed: 478,
  assetPath: _k478MidiAsset,
  pdfPageAssetPrefix: 'assets/scores/mozart_k478_piano_part/page',
  pdfPageCount: 21,
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MidiFileParser _parser = MidiFileParser();
  var _isLoading = false;

  Future<void> _startK478Practice() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final data = await rootBundle.load(_k478MidiAsset);
      final song = _parser.parseBytes(
        data.buffer.asUint8List(),
        fileName: _k478MidiAsset.split('/').last,
      );
      if (!mounted) return;

      final player = context.read<MidiPlayerController>();
      player.loadSong(song, songId: _k478Score.title);
      player.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );

      await Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const PlayerPage()));
    } catch (error) {
      if (mounted) {
        _showError('无法载入内置 K.478 MIDI：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openScore() {
    unawaited(
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => const ScorePracticePage(score: _k478Score),
        ),
      ),
    );
  }

  void _openSettings() {
    unawaited(
      Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsPage())),
    );
  }

  void _showError(String message) {
    unawaited(
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('载入失败'),
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        middle: const Text('K.478 排练'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 0),
          onPressed: _openSettings,
          child: const Icon(
            CupertinoIcons.gear_alt_fill,
            size: 18,
            color: LuxuryPalette.goldBright,
          ),
        ),
      ),
      child: LuxuryBackdrop(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _K478ReleaseCard(
                  isLoading: _isLoading,
                  onStartPractice: _startK478Practice,
                  onViewScore: _openScore,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _K478ReleaseCard extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onStartPractice;
  final VoidCallback onViewScore;

  const _K478ReleaseCard({
    required this.isLoading,
    required this.onStartPractice,
    required this.onViewScore,
  });

  @override
  Widget build(BuildContext context) {
    return LuxuryPanel(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow(label: 'IOS USB MIDI BETA'),
          const SizedBox(height: 16),
          Text('钢琴四重奏\nK.478', style: luxuryDisplayStyle(context, size: 38)),
          const SizedBox(height: 10),
          const Text(
            '莫扎特 · 钢琴右手、左手与弦乐分轨\n首轮试用只验证这一首内置曲目。',
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 22),
          const _PracticeStep(
            number: '1',
            text: '用 class-compliant USB MIDI 电子琴直接连接 iPhone。',
          ),
          const _PracticeStep(number: '2', text: '进入演奏台后选择钢琴右手和左手两条轨道。'),
          const _PracticeStep(number: '3', text: '开启跟随；App 不会请求麦克风权限。'),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              key: const Key('start-k478-usb-practice'),
              color: LuxuryPalette.gold,
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 15),
              onPressed: isLoading ? null : () => unawaited(onStartPractice()),
              child: isLoading
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.black,
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.music_note_2,
                          size: 18,
                          color: CupertinoColors.black,
                        ),
                        SizedBox(width: 9),
                        Text(
                          '开始 USB MIDI 排练',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.black,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              key: const Key('view-k478-pdf-score'),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: CupertinoColors.white.withValues(alpha: 0.07),
              onPressed: isLoading ? null : onViewScore,
              child: const Text(
                '查看钢琴分谱（PDF）',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: LuxuryPalette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '试用范围：iOS + USB MIDI + K.478。MusicXML、PDF 识谱、文件导入和麦克风跟随均不在本版内。',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: LuxuryPalette.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeStep extends StatelessWidget {
  final String number;
  final String text;

  const _PracticeStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: LuxuryPalette.gold,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: CupertinoColors.black,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: LuxuryPalette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
