import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/import/score_import_service.dart';
import '../../core/midi/midi_parser.dart';
import '../../core/midi/midi_player.dart';
import '../../core/notation/midi_notation_service.dart';
import '../../core/notation/midi_score_selection.dart';
import '../../core/score/score_playback_coordinator.dart';
import '../../core/score/score_renderer_protocol.dart';
import '../../core/settings/app_settings.dart';
import '../../models/midi_track.dart';
import '../../models/midi_score_part.dart';
import '../../models/score_session.dart';
import '../widgets/interactive_score_view.dart';
import '../widgets/score_part_picker.dart';
import '../widgets/score_transport_bar.dart';
import 'settings_page.dart';

enum _NotationRetryKind { asset, importPath, prepare }

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
  final String? sourceFingerprint;

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
    this.sourceFingerprint,
  });

  factory PracticeScoreMetadata.imported(
    String fileName, {
    String? sourceFingerprint,
  }) {
    return PracticeScoreMetadata(
      title: fileName,
      composer: '导入乐谱',
      category: '导入',
      level: '',
      duration: '',
      saves: '',
      accent: const Color(0xFFA2773F),
      seed: 0,
      sourceFingerprint: sourceFingerprint,
    );
  }
}

class ScorePracticePage extends StatefulWidget {
  final PracticeScoreMetadata score;
  final ScoreSession? initialSession;
  final ScoreSurfaceFactory? surfaceFactory;
  final ScoreImportService? importService;
  final MidiNotationBuilder? notationBuilder;
  final MidiFileParser? midiParser;

  const ScorePracticePage({
    super.key,
    required this.score,
    this.initialSession,
    this.surfaceFactory,
    this.importService,
    this.notationBuilder,
    this.midiParser,
  });

  @override
  State<ScorePracticePage> createState() => _ScorePracticePageState();
}

class _ScorePracticePageState extends State<ScorePracticePage> {
  late final MidiFileParser _parser;
  late final ScoreImportService _importService;
  late final MidiNotationBuilder _notationBuilder;
  MidiPlayerController? _player;
  ScorePlaybackCoordinator? _coordinator;
  ScoreSession? _displaySession;
  MidiScoreCatalog? _catalog;
  MidiScoreSelection? _selection;
  Set<String>? _selectionBaselinePartIds;
  OverlayEntry? _transientMessage;
  Timer? _transientMessageTimer;
  bool _didScheduleInitialLoad = false;
  bool _isImporting = false;
  bool _isGeneratingNotation = false;
  bool _isSavingDefault = false;
  bool _isTemporarySelection = false;
  bool _notationWarningsDismissed = false;
  String? _notationError;
  int _notationGeneration = 0;
  int? _activeRetryGeneration;
  _NotationRetryKind? _retryKind;
  String? _retryAssetPath;
  String? _retryImportPath;
  ScoreSession? _retryMidiSession;
  String? _retryFingerprint;

  bool get _hasComplexRepetition =>
      _displaySession?.warnings.contains(ScoreWarning.complexRepetition) ??
      false;

  @override
  void initState() {
    super.initState();
    _parser = widget.midiParser ?? MidiFileParser();
    _importService = widget.importService ?? ScoreImportService();
    _notationBuilder = widget.notationBuilder ?? MidiNotationService();
    final initialSession = widget.initialSession;
    _displaySession = initialSession?.sourceType == ScoreSourceType.midiOnly
        ? null
        : initialSession;
    _isGeneratingNotation =
        initialSession?.sourceType == ScoreSourceType.midiOnly ||
        (initialSession == null && widget.score.assetPath != null);
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
    _beginNotationGeneration();
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
    final generation = _beginNotationGeneration();
    final initialSession = widget.initialSession;
    if (initialSession != null) {
      player.loadScore(initialSession, songId: widget.score.title);
      player.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );
      if (initialSession.sourceType == ScoreSourceType.midiOnly) {
        await _prepareMidiNotation(
          initialSession,
          generation: generation,
          fingerprint:
              initialSession.sourceFingerprint ??
              widget.score.sourceFingerprint ??
              _fallbackFingerprint(initialSession.songData),
        );
      }
      return;
    }

    final assetPath = widget.score.assetPath;
    if (assetPath == null) {
      _clearRetryTarget();
      final emptySession = _emptyMidiSession(widget.score.title);
      player.loadScore(emptySession, songId: widget.score.title);
      player.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );
      if (mounted) setState(() => _displaySession = emptySession);
      return;
    }
    await _loadAssetScore(assetPath, generation: generation);
  }

  Future<void> _loadAssetScore(
    String assetPath, {
    required int generation,
  }) async {
    if (!_isCurrentGeneration(generation)) return;
    _setAssetRetryTarget(assetPath);
    _player?.clearScore();
    setState(() {
      _displaySession = null;
      _catalog = null;
      _selection = null;
      _selectionBaselinePartIds = null;
      _isTemporarySelection = false;
      _notationError = null;
      _isGeneratingNotation = true;
      _notationWarningsDismissed = false;
    });
    try {
      final data = await rootBundle.load(assetPath);
      if (!_isCurrentGeneration(generation)) return;
      final song = await _parser.parseBytesInBackground(
        data.buffer.asUint8List(),
        fileName: assetPath.split('/').last,
      );
      if (!_isCurrentGeneration(generation)) return;
      final fingerprint = 'asset:$assetPath';
      final session = ScoreSession.midiOnly(
        song,
        sourceFingerprint: fingerprint,
      );
      _setPrepareRetryTarget(session, fingerprint);
      _player?.loadScore(session, songId: widget.score.title);
      await _prepareMidiNotation(
        session,
        generation: generation,
        fingerprint: fingerprint,
      );
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      _enterNotationError(error);
    }
  }

  Future<void> _prepareMidiNotation(
    ScoreSession midiSession, {
    required int generation,
    required String fingerprint,
  }) async {
    if (!_isCurrentGeneration(generation)) return;
    _setPrepareRetryTarget(midiSession, fingerprint);
    setState(() {
      _displaySession = null;
      _catalog = null;
      _selection = null;
      _selectionBaselinePartIds = null;
      _isTemporarySelection = false;
      _notationError = null;
      _isGeneratingNotation = true;
      _notationWarningsDismissed = false;
    });

    try {
      final settings = context.read<AppSettingsController>();
      await settings.load();
      if (!_isCurrentGeneration(generation)) return;
      _player?.setSpeed(settings.defaultPlaybackSpeed);
      final preparation = await _notationBuilder.prepare(
        midiSession.songData,
        fingerprint: fingerprint,
        globalDefaultKinds: settings.defaultScorePartKinds,
        songDefaultPartIds: settings.scorePartSelectionForSong(fingerprint),
      );
      if (!_isCurrentGeneration(generation)) return;
      final generated = preparation.session;
      if (!identical(generated.songData, midiSession.songData) ||
          !generated.hasInteractiveScore ||
          !(_player?.updateScorePresentation(generated) ?? false)) {
        throw StateError('生成的谱面无法与当前 MIDI 对齐');
      }
      setState(() {
        _displaySession = generated;
        _catalog = preparation.catalog;
        _selection = preparation.selection;
        _selectionBaselinePartIds = Set<String>.unmodifiable(
          preparation.selection.partIds,
        );
        _isTemporarySelection = false;
        _notationError = null;
        _isGeneratingNotation = false;
        _notationWarningsDismissed = false;
      });
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      _enterNotationError(error);
    }
  }

  bool _isCurrentGeneration(int generation) =>
      mounted && generation == _notationGeneration;

  void _enterNotationError(Object error) {
    setState(() {
      _displaySession = null;
      _catalog = null;
      _selection = null;
      _selectionBaselinePartIds = null;
      _isTemporarySelection = false;
      _notationError = _describeNotationError(error);
      _isGeneratingNotation = false;
      _notationWarningsDismissed = false;
    });
  }

  String _describeNotationError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '').trim();
    return message.isEmpty ? '请检查 MIDI 文件后重试。' : message;
  }

  String _fallbackFingerprint(MidiSongData song) =>
      'midi:session:${song.fileName}:${song.totalTicks}:${song.timeline.length}';

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

  Future<void> _importScoreForCurrentPage() async {
    if (_isImporting) return;
    _isImporting = true;
    int? importGeneration;
    var wasAwaitingInitialNotation = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mid', 'midi', 'musicxml', 'xml', 'pdf'],
        allowMultiple: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      wasAwaitingInitialNotation =
          _displaySession == null && _isGeneratingNotation;
      importGeneration = _beginNotationGeneration();
      _setImportRetryTarget(path);
      await _importPath(
        path,
        generation: importGeneration,
        terminalOnFailure: wasAwaitingInitialNotation,
      );
    } catch (error) {
      if (!mounted) return;
      final generation = importGeneration;
      if (generation != null && !_isCurrentGeneration(generation)) return;
      if (generation != null && wasAwaitingInitialNotation) {
        _enterNotationError(error);
      } else {
        _showAlert('导入失败', '无法导入乐谱文件：$error');
      }
    } finally {
      _isImporting = false;
    }
  }

  Future<void> _importPath(
    String path, {
    required int generation,
    required bool terminalOnFailure,
  }) async {
    if (!_isCurrentGeneration(generation)) return;
    _setImportRetryTarget(path);
    if (terminalOnFailure) {
      setState(() {
        _displaySession = null;
        _catalog = null;
        _selection = null;
        _selectionBaselinePartIds = null;
        _isTemporarySelection = false;
        _notationError = null;
        _isGeneratingNotation = true;
        _notationWarningsDismissed = false;
      });
    }
    try {
      final session = await _importService.importFile(path);
      if (!mounted) return;
      if (!_isCurrentGeneration(generation)) return;
      _player?.loadScore(session, songId: widget.score.title, filePath: path);
      _player?.setSpeed(
        context.read<AppSettingsController>().defaultPlaybackSpeed,
      );
      if (session.sourceType == ScoreSourceType.midiOnly) {
        final fingerprint =
            session.sourceFingerprint ?? _fallbackFingerprint(session.songData);
        _setPrepareRetryTarget(session, fingerprint);
        await _prepareMidiNotation(
          session,
          generation: generation,
          fingerprint: fingerprint,
        );
      } else if (_isCurrentGeneration(generation)) {
        _clearRetryTarget();
        setState(() {
          _displaySession = session;
          _catalog = null;
          _selection = null;
          _selectionBaselinePartIds = null;
          _isTemporarySelection = false;
          _notationError = null;
          _isGeneratingNotation = false;
          _notationWarningsDismissed = false;
        });
      }
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      if (terminalOnFailure) {
        _enterNotationError(error);
      } else {
        _showAlert('导入失败', '无法导入乐谱文件：$error');
      }
    }
  }

  void _retryNotation() {
    if (_activeRetryGeneration == _notationGeneration) return;
    final retryKind = _retryKind;
    switch (retryKind) {
      case _NotationRetryKind.asset:
        final assetPath = _retryAssetPath;
        if (assetPath == null) return;
        _runNotationRetry(
          (generation) => _loadAssetScore(assetPath, generation: generation),
        );
        return;
      case _NotationRetryKind.importPath:
        final importPath = _retryImportPath;
        if (importPath == null || _isImporting) return;
        _runNotationRetry(
          (generation) => _importPath(
            importPath,
            generation: generation,
            terminalOnFailure: true,
          ),
          isImport: true,
        );
        return;
      case _NotationRetryKind.prepare:
        final midiSession = _retryMidiSession;
        final fingerprint = _retryFingerprint;
        if (midiSession == null || fingerprint == null) return;
        _runNotationRetry(
          (generation) => _prepareMidiNotation(
            midiSession,
            generation: generation,
            fingerprint: fingerprint,
          ),
        );
        return;
      case null:
        return;
    }
  }

  void _runNotationRetry(
    Future<void> Function(int generation) operation, {
    bool isImport = false,
  }) {
    if (isImport) _isImporting = true;
    final generation = _beginNotationGeneration();
    _activeRetryGeneration = generation;
    unawaited(
      operation(generation).whenComplete(() {
        if (_activeRetryGeneration == generation) {
          _activeRetryGeneration = null;
        }
        if (isImport) _isImporting = false;
      }),
    );
  }

  void _setAssetRetryTarget(String assetPath) {
    _retryKind = _NotationRetryKind.asset;
    _retryAssetPath = assetPath;
    _retryImportPath = null;
    _retryMidiSession = null;
    _retryFingerprint = null;
  }

  void _setImportRetryTarget(String importPath) {
    _retryKind = _NotationRetryKind.importPath;
    _retryAssetPath = null;
    _retryImportPath = importPath;
    _retryMidiSession = null;
    _retryFingerprint = null;
  }

  void _setPrepareRetryTarget(ScoreSession midiSession, String fingerprint) {
    _retryKind = _NotationRetryKind.prepare;
    _retryAssetPath = null;
    _retryImportPath = null;
    _retryMidiSession = midiSession;
    _retryFingerprint = fingerprint;
  }

  void _clearRetryTarget() {
    _retryKind = null;
    _retryAssetPath = null;
    _retryImportPath = null;
    _retryMidiSession = null;
    _retryFingerprint = null;
  }

  Future<void> _openPartPicker() async {
    if (_isSavingDefault) return;
    final catalog = _catalog;
    final selection = _selection;
    final session = _displaySession;
    if (catalog == null || selection == null || session == null) return;
    final result = await showScorePartPicker(
      context,
      catalog: catalog,
      selectedPartIds: selection.partIds,
      origin: selection.origin,
      warnings: session.notationWarnings,
      originLabelOverride: _isTemporarySelection ? '当前临时选择' : null,
    );
    if (!mounted || result == null) return;
    await _applyPartSelection(result);
  }

  Future<void> _applyPartSelection(ScorePartPickerResult result) async {
    final catalog = _catalog;
    final previousSelection = _selection;
    final currentSession = _displaySession;
    if (catalog == null ||
        previousSelection == null ||
        currentSession == null) {
      return;
    }
    final settings = context.read<AppSettingsController>();
    final generation = _beginNotationGeneration();
    setState(() => _isGeneratingNotation = true);
    try {
      final rebuilt = await _notationBuilder.rebuild(
        currentSession.songData,
        catalog: catalog,
        selectedPartIds: result.partIds,
      );
      if (!_isCurrentGeneration(generation)) return;
      if (!identical(rebuilt.songData, currentSession.songData) ||
          !rebuilt.hasInteractiveScore ||
          !(_player?.updateScorePresentation(rebuilt) ?? false)) {
        throw StateError('生成的谱面无法与当前 MIDI 对齐');
      }

      setState(() {
        _displaySession = rebuilt;
        _selection = MidiScoreSelection(
          partIds: result.partIds,
          origin: previousSelection.origin,
        );
        if (result.action == ScorePartPickerAction.apply) {
          final baseline = _selectionBaselinePartIds;
          _isTemporarySelection =
              baseline != null && !setEquals(result.partIds, baseline);
        } else {
          _isTemporarySelection = true;
        }
        _isGeneratingNotation = false;
        _notationWarningsDismissed = false;
      });
    } catch (error) {
      if (error is MidiNotationCancelledException) return;
      if (!_isCurrentGeneration(generation)) return;
      setState(() => _isGeneratingNotation = false);
      _showAlert('无法更新五线谱', _describeNotationError(error));
      return;
    }

    if (result.action == ScorePartPickerAction.apply) return;
    setState(() => _isSavingDefault = true);
    try {
      final MidiSelectionOrigin savedOrigin;
      final String successMessage;
      switch (result.action) {
        case ScorePartPickerAction.apply:
          return;
        case ScorePartPickerAction.setSongDefault:
          await settings.setScorePartSelectionForSong(
            catalog.fingerprint,
            result.partIds,
          );
          savedOrigin = MidiSelectionOrigin.songDefault;
          successMessage = '已设为本曲默认声部';
        case ScorePartPickerAction.setGlobalDefault:
          final selectedKinds = {
            for (final part in catalog.parts)
              if (result.partIds.contains(part.id)) part.kind,
          };
          await settings.setDefaultScorePartKinds(selectedKinds);
          savedOrigin = MidiSelectionOrigin.globalDefault;
          successMessage = '已设为全局默认声部';
      }
      if (!_isCurrentGeneration(generation)) return;
      setState(() {
        _selection = MidiScoreSelection(
          partIds: result.partIds,
          origin: savedOrigin,
        );
        _selectionBaselinePartIds = Set<String>.unmodifiable(result.partIds);
        _isTemporarySelection = false;
      });
      _showTransientMessage(successMessage);
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      _showAlert(
        '无法保存默认声部',
        '当前谱面已作为临时选择保留，但设置未能写入：'
            '${_describeNotationError(error)}',
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingDefault = false);
      } else {
        _isSavingDefault = false;
      }
    }
  }

  int _beginNotationGeneration() {
    _notationBuilder.cancel();
    return ++_notationGeneration;
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
    final notationWarnings = _displaySession?.notationWarnings ?? const {};
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF8F0DC),
      navigationBar: CupertinoNavigationBar(
        border: null,
        backgroundColor: const Color(0xFFF8F0DC),
        previousPageTitle: '乐库',
        middle: Text(
          score.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF2A2118)),
        ),
        trailing: _ScorePageActions(
          showParts: _catalog != null,
          partsEnabled: !_isSavingDefault,
          onOpenParts: _openPartPicker,
          onOpenSettings: _openSettings,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_hasComplexRepetition) const _ComplexRepeatBanner(),
            if (notationWarnings.isNotEmpty && !_notationWarningsDismissed)
              _NotationWarningBanner(
                warnings: notationWarnings,
                onDismiss: () {
                  setState(() => _notationWarningsDismissed = true);
                },
              ),
            if (_displaySession != null && _isGeneratingNotation)
              const _NotationRebuildProgress(),
            Expanded(
              child: KeyedSubtree(
                key: const Key('interactive-score-view'),
                child: _buildScoreBody(),
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

  Widget _buildScoreBody() {
    if (_displaySession == null && _isGeneratingNotation) {
      return _NotationGeneratingState(
        onImportScore: _importScoreForCurrentPage,
      );
    }
    if (_displaySession == null && _notationError != null) {
      return _NotationErrorState(
        message: _notationError!,
        onRetry: _retryNotation,
        onImportScore: _importScoreForCurrentPage,
      );
    }
    return InteractiveScoreView(
      musicXml: _displaySession?.musicXml,
      onMessage: _handleRendererMessage,
      onPortReady: _attachRendererPort,
      onImportScore: _importScoreForCurrentPage,
      surfaceFactory: widget.surfaceFactory,
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
  final bool showParts;
  final bool partsEnabled;
  final VoidCallback onOpenParts;
  final VoidCallback onOpenSettings;

  const _ScorePageActions({
    required this.showParts,
    required this.partsEnabled,
    required this.onOpenParts,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showParts)
          Semantics(
            key: const Key('score-parts'),
            label: '选择显示声部',
            button: true,
            onTap: partsEnabled ? onOpenParts : null,
            child: ExcludeSemantics(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: partsEnabled ? onOpenParts : null,
                child: const Icon(
                  CupertinoIcons.person_2,
                  size: 19,
                  color: Color(0xFF5F4A35),
                ),
              ),
            ),
          ),
        Semantics(
          key: const Key('score-settings'),
          label: '打开设置',
          button: true,
          onTap: onOpenSettings,
          child: ExcludeSemantics(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: onOpenSettings,
              child: const Icon(
                CupertinoIcons.gear_alt_fill,
                size: 18,
                color: Color(0xFF5F4A35),
              ),
            ),
          ),
        ),
      ],
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

class _NotationGeneratingState extends StatelessWidget {
  final VoidCallback onImportScore;

  const _NotationGeneratingState({required this.onImportScore});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8F0DC),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('notation-generating-scroll'),
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 40).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CupertinoActivityIndicator(color: Color(0xFFA2773F)),
                  const SizedBox(height: 12),
                  const Text(
                    '正在生成五线谱',
                    style: TextStyle(color: Color(0xFF5F4A35), fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  CupertinoButton(
                    onPressed: onImportScore,
                    child: const Text('导入文件'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotationErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onImportScore;

  const _NotationErrorState({
    required this.message,
    required this.onRetry,
    required this.onImportScore,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8F0DC),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('notation-error-scroll'),
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 40).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 32,
                    color: Color(0xFFA2773F),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '无法生成五线谱',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF2A2118),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7E6C55),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      CupertinoButton(
                        color: const Color(0xFF5F4A35),
                        onPressed: onRetry,
                        child: const Text('重试'),
                      ),
                      CupertinoButton(
                        onPressed: onImportScore,
                        child: const Text('导入文件'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotationRebuildProgress extends StatelessWidget {
  const _NotationRebuildProgress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Key('notation-rebuild-progress'),
      height: 24,
      child: ColoredBox(
        color: Color(0xFFE9DDC6),
        child: Center(
          child: CupertinoActivityIndicator(
            radius: 7,
            color: Color(0xFFA2773F),
          ),
        ),
      ),
    );
  }
}

class _NotationWarningBanner extends StatelessWidget {
  final Set<MidiNotationWarning> warnings;
  final VoidCallback onDismiss;

  const _NotationWarningBanner({
    required this.warnings,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (warnings.contains(MidiNotationWarning.rhythmQuantized)) '节奏已近似量化',
      if (warnings.contains(MidiNotationWarning.unknownInstrument))
        '未知乐器按独立声部显示',
      if (warnings.contains(MidiNotationWarning.irregularTimeSignature))
        '拍号变化已截断小节',
      if (warnings.contains(MidiNotationWarning.densePassage)) '谱面较密集',
    ];
    return ColoredBox(
      key: const Key('notation-warning-banner'),
      color: const Color(0xFFE9DDC6),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 7, bottom: 7),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 15,
              color: Color(0xFF715B41),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labels.join(' / '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F4A35)),
              ),
            ),
            Semantics(
              key: const Key('dismiss-notation-warnings'),
              label: '关闭记谱提示',
              button: true,
              onTap: onDismiss,
              child: ExcludeSemantics(
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  onPressed: onDismiss,
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 14,
                    color: Color(0xFF715B41),
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
