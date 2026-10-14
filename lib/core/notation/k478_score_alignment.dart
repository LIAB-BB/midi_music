import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import '../midi/measure_map.dart';
import '../midi/tempo_map.dart';
import 'midi_part_analyzer.dart';
import 'midi_to_musicxml_converter.dart';

/// 与 `packages/k478_practice` 的演奏者轨道保持同一编号。
const k478PerformerTrackIndexes = <int>{4, 5};

/// 与 `packages/k478_practice` 的弦乐伴奏轨道保持同一编号。
const k478AccompanimentTrackIndexes = <int>{1, 2, 3};

const _k478TicksPerBeat = 384;
const _k478TimeSignature = (numerator: 2, denominator: 2);
const _k478ProgramsByTrack = <int, int>{1: 40, 2: 40, 3: 42, 4: 0, 5: 0};
const _k478PerformerNames = <int, String>{4: 'upper', 5: 'lower'};

/// 一颗已经落到小节上的演奏者音符。播放时间线仍以原始 MIDI 为准。
class K478AlignedNote {
  final int trackIndex;
  final int channel;
  final int noteNumber;
  final int startTick;
  final int endTick;
  final int measureOrdinal;

  const K478AlignedNote({
    required this.trackIndex,
    required this.channel,
    required this.noteNumber,
    required this.startTick,
    required this.endTick,
    required this.measureOrdinal,
  });
}

/// K.478 的记谱对齐：钢琴 MusicXML 只用于显示，原始 MIDI 仍是播放和跟随数据。
class K478ScoreAlignment {
  final MidiSongData song;
  final String musicXml;
  final String pianoPartId;
  final List<ScoreMeasureBoundary> measures;
  final List<K478AlignedNote> performerNotes;
  final Set<MidiNotationWarning> warnings;

  factory K478ScoreAlignment.compile(
    MidiSongData song, {
    MidiPartAnalyzer? analyzer,
    MidiToMusicXmlConverter? converter,
  }) {
    _requireSongContract(song);
    final catalog = (analyzer ?? MidiPartAnalyzer()).analyze(
      song,
      fingerprint: 'k478:${song.fileName}',
    );
    final piano = _requirePianoPart(catalog);
    final notation = (converter ?? MidiToMusicXmlConverter()).convertSync(
      song,
      catalog: catalog,
      selectedPartIds: {piano.id},
    );
    _requireMeasures(song, notation);
    return K478ScoreAlignment._(
      song: song,
      musicXml: notation.musicXml,
      pianoPartId: piano.id,
      measures: notation.measures,
      performerNotes: _alignPerformerNotes(song, notation.measures),
      warnings: notation.warnings,
    );
  }

  const K478ScoreAlignment._({
    required this.song,
    required this.musicXml,
    required this.pianoPartId,
    required this.measures,
    required this.performerNotes,
    required this.warnings,
  });

  ScoreSession toSession() => ScoreSession(
    songData: song,
    musicXml: musicXml,
    sourceType: ScoreSourceType.midiNotation,
    measures: measures,
    mappingStatus: ScoreMappingStatus.complete,
    sourceFingerprint: 'k478:${song.fileName}',
    selectedPartIds: {pianoPartId},
    notationWarnings: warnings,
  );

  int measureOrdinalAtTick(int tick) =>
      _measureContaining(measures, tick).ordinal;

  int measureStartTick(int ordinal) {
    for (final measure in measures) {
      if (measure.ordinal == ordinal) return measure.startTick;
    }
    throw ArgumentError.value(ordinal, 'ordinal', 'K.478 没有该小节');
  }

  int performerNoteCountInMeasure(int ordinal) {
    if (measures.every((measure) => measure.ordinal != ordinal)) {
      throw ArgumentError.value(ordinal, 'ordinal', 'K.478 没有该小节');
    }
    return performerNotes
        .where((note) => note.measureOrdinal == ordinal)
        .length;
  }
}

void _requireSongContract(MidiSongData song) {
  if (song.ticksPerBeat != _k478TicksPerBeat) {
    throw StateError('K.478 MIDI 的 PPQ 必须是 $_k478TicksPerBeat');
  }
  if (song.timeSignatureChanges.isEmpty ||
      song.timeSignatureChanges.any(
        (signature) =>
            signature.tick != 0 ||
            signature.numerator != _k478TimeSignature.numerator ||
            signature.denominator != _k478TimeSignature.denominator,
      )) {
    throw StateError('K.478 MIDI 必须全程使用 2/2');
  }
  for (final entry in _k478ProgramsByTrack.entries) {
    final track = _track(song, entry.key);
    if (!track.hasNotes) {
      throw StateError('K.478 轨道 ${entry.key} 没有音符');
    }
    if (track.programByChannel.length != 1 ||
        track.programByChannel.values.single != entry.value) {
      throw StateError('K.478 轨道 ${entry.key} 的 Program 必须是 ${entry.value}');
    }
  }
  for (final entry in _k478PerformerNames.entries) {
    final name = _track(song, entry.key).name;
    if (name != entry.value) {
      throw StateError('K.478 轨道 ${entry.key} 的名称必须是 ${entry.value}');
    }
  }
}

MidiScorePart _requirePianoPart(MidiScoreCatalog catalog) {
  final pianoParts = catalog.parts
      .where((part) => part.kind == MidiPartKind.piano)
      .toList(growable: false);
  if (pianoParts.length != 1) {
    throw StateError('K.478 应有且仅有一个钢琴声部');
  }
  final piano = pianoParts.single;
  final indexes = piano.sources.map((source) => source.trackIndex).toSet();
  if (!indexes.containsAll(k478PerformerTrackIndexes) ||
      indexes.length != k478PerformerTrackIndexes.length) {
    throw StateError('K.478 钢琴声部必须正好是轨道 4 和 5');
  }
  for (final index in k478AccompanimentTrackIndexes) {
    final claimedByPiano = piano.sources.any(
      (source) => source.trackIndex == index,
    );
    if (claimedByPiano) {
      throw StateError('K.478 伴奏轨道 $index 不能并入钢琴声部');
    }
  }
  return piano;
}

void _requireMeasures(MidiSongData song, MidiNotationResult notation) {
  final tempoMap = TempoMap(
    ticksPerBeat: song.ticksPerBeat,
    tempoChanges: song.tempoChanges,
  );
  final sourceMeasures = MeasureMap(song: song, tempoMap: tempoMap).measures;
  if (sourceMeasures.length != notation.measures.length) {
    throw StateError('K.478 派生谱的小节数与 MIDI 小节线不一致');
  }
  for (var index = 0; index < sourceMeasures.length; index++) {
    final source = sourceMeasures[index];
    final derived = notation.measures[index];
    if (source.number != derived.ordinal ||
        source.startTick != derived.startTick ||
        source.endTick != derived.endTick ||
        !derived.isInteractive) {
      throw StateError('K.478 第 ${source.number} 小节的 tick 边界不一致');
    }
  }
  final writtenMeasures = RegExp(
    r'<measure\b',
  ).allMatches(notation.musicXml).length;
  if (writtenMeasures != notation.measures.length) {
    throw StateError('K.478 MusicXML 的小节标签数与对齐表不一致');
  }
}

List<K478AlignedNote> _alignPerformerNotes(
  MidiSongData song,
  List<ScoreMeasureBoundary> measures,
) {
  final aligned = <K478AlignedNote>[];
  for (final index in k478PerformerTrackIndexes) {
    for (final note in _track(song, index).notes) {
      aligned.add(
        K478AlignedNote(
          trackIndex: index,
          channel: note.channel,
          noteNumber: note.noteNumber,
          startTick: note.startTick,
          endTick: note.endTick,
          measureOrdinal: _measureContaining(measures, note.startTick).ordinal,
        ),
      );
    }
  }
  aligned.sort((left, right) {
    final tickCompare = left.startTick.compareTo(right.startTick);
    if (tickCompare != 0) return tickCompare;
    final trackCompare = left.trackIndex.compareTo(right.trackIndex);
    if (trackCompare != 0) return trackCompare;
    return left.noteNumber.compareTo(right.noteNumber);
  });
  return List<K478AlignedNote>.unmodifiable(aligned);
}

MidiTrackInfo _track(MidiSongData song, int index) {
  for (final track in song.tracks) {
    if (track.index == index) return track;
  }
  throw StateError('K.478 缺少轨道 $index');
}

ScoreMeasureBoundary _measureContaining(
  List<ScoreMeasureBoundary> measures,
  int tick,
) {
  if (tick < 0) {
    throw ArgumentError.value(tick, 'tick', '必须大于等于 0');
  }
  if (measures.isEmpty) {
    throw StateError('K.478 对齐结果没有小节');
  }
  if (tick < measures.first.startTick) {
    throw StateError('tick $tick 早于 K.478 第一小节');
  }
  var low = 0;
  var high = measures.length - 1;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (measures[mid].startTick <= tick) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  final measure = measures[low];
  final last = low == measures.length - 1;
  final fits = tick < measure.endTick || (last && tick == measure.endTick);
  if (!fits) {
    throw StateError('tick $tick 不在 K.478 小节 ${measure.ordinal} 内');
  }
  return measure;
}
