import 'dart:async';
import 'dart:isolate';

import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import 'midi_part_analyzer.dart';
import 'midi_score_selection.dart';
import 'midi_to_musicxml_converter.dart';

class MidiNotationPreparation {
  final MidiScoreCatalog catalog;
  final MidiScoreSelection selection;
  final ScoreSession session;

  factory MidiNotationPreparation({
    required MidiScoreCatalog catalog,
    required MidiScoreSelection selection,
    required ScoreSession session,
  }) => MidiNotationPreparation._(
    catalog: catalog,
    selection: selection,
    session: session,
  );

  const MidiNotationPreparation._({
    required this.catalog,
    required this.selection,
    required this.session,
  });
}

abstract interface class MidiNotationBuilder {
  void cancel();

  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  });

  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  });
}

class MidiNotationCancelledException implements Exception {
  const MidiNotationCancelledException();

  @override
  String toString() => 'MIDI notation operation cancelled';
}

class MidiNotationService implements MidiNotationBuilder {
  _MidiNotationWorkerTask? _activeTask;

  @override
  void cancel() {
    _activeTask?.cancel();
    _activeTask = null;
  }

  @override
  Future<MidiNotationPreparation> prepare(
    MidiSongData song, {
    required String fingerprint,
    required Set<MidiPartKind> globalDefaultKinds,
    Set<String>? songDefaultPartIds,
  }) async {
    final copiedGlobalDefaultKinds = Set<MidiPartKind>.of(globalDefaultKinds);
    final copiedSongDefaultPartIds = songDefaultPartIds == null
        ? null
        : Set<String>.of(songDefaultPartIds);
    final prepared = await _runWorker<_PreparedNotation>(
      _NotationWorkerRequest.prepare(
        song: song,
        fingerprint: fingerprint,
        globalDefaultKinds: copiedGlobalDefaultKinds,
        songDefaultPartIds: copiedSongDefaultPartIds,
      ),
      debugName: 'MIDI notation preparation',
    );
    return MidiNotationPreparation(
      catalog: prepared.catalog,
      selection: prepared.selection,
      session: _asMidiNotation(
        song,
        prepared.notation,
        fingerprint: prepared.catalog.fingerprint,
      ),
    );
  }

  @override
  Future<ScoreSession> rebuild(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  }) async {
    final copiedSelectedPartIds = Set<String>.of(selectedPartIds);
    final notation = await _runWorker<MidiNotationResult>(
      _NotationWorkerRequest.rebuild(
        song: song,
        catalog: catalog,
        selectedPartIds: copiedSelectedPartIds,
      ),
      debugName: 'MIDI notation rebuild',
    );
    return _asMidiNotation(song, notation, fingerprint: catalog.fingerprint);
  }

  Future<T> _runWorker<T>(
    _NotationWorkerRequest request, {
    required String debugName,
  }) async {
    cancel();
    final task = _MidiNotationWorkerTask();
    _activeTask = task;
    try {
      return await task.run<T>(request, debugName: debugName);
    } finally {
      if (identical(_activeTask, task)) _activeTask = null;
    }
  }
}

_PreparedNotation _prepareNotation(
  MidiSongData song, {
  required String fingerprint,
  required Set<MidiPartKind> globalDefaultKinds,
  Set<String>? songDefaultPartIds,
}) {
  final catalog = MidiPartAnalyzer().analyze(song, fingerprint: fingerprint);
  final selection = MidiScoreSelectionResolver().resolve(
    catalog,
    globalDefaultKinds: globalDefaultKinds,
    songDefaultPartIds: songDefaultPartIds,
  );
  final notation = MidiToMusicXmlConverter().convertSync(
    song,
    catalog: catalog,
    selectedPartIds: selection.partIds,
  );
  return _PreparedNotation(
    catalog: catalog,
    selection: selection,
    notation: notation,
  );
}

ScoreSession _asMidiNotation(
  MidiSongData song,
  MidiNotationResult result, {
  required String fingerprint,
}) => ScoreSession(
  songData: song,
  musicXml: result.musicXml,
  sourceType: ScoreSourceType.midiNotation,
  measures: result.measures,
  mappingStatus: ScoreMappingStatus.complete,
  sourceFingerprint: fingerprint,
  selectedPartIds: result.selectedPartIds,
  notationWarnings: result.warnings,
);

class _PreparedNotation {
  final MidiScoreCatalog catalog;
  final MidiScoreSelection selection;
  final MidiNotationResult notation;

  const _PreparedNotation({
    required this.catalog,
    required this.selection,
    required this.notation,
  });
}

enum _NotationWorkerKind { prepare, rebuild }

class _NotationWorkerRequest {
  final _NotationWorkerKind kind;
  final MidiSongData song;
  final String? fingerprint;
  final Set<MidiPartKind>? globalDefaultKinds;
  final Set<String>? songDefaultPartIds;
  final MidiScoreCatalog? catalog;
  final Set<String>? selectedPartIds;
  SendPort? responsePort;

  _NotationWorkerRequest.prepare({
    required this.song,
    required String this.fingerprint,
    required Set<MidiPartKind> this.globalDefaultKinds,
    required this.songDefaultPartIds,
  }) : kind = _NotationWorkerKind.prepare,
       catalog = null,
       selectedPartIds = null;

  _NotationWorkerRequest.rebuild({
    required this.song,
    required MidiScoreCatalog this.catalog,
    required Set<String> this.selectedPartIds,
  }) : kind = _NotationWorkerKind.rebuild,
       fingerprint = null,
       globalDefaultKinds = null,
       songDefaultPartIds = null;
}

class _NotationWorkerSuccess {
  final Object value;

  const _NotationWorkerSuccess(this.value);
}

class _NotationWorkerFailure {
  final Object error;
  final String stackTrace;

  const _NotationWorkerFailure(this.error, this.stackTrace);
}

void _runNotationWorker(_NotationWorkerRequest request) {
  final responsePort = request.responsePort!;
  try {
    final Object result = switch (request.kind) {
      _NotationWorkerKind.prepare => _prepareNotation(
        request.song,
        fingerprint: request.fingerprint!,
        globalDefaultKinds: request.globalDefaultKinds!,
        songDefaultPartIds: request.songDefaultPartIds,
      ),
      _NotationWorkerKind.rebuild => MidiToMusicXmlConverter().convertSync(
        request.song,
        catalog: request.catalog!,
        selectedPartIds: request.selectedPartIds!,
      ),
    };
    responsePort.send(_NotationWorkerSuccess(result));
  } catch (error, stackTrace) {
    responsePort.send(_NotationWorkerFailure(error, stackTrace.toString()));
  }
}

class _MidiNotationWorkerTask {
  final Completer<Object> _completer = Completer<Object>();
  Isolate? _isolate;
  ReceivePort? _responsePort;
  bool _isCancelled = false;

  Future<T> run<T>(
    _NotationWorkerRequest request, {
    required String debugName,
  }) async {
    final responsePort = ReceivePort();
    _responsePort = responsePort;
    request.responsePort = responsePort.sendPort;
    responsePort.listen(_handleResponse);
    unawaited(_spawn(request, debugName: debugName));
    return (await _completer.future) as T;
  }

  Future<void> _spawn(
    _NotationWorkerRequest request, {
    required String debugName,
  }) async {
    try {
      final isolate = await Isolate.spawn(
        _runNotationWorker,
        request,
        debugName: debugName,
      );
      if (_isCancelled) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error, stackTrace) {
      if (!_completer.isCompleted) {
        _completeError(error, stackTrace);
      }
    }
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_completer.isCompleted) {
      _completeError(
        const MidiNotationCancelledException(),
        StackTrace.current,
      );
    }
  }

  void _handleResponse(Object? message) {
    if (_completer.isCompleted) return;
    switch (message) {
      case _NotationWorkerSuccess(:final value):
        _complete(value);
      case _NotationWorkerFailure(:final error, :final stackTrace):
        _completeError(error, StackTrace.fromString(stackTrace));
      default:
        _completeError(
          StateError('MIDI notation worker returned an invalid response'),
          StackTrace.current,
        );
    }
  }

  void _complete(Object value) {
    _cleanup();
    _completer.complete(value);
  }

  void _completeError(Object error, StackTrace stackTrace) {
    _cleanup();
    _completer.completeError(error, stackTrace);
  }

  void _cleanup() {
    _responsePort?.close();
    _responsePort = null;
    _isolate = null;
  }
}
