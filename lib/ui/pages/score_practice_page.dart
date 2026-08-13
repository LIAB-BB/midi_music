import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/import/score_import_service.dart';
import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../../core/score/score_playback_coordinator.dart';
import '../../core/score/score_renderer_protocol.dart';
import '../../core/settings/app_settings.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import '../widgets/interactive_score_view.dart';
import '../widgets/score_transport_bar.dart';
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
  final ScoreSession? initialSession;
  final ScoreSurfaceFactory? surfaceFactory;
  final ScoreImportService? importService;

  const ScorePracticePage({
    super.key,
    required this.score,
    this.initialSession,
    this.surfaceFactory,
    this.importService,
  });

  @override
  State<ScorePracticePage> createState() => _ScorePracticePageState();
}

class _ScorePracticePageState extends State<ScorePracticePage> {
  final MidiFileParser _parser = MidiFileParser();
  late final ScoreImportService _importService;
  MidiPlayerController? _player;
  ScorePlaybackCoordinator? _coordinator;
  ScoreSession? _displaySession;
  OverlayEntry? _transientMessage;
  Timer? _transientMessageTimer;
  bool _didScheduleInitialLoad = false;
  bool _isImporting = false;
  int _sessionLoadGeneration = 0;

  bool get _hasComplexRepetition =>
      _displaySession?.warnings.contains(ScoreWarning.complexRepetition) ??
      false;

  @override
  void initState() {
    super.initState();
    _importService = widget.importService ?? ScoreImportService();
    _displaySession = widget.initialSession;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = context.read<MidiPlayerController>();
    if (!identical(_player, player)) {
      _player?.removeListener(_handlePlayerChanged);
      _player = player..addListener(_handlePlayerChanged);
      _coordinator = null;
    }
    if (_didScheduleInitialLoad) return;
    _didScheduleInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadInitialScore());
    });
  }

  @override
  void dispose() {
    _player?.removeListener(_handlePlayerChanged);
    _transientMessageTimer?.cancel();
    _transientMessage?.remove();
    super.dispose();
  }

  void _handlePlayerChanged() {
    _coordinator?.syncFromPlayer();
  }

  Future<void> _loadInitialScore() async {
    final player = _player;
    if (player == null) return;
    final initialSession = widget.initialSession;
    if (initialSession != null) {
      player.loadScore(initialSession, songId: widget.score.title);
      player.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );
      return;
    }

    final emptySession = _emptyMidiSession(widget.score.title);
    player.loadScore(emptySession, songId: widget.score.title);
    if (mounted) setState(() => _displaySession = emptySession);
    final assetPath = widget.score.assetPath;
    if (assetPath == null) return;
    final loadGeneration = _sessionLoadGeneration;
    try {
      final data = await rootBundle.load(assetPath);
      final song = _parser.parseBytes(
        data.buffer.asUint8List(),
        fileName: assetPath.split('/').last,
      );
      if (!mounted || loadGeneration != _sessionLoadGeneration) return;
      final session = ScoreSession.midiOnly(song);
      player.loadScore(session, songId: widget.score.title);
      player.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );
      setState(() => _displaySession = session);
    } catch (error) {
      if (mounted) _showAlert('载入失败', '无法载入内置 MIDI：$error');
    }
  }

  void _attachRendererPort(ScoreRendererPort port) {
    final player = _player;
    if (player == null) return;
    _coordinator = ScorePlaybackCoordinator(player: player, port: port);
  }

  void _handleRendererMessage(ScoreRendererMessage message) {
    final result =
        _coordinator?.handleMessage(message) ??
        ScoreMessageHandlingResult.ignored;
    if (result == ScoreMessageHandlingResult.unmappableMeasure) {
      _showTransientMessage('谱面与伴奏小节不一致，无法跳转到这一小节。');
    }
    if (message.type == ScoreRendererMessageType.ready) {
      _coordinator?.syncFromPlayer(force: true);
    }
  }

  void _resumeScoreFollow() {
    _coordinator?.resumeAutoFollow();
    _coordinator?.syncFromPlayer(force: true);
  }

  Future<void> _importMusicXmlForCurrentScore() async {
    if (_isImporting) return;
    _isImporting = true;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['musicxml', 'xml'],
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final session = await _importService.importFile(path);
      if (!mounted) return;
      _sessionLoadGeneration += 1;
      _player?.loadScore(session, songId: widget.score.title, filePath: path);
      setState(() => _displaySession = session);
    } catch (error) {
      if (mounted) _showAlert('导入失败', '无法导入 MusicXML：$error');
    } finally {
      _isImporting = false;
    }
  }

  void _openSettings() {
    unawaited(
      Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsPage())),
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

  void _showTransientMessage(String message) {
    _transientMessageTimer?.cancel();
    _transientMessage?.remove();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 24,
        right: 24,
        bottom: 110,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE6403640),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _transientMessage = entry;
    Overlay.of(context).insert(entry);
    _transientMessageTimer = Timer(const Duration(seconds: 2), () {
      if (identical(_transientMessage, entry)) {
        entry.remove();
        _transientMessage = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final player = context.watch<MidiPlayerController>();
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF8F0DC),
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: const Color(0xFFF8F0DC),
        previousPageTitle: '乐库',
        middle: Text(score.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _ScorePageActions(onOpenSettings: _openSettings),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_hasComplexRepetition) const _ComplexRepeatBanner(),
            Expanded(
              child: KeyedSubtree(
                key: const Key('interactive-score-view'),
                child: InteractiveScoreView(
                  musicXml: _displaySession?.musicXml,
                  onMessage: _handleRendererMessage,
                  onPortReady: _attachRendererPort,
                  onImportMusicXml: _importMusicXmlForCurrentScore,
                  surfaceFactory: widget.surfaceFactory,
                ),
              ),
            ),
            ScoreTransportBar(
              key: const Key('score-transport-bar'),
              player: player,
              onPlaybackInteraction: _resumeScoreFollow,
            ),
          ],
        ),
      ),
    );
  }
}

ScoreSession _emptyMidiSession(String title) => ScoreSession.midiOnly(
  MidiSongData(
    fileName: title,
    format: 1,
    ticksPerBeat: 480,
    tracks: const [],
    timeline: const [],
    tempoChanges: const [],
    timeSignatureChanges: const [],
    totalTicks: 0,
    totalDuration: 0,
  ),
);

class _ScorePageActions extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _ScorePageActions({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      onPressed: onOpenSettings,
      child: const Icon(
        CupertinoIcons.gear_alt_fill,
        size: 18,
        color: Color(0xFF5F4A35),
      ),
    );
  }
}

class _ComplexRepeatBanner extends StatelessWidget {
  const _ComplexRepeatBanner();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE9DDC6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 16,
              color: Color(0xFF715B41),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '此乐谱包含复杂反复，当前按谱面顺序播放。',
                style: TextStyle(fontSize: 12, color: Color(0xFF5F4A35)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
