import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import '../midi/measure_map.dart';
import '../midi/tempo_map.dart';
import '../score/piece_manifest.dart';
import 'midi_part_analyzer.dart';
import 'midi_to_musicxml_converter.dart';

/// 一颗已经落到小节上的演奏者音符。播放时间线仍以原始 MIDI 为准。
class PieceAlignedNote {
  final int trackIndex;
  final int channel;
  final int noteNumber;
  final int startTick;
  final int endTick;
  final int measureOrdinal;

  const PieceAlignedNote({
    required this.trackIndex,
    required this.channel,
    required this.noteNumber,
    required this.startTick,
    required this.endTick,
    required this.measureOrdinal,
  });
}

/// 曲目包的记谱对齐：MusicXML 只用于显示，原始 MIDI 仍是播放和跟随数据。
class PieceScoreAlignment {
  final PieceManifest manifest;
  final MidiSongData song;
  final String musicXml;
  final Set<String> notationPartIds;
  final List<ScoreMeasureBoundary> measures;
  final List<PieceAlignedNote> performerNotes;
  final Set<MidiNotationWarning> warnings;

  factory PieceScoreAlignment.compile(
    MidiSongData song,
    PieceManifest manifest, {
    MidiPartAnalyzer? analyzer,
    MidiToMusicXmlConverter? converter,
  }) {
    _requireSongContract(song, manifest);
    final catalog = (analyzer ?? MidiPartAnalyzer()).analyze(
      song,
      fingerprint: 'piece:${manifest.id}',
    );
    final notationPartIds = _notationPartIds(catalog, manifest);
    final notation = (converter ?? MidiToMusicXmlConverter()).convertSync(
      song,
      catalog: catalog,
      selectedPartIds: notationPartIds,
    );
    _requireMeasures(song, manifest, notation);
    return PieceScoreAlignment._(
      manifest: manifest,
      song: song,
      musicXml: notation.musicXml,
      notationPartIds: notationPartIds,
      measures: notation.measures,
      performerNotes: _alignPerformerNotes(
        song,
        manifest.performerTrackIndexes,
        notation.measures,
      ),
      warnings: notation.warnings,
    );
  }

  const PieceScoreAlignment._({
    required this.manifest,
    required this.song,
    required this.musicXml,
    required this.notationPartIds,
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
    sourceFingerprint: 'piece:${manifest.id}',
    selectedPartIds: notationPartIds,
    notationWarnings: warnings,
  );

  int measureOrdinalAtTick(int tick) =>
      _measureContaining(measures, tick).ordinal;

  int measureStartTick(int ordinal) {
    for (final measure in measures) {
      if (measure.ordinal == ordinal) return measure.startTick;
    }
    throw ArgumentError.value(ordinal, 'ordinal', '${manifest.id} 没有该小节');
  }

  int performerNoteCountInMeasure(int ordinal) {
    if (measures.every((measure) => measure.ordinal != ordinal)) {
      throw ArgumentError.value(ordinal, 'ordinal', '${manifest.id} 没有该小节');
    }
    return performerNotes
        .where((note) => note.measureOrdinal == ordinal)
        .length;
  }
}

void _requireSongContract(MidiSongData song, PieceManifest manifest) {
  if (song.ticksPerBeat != manifest.ticksPerBeat) {
    throw StateError('${manifest.id} 的 PPQ 必须是 ${manifest.ticksPerBeat}');
  }
  final numerator = manifest.timeSignatureNumerator;
  final denominator = manifest.timeSignatureDenominator;
  if (numerator != null &&
      denominator != null &&
      (song.timeSignatureChanges.isEmpty ||
          song.timeSignatureChanges.any(
            (signature) =>
                signature.tick != 0 ||
                signature.numerator != numerator ||
                signature.denominator != denominator,
          ))) {
    throw StateError('${manifest.id} 的拍号与曲目包不一致');
  }
  for (final spec in manifest.tracks) {
    final track = _track(song, manifest.id, spec.index);
    if (!track.hasNotes) {
      throw StateError('${manifest.id} 轨道 ${spec.index} 没有音符');
    }
    if (track.programByChannel.length != 1 ||
        track.programByChannel.values.single != spec.program) {
      throw StateError(
        '${manifest.id} 轨道 ${spec.index} 的 Program 必须是 ${spec.program}',
      );
    }
    final expectedName = spec.name;
    if (expectedName != null && track.name != expectedName) {
      throw StateError('${manifest.id} 轨道 ${spec.index} 的名称必须是 $expectedName');
    }
  }
}

Set<String> _notationPartIds(MidiScoreCatalog catalog, PieceManifest manifest) {
  final performer = manifest.performerTrackIndexes;
  final accompaniment = manifest.accompanimentTrackIndexes;
  final selected = <MidiScorePart>[];
  for (final part in catalog.parts) {
    final indexes = part.sources.map((source) => source.trackIndex).toSet();
    final usesPerformer = indexes.intersection(performer).isNotEmpty;
    final usesAccompaniment = indexes.intersection(accompaniment).isNotEmpty;
    if (usesPerformer && usesAccompaniment) {
      throw StateError('${manifest.id} 的演奏者轨道和伴奏轨道被分进同一声部');
    }
    if (!usesPerformer) continue;
    if (!performer.containsAll(indexes)) {
      throw StateError('${manifest.id} 的记谱声部包含未声明的演奏者轨道');
    }
    selected.add(part);
  }
  final covered = {
    for (final part in selected)
      for (final source in part.sources) source.trackIndex,
  };
  if (covered.length != performer.length || !covered.containsAll(performer)) {
    throw StateError('${manifest.id} 的演奏者轨道没有全部进入记谱声部');
  }
  return selected.map((part) => part.id).toSet();
}

void _requireMeasures(
  MidiSongData song,
  PieceManifest manifest,
  MidiNotationResult notation,
) {
  final tempoMap = TempoMap(
    ticksPerBeat: song.ticksPerBeat,
    tempoChanges: song.tempoChanges,
  );
  final sourceMeasures = MeasureMap(song: song, tempoMap: tempoMap).measures;
  if (sourceMeasures.length != notation.measures.length) {
    throw StateError('${manifest.id} 派生谱的小节数与 MIDI 小节线不一致');
  }
  for (var index = 0; index < sourceMeasures.length; index++) {
    final source = sourceMeasures[index];
    final derived = notation.measures[index];
    if (source.number != derived.ordinal ||
        source.startTick != derived.startTick ||
        source.endTick != derived.endTick ||
        !derived.isInteractive) {
      throw StateError('${manifest.id} 第 ${source.number} 小节的 tick 边界不一致');
    }
  }
  final writtenMeasures = RegExp(
    r'<measure\b',
  ).allMatches(notation.musicXml).length;
  final expectedMeasures =
      notation.measures.length * notation.selectedPartIds.length;
  if (writtenMeasures != expectedMeasures) {
    throw StateError('${manifest.id} 的 MusicXML 小节标签数与对齐表不一致');
  }
}

List<PieceAlignedNote> _alignPerformerNotes(
  MidiSongData song,
  Set<int> performerTrackIndexes,
  List<ScoreMeasureBoundary> measures,
) {
  final aligned = <PieceAlignedNote>[];
  for (final index in performerTrackIndexes) {
    for (final note in _track(song, '曲目包', index).notes) {
      aligned.add(
        PieceAlignedNote(
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
  return List<PieceAlignedNote>.unmodifiable(aligned);
}

MidiTrackInfo _track(MidiSongData song, String pieceId, int index) {
  for (final track in song.tracks) {
    if (track.index == index) return track;
  }
  throw StateError('$pieceId 缺少轨道 $index');
}

ScoreMeasureBoundary _measureContaining(
  List<ScoreMeasureBoundary> measures,
  int tick,
) {
  if (tick < 0) {
    throw ArgumentError.value(tick, 'tick', '必须大于等于 0');
  }
  if (measures.isEmpty) {
    throw StateError('曲目包对齐结果没有小节');
  }
  if (tick < measures.first.startTick) {
    throw StateError('tick $tick 早于第一小节');
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
    throw StateError('tick $tick 不在小节 ${measure.ordinal} 内');
  }
  return measure;
}
