import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/import/pdf_omr_client.dart';
import '../../core/import/score_import_service.dart';
import '../../core/midi/midi_player.dart';
import '../../core/notation/midi_notation_service.dart';
import '../theme/luxury_theme.dart';
import '../widgets/interactive_score_view.dart';
import 'score_practice_page.dart';
import 'settings_page.dart';

const _allCategory = '精选';

const _scoreCategories = [_allCategory, '古典', '练习曲', '爵士', '电影', '流行', '四手联弹'];

const _scoreCards = [
  _ScoreCardData(
    title: '钢琴四重奏 K.478',
    composer: 'W. A. Mozart · USB MIDI Demo',
    category: '古典',
    level: '进阶',
    duration: '8:00',
    saves: 'Demo',
    coverHeight: 252,
    accent: Color(0xFF8B6F9E),
    seed: 13,
    assetPath: 'assets/midi/mozart_k478_piano_quartet.mid',
  ),
  _ScoreCardData(
    title: '月光奏鸣曲 第一乐章',
    composer: 'Beethoven',
    category: '古典',
    level: '中级',
    duration: '5:20',
    saves: '2.4k',
    coverHeight: 228,
    accent: Color(0xFFB98B5B),
    seed: 2,
    assetPath: 'assets/midi/Beethoven-Moonlight-Sonata.mid',
  ),
  _ScoreCardData(
    title: '雨后练习曲',
    composer: 'Chopin Study',
    category: '练习曲',
    level: '进阶',
    duration: '3:48',
    saves: '986',
    coverHeight: 286,
    accent: Color(0xFF7E9B84),
    seed: 5,
    assetPath: 'assets/midi/chopin_nocturne.mid',
  ),
  _ScoreCardData(
    title: '深夜爵士小品',
    composer: 'Blue Room',
    category: '爵士',
    level: '中级',
    duration: '2:56',
    saves: '1.1k',
    coverHeight: 196,
    accent: Color(0xFF9C6F8A),
    seed: 8,
  ),
  _ScoreCardData(
    title: '银幕主题变奏',
    composer: 'Cinema Theme',
    category: '电影',
    level: '初级',
    duration: '4:12',
    saves: '764',
    coverHeight: 258,
    accent: Color(0xFFB66A4C),
    seed: 3,
  ),
  _ScoreCardData(
    title: '午后圆舞曲',
    composer: 'Salon Waltz',
    category: '古典',
    level: '初级',
    duration: '2:34',
    saves: '538',
    coverHeight: 214,
    accent: Color(0xFFC3AA72),
    seed: 9,
    assetPath: 'assets/midi/mozart_k545.mid',
  ),
  _ScoreCardData(
    title: '流行和弦速写',
    composer: 'Pop Sketch',
    category: '流行',
    level: '入门',
    duration: '3:10',
    saves: '1.8k',
    coverHeight: 300,
    accent: Color(0xFF6893A1),
    seed: 4,
  ),
  _ScoreCardData(
    title: '双钢琴排练片段',
    composer: 'Duo Session',
    category: '四手联弹',
    level: '进阶',
    duration: '6:18',
    saves: '431',
    coverHeight: 244,
    accent: Color(0xFFA88C5E),
    seed: 11,
  ),
  _ScoreCardData(
    title: '平均律 C大调前奏曲',
    composer: 'J. S. Bach · BWV 846',
    category: '古典',
    level: '中级',
    duration: '2:00',
    saves: '1.3k',
    coverHeight: 184,
    accent: Color(0xFF8F855D),
    seed: 1,
    assetPath: 'assets/midi/bach_wtc1_prelude.mid',
  ),
  _ScoreCardData(
    title: '黑键即兴',
    composer: 'Noir Keys',
    category: '爵士',
    level: '进阶',
    duration: '4:45',
    saves: '807',
    coverHeight: 272,
    accent: Color(0xFF6E8175),
    seed: 7,
  ),
  _ScoreCardData(
    title: '片尾曲钢琴版',
    composer: 'Ending Credits',
    category: '电影',
    level: '中级',
    duration: '3:38',
    saves: '1.5k',
    coverHeight: 220,
    accent: Color(0xFFAA7F69),
    seed: 6,
  ),
  _ScoreCardData(
    title: '周末旋律',
    composer: 'Weekend Lead',
    category: '流行',
    level: '初级',
    duration: '2:48',
    saves: '923',
    coverHeight: 252,
    accent: Color(0xFF9BA35E),
    seed: 10,
  ),
  _ScoreCardData(
    title: '四手联弹序曲',
    composer: 'Opening Duo',
    category: '四手联弹',
    level: '中级',
    duration: '5:04',
    saves: '376',
    coverHeight: 312,
    accent: Color(0xFFB78D72),
    seed: 12,
  ),
];

abstract class ScoreFilePicker {
  Future<String?> pickScorePath();
}

class _PlatformScoreFilePicker implements ScoreFilePicker {
  @override
  Future<String?> pickScorePath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mid', 'midi', 'musicxml', 'xml', 'pdf'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }
}

/// 保留的通用曲库与文件导入入口；默认 K.478 首页暂未直接导航到这里。
class ScoreLibraryPage extends StatefulWidget {
  final ScoreImportService? importService;
  final ScoreFilePicker? filePicker;
  final ScoreSurfaceFactory? practiceSurfaceFactory;
  final MidiNotationBuilder? practiceNotationBuilder;

  const ScoreLibraryPage({
    super.key,
    this.importService,
    this.filePicker,
    this.practiceSurfaceFactory,
    this.practiceNotationBuilder,
  });

  @override
  State<ScoreLibraryPage> createState() => _ScoreLibraryPageState();
}

class _ScoreLibraryPageState extends State<ScoreLibraryPage> {
  late final ScoreImportService _scoreImportService;
  late final ScoreFilePicker _scoreFilePicker;
  var _isLoading = false;
  var _selectedCategory = _allCategory;

  @override
  void initState() {
    super.initState();
    _scoreImportService = widget.importService ?? ScoreImportService();
    _scoreFilePicker = widget.filePicker ?? _PlatformScoreFilePicker();
  }

  Future<void> _pickAndLoadScore() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final filePath = await _scoreFilePicker.pickScorePath();
      if (!mounted || filePath == null) return;

      final session = await _scoreImportService.importFile(filePath);
      if (!mounted) return;

      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ScorePracticePage(
            score: PracticeScoreMetadata.imported(
              session.songData.fileName,
              sourceFingerprint: session.sourceFingerprint,
            ),
            initialSession: session,
            surfaceFactory: widget.practiceSurfaceFactory,
            notationBuilder: widget.practiceNotationBuilder,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('无法导入乐谱文件：${_describeImportError(e)}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _describeImportError(Object error) {
    if (error is OmrServiceException) {
      return error.message;
    }
    if (error is UnsupportedError) {
      return error.message?.toString() ?? '暂不支持这类乐谱格式。';
    }
    if (error is FileSystemException) {
      return '找不到或无法读取选择的乐谱文件。';
    }
    if (error is FormatException) {
      return '文件内容无法解析，请确认乐谱文件格式有效。';
    }
    return '请确认文件格式有效后重试。';
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

  void _openScorePractice(_ScoreCardData score) {
    unawaited(
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ScorePracticePage(
            score: score.toPracticeMetadata(),
            notationBuilder: widget.practiceNotationBuilder,
          ),
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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MidiPlayerController>();
    final visibleScores = _selectedCategory == _allCategory
        ? _scoreCards
        : _scoreCards
              .where((score) => score.category == _selectedCategory)
              .toList(growable: false);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        border: null,
        middle: const Text('乐谱广场'),
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _isLoading
                ? const Center(
                    key: ValueKey('loading'),
                    child: CupertinoActivityIndicator(radius: 18),
                  )
                : CustomScrollView(
                    key: const ValueKey('score-feed'),
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _ScoreFeedHeader(
                          player: player,
                          onImport: _pickAndLoadScore,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _CategoryDropdown(
                          selectedCategory: _selectedCategory,
                          onSelected: (category) {
                            setState(() => _selectedCategory = category);
                          },
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 34),
                        sliver: SliverToBoxAdapter(
                          child: _ScoreMasonryGrid(
                            scores: visibleScores,
                            onScorePressed: _openScorePractice,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _ScoreFeedHeader extends StatelessWidget {
  final MidiPlayerController player;
  final VoidCallback onImport;

  const _ScoreFeedHeader({required this.player, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('乐谱广场', style: luxuryDisplayStyle(context, size: 36)),
                    const SizedBox(height: 8),
                    const Text(
                      '浏览谱面灵感，导入 MIDI 或 MusicXML 后进入排练。',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: LuxuryPalette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!player.isSoundfontReady) ...[
                const SizedBox(width: 14),
                _SoundfontBadge(player: player),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const _SearchField(),
          const SizedBox(height: 14),
          _HeaderActions(onImport: onImport),
          if (!player.isSoundfontReady) ...[
            const SizedBox(height: 12),
            _SoundfontStatusLine(player: player),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.search,
            size: 18,
            color: LuxuryPalette.textSubtle,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '搜索曲名、作曲家或风格',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: LuxuryPalette.textSubtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  final VoidCallback onImport;

  const _HeaderActions({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _PrimaryActionButton(
        label: '导入乐谱文件',
        icon: CupertinoIcons.arrow_down_doc_fill,
        onPressed: onImport,
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const _CategoryDropdown({
    required this.selectedCategory,
    required this.onSelected,
  });

  Future<void> _showMenu(BuildContext context) async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('选择分类'),
        actions: [
          for (final category in _scoreCategories)
            CupertinoActionSheetAction(
              key: Key('score-category-$category'),
              isDefaultAction: category == selectedCategory,
              onPressed: () => Navigator.of(sheetContext).pop(category),
              child: Text(category),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) {
      onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: LuxuryPalette.divider),
          ),
          child: CupertinoButton(
            key: const Key('score-category-dropdown'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            minimumSize: const Size(0, 0),
            borderRadius: BorderRadius.circular(999),
            onPressed: () => unawaited(_showMenu(context)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.slider_horizontal_3,
                  size: 15,
                  color: LuxuryPalette.goldBright,
                ),
                const SizedBox(width: 8),
                Text(
                  selectedCategory,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: LuxuryPalette.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  CupertinoIcons.chevron_down,
                  size: 13,
                  color: LuxuryPalette.textSubtle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreMasonryGrid extends StatelessWidget {
  final List<_ScoreCardData> scores;
  final ValueChanged<_ScoreCardData> onScorePressed;

  const _ScoreMasonryGrid({required this.scores, required this.onScorePressed});

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const _EmptyScores();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnCount = width >= 920
            ? 4
            : width >= 620
            ? 3
            : 2;
        final gap = width >= 620 ? 14.0 : 10.0;
        final columns = List.generate(columnCount, (_) => <_ScoreCardData>[]);
        final columnHeights = List.filled(columnCount, 0.0);

        for (final score in scores) {
          var targetColumn = 0;
          for (var i = 1; i < columnHeights.length; i += 1) {
            if (columnHeights[i] < columnHeights[targetColumn]) {
              targetColumn = i;
            }
          }

          columns[targetColumn].add(score);
          columnHeights[targetColumn] += score.coverHeight + 150;
        }

        return Row(
          key: const Key('score-masonry-grid'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < columns.length; index += 1) ...[
              if (index > 0) SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    for (final score in columns[index]) ...[
                      _ScoreCard(
                        score: score,
                        onPressed: () => onScorePressed(score),
                      ),
                      SizedBox(height: gap),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final _ScoreCardData score;
  final VoidCallback onPressed;

  const _ScoreCard({required this.score, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: Key('score-card-${score.seed}'),
      decoration: BoxDecoration(
        color: LuxuryPalette.panelRaised.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxuryPalette.divider),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 0),
        borderRadius: BorderRadius.circular(18),
        onPressed: onPressed,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetPreview(score: score),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _MiniTag(label: score.category, color: score.accent),
                      const SizedBox(width: 6),
                      _MiniTag(
                        label: score.assetPath == null ? '预览' : 'MIDI',
                        color: score.assetPath == null
                            ? LuxuryPalette.textSubtle
                            : LuxuryPalette.goldBright,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          score.level,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: LuxuryPalette.textSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    score.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.18,
                      fontWeight: FontWeight.w600,
                      color: LuxuryPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    score.composer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LuxuryPalette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.clock,
                        size: 13,
                        color: LuxuryPalette.textSubtle,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        score.duration,
                        style: const TextStyle(
                          fontSize: 11,
                          color: LuxuryPalette.textSubtle,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        CupertinoIcons.bookmark,
                        size: 13,
                        color: LuxuryPalette.goldBright,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        score.saves,
                        style: const TextStyle(
                          fontSize: 11,
                          color: LuxuryPalette.goldBright,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetPreview extends StatelessWidget {
  final _ScoreCardData score;

  const _SheetPreview({required this.score});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
      child: Container(
        height: score.coverHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3E7D1), Color(0xFFD9C59B)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(
                color: score.accent.withValues(alpha: 0.22),
                child: const SizedBox(width: 8),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CupertinoColors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_2,
                  size: 18,
                  color: LuxuryPalette.goldBright,
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  child: Text(
                    score.assetPath == null ? '仅预览' : '可生成五线谱',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: LuxuryPalette.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: LuxuryPalette.textPrimary,
        ),
      ),
    );
  }
}

class _SoundfontBadge extends StatelessWidget {
  final MidiPlayerController player;

  const _SoundfontBadge({required this.player});

  @override
  Widget build(BuildContext context) {
    final color = switch (player.soundfontState) {
      SoundfontSetupState.ready => LuxuryPalette.emerald,
      SoundfontSetupState.failed => LuxuryPalette.ruby,
      SoundfontSetupState.downloading => LuxuryPalette.goldBright,
      _ => LuxuryPalette.gold,
    };
    final text = switch (player.soundfontState) {
      SoundfontSetupState.ready => '音色',
      SoundfontSetupState.failed => '异常',
      SoundfontSetupState.downloading => '下载',
      SoundfontSetupState.checking => '检查',
      SoundfontSetupState.idle => '准备',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: Row(
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

class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8CF99), Color(0xFFC49A57)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: LuxuryPalette.gold.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CupertinoButton(
        key: const Key('import-score'),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        borderRadius: BorderRadius.circular(18),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: CupertinoColors.black),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CupertinoColors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScores extends StatelessWidget {
  const _EmptyScores();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LuxuryPalette.divider),
      ),
      child: const Center(
        child: Text(
          '暂无乐谱',
          style: TextStyle(fontSize: 14, color: LuxuryPalette.textMuted),
        ),
      ),
    );
  }
}

class _ScoreCardData {
  final String title;
  final String composer;
  final String category;
  final String level;
  final String duration;
  final String saves;
  final double coverHeight;
  final Color accent;
  final int seed;
  final String? assetPath;

  const _ScoreCardData({
    required this.title,
    required this.composer,
    required this.category,
    required this.level,
    required this.duration,
    required this.saves,
    required this.coverHeight,
    required this.accent,
    required this.seed,
    this.assetPath,
  });

  PracticeScoreMetadata toPracticeMetadata() {
    return PracticeScoreMetadata(
      title: title,
      composer: composer,
      category: category,
      level: level,
      duration: duration,
      saves: saves,
      accent: accent,
      seed: seed,
      assetPath: assetPath,
      sourceFingerprint: assetPath == null ? null : 'asset:$assetPath',
    );
  }
}
