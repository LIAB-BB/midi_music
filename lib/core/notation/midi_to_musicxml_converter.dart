import 'dart:math' as math;

import '../../models/midi_score_part.dart';
import '../../models/midi_track.dart';
import '../../models/score_session.dart';
import '../midi/measure_map.dart';
import '../midi/tempo_map.dart';

class MidiNotationResult {
  final String musicXml;
  final List<ScoreMeasureBoundary> measures;
  final Set<String> selectedPartIds;
  final Set<MidiNotationWarning> warnings;

  factory MidiNotationResult({
    required String musicXml,
    required List<ScoreMeasureBoundary> measures,
    required Set<String> selectedPartIds,
    required Set<MidiNotationWarning> warnings,
  }) => MidiNotationResult._(
    musicXml: musicXml,
    measures: List<ScoreMeasureBoundary>.unmodifiable(measures),
    selectedPartIds: Set<String>.unmodifiable(selectedPartIds),
    warnings: Set<MidiNotationWarning>.unmodifiable(warnings),
  );

  const MidiNotationResult._({
    required this.musicXml,
    required this.measures,
    required this.selectedPartIds,
    required this.warnings,
  });
}

class MidiToMusicXmlConverter {
  static const int _maxMeasures = 10000;
  static const int _maxGeneratedFragments = 1000000;
  static const int _maxNotationElements = 2000000;
  static const int _maxDynamicStates = 200000;

  MidiNotationResult convertSync(
    MidiSongData song, {
    required MidiScoreCatalog catalog,
    required Set<String> selectedPartIds,
  }) {
    if (selectedPartIds.isEmpty) {
      throw ArgumentError.value(
        selectedPartIds,
        'selectedPartIds',
        '至少选择一个可记谱声部',
      );
    }
    final partsById = {for (final part in catalog.parts) part.id: part};
    final missing = selectedPartIds.difference(partsById.keys.toSet());
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
        selectedPartIds,
        'selectedPartIds',
        '包含目录中不存在的声部 ID: ${missing.join(', ')}',
      );
    }
    if (song.noteTracks.length > 64) {
      throw StateError('MIDI 有音符轨道超过 64 条，无法生成谱面');
    }
    var noteCount = 0;
    final channelsWithNotesByTrack = <int, Set<int>>{};
    for (final track in song.tracks) {
      noteCount += track.notes.length;
      if (noteCount > 500000) {
        throw StateError('MIDI 音符超过 500000 个，无法生成谱面');
      }
      channelsWithNotesByTrack[track.index] = {
        for (final note in track.notes) note.channel,
      };
    }
    final noteSources = <(int, int)>{};
    for (final part in catalog.parts) {
      for (final source in part.sources) {
        final channelsWithNotes = channelsWithNotesByTrack[source.trackIndex];
        if (channelsWithNotes == null) continue;
        for (final channel in source.channels) {
          if (channelsWithNotes.contains(channel)) {
            noteSources.add((source.trackIndex, channel));
          }
        }
      }
    }
    if (noteSources.length > 64) {
      throw StateError('MIDI 有音符声部来源超过 64 个，无法生成谱面');
    }

    final selectedParts = catalog.parts
        .where((part) => selectedPartIds.contains(part.id))
        .toList(growable: false);
    if (_estimatedMeasureCount(song, stopAfter: _maxMeasures) > _maxMeasures) {
      throw StateError('MIDI 生成小节超过 $_maxMeasures 个，无法生成谱面');
    }
    final tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    final sourceMeasures = MeasureMap(song: song, tempoMap: tempoMap).measures;
    if (sourceMeasures.length > _maxMeasures) {
      throw StateError('MIDI 生成小节超过 $_maxMeasures 个，无法生成谱面');
    }
    final measures = sourceMeasures
        .map(
          (measure) => ScoreMeasureBoundary(
            ordinal: measure.number,
            label: measure.label,
            startTick: measure.startTick,
            endTick: measure.endTick,
          ),
        )
        .toList(growable: false);
    final warnings = <MidiNotationWarning>{
      if (song.timeSignatureChanges.any((change) => change.tick > 0))
        MidiNotationWarning.irregularTimeSignature,
      if (selectedParts.any((part) => part.kind == MidiPartKind.other))
        MidiNotationWarning.unknownInstrument,
    };
    final selectedNotesByPart = {
      for (final part in selectedParts) part.id: _selectedNotes(song, part),
    };
    if (!selectedNotesByPart.values.any((notes) => notes.isNotEmpty)) {
      throw StateError('所选声部中没有可记谱音符');
    }
    final xml = _buildDocument(
      song,
      selectedParts,
      selectedNotesByPart,
      sourceMeasures,
      warnings,
    );
    return MidiNotationResult(
      musicXml: xml,
      measures: measures,
      selectedPartIds: selectedPartIds,
      warnings: warnings,
    );
  }

  String _buildDocument(
    MidiSongData song,
    List<MidiScorePart> parts,
    Map<String, List<MidiNote>> selectedNotesByPart,
    List<MeasureInfo> measures,
    Set<MidiNotationWarning> warnings,
  ) {
    final budget = _ConversionBudget(
      maxFragments: _maxGeneratedFragments,
      maxNotationElements: _maxNotationElements,
      maxDynamicStates: _maxDynamicStates,
    );
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
      ..writeln(
        '<!DOCTYPE score-partwise PUBLIC '
        '"-//Recordare//DTD MusicXML 4.0 Partwise//EN" '
        '"http://www.musicxml.org/dtds/partwise.dtd">',
      )
      ..writeln('<score-partwise version="4.0">')
      ..writeln(
        '  <work><work-title>${_escapeXml(song.fileName)}</work-title></work>',
      )
      ..writeln('  <part-list>');
    for (var index = 0; index < parts.length; index++) {
      final id = 'P${index + 1}';
      final name = _escapeXml(parts[index].label);
      buffer
        ..writeln('    <score-part id="$id">')
        ..writeln('      <part-name>$name</part-name>')
        ..writeln(
          '      <score-instrument id="$id-I1">'
          '<instrument-name>$name</instrument-name></score-instrument>',
        )
        ..writeln('    </score-part>');
    }
    buffer.writeln('  </part-list>');
    for (var index = 0; index < parts.length; index++) {
      _writePart(
        buffer,
        song,
        parts[index],
        selectedNotesByPart[parts[index].id]!,
        'P${index + 1}',
        measures,
        warnings,
        budget,
      );
    }
    buffer.writeln('</score-partwise>');
    return buffer.toString();
  }

  void _writePart(
    StringBuffer buffer,
    MidiSongData song,
    MidiScorePart part,
    List<MidiNote> notes,
    String partId,
    List<MeasureInfo> measures,
    Set<MidiNotationWarning> warnings,
    _ConversionBudget budget,
  ) {
    final eventsByMeasure = _bucketEventsByMeasure(
      notes,
      measures,
      song.ticksPerBeat,
      part,
      warnings,
      budget,
    );
    final voicesByMeasure = List<List<List<_ChordEvent>>>.generate(
      measures.length,
      (measureIndex) => _colorVoices(
        eventsByMeasure[measureIndex],
        measures[measureIndex].lengthTick,
        song.ticksPerBeat,
        warnings,
      ),
      growable: false,
    );
    final validBarTieIds = _validBarTieIds(voicesByMeasure, measures, warnings);
    final previousStaffByVoice = <int, int>{};
    buffer.writeln('  <part id="$partId">');
    for (var measureIndex = 0; measureIndex < measures.length; measureIndex++) {
      final measure = measures[measureIndex];
      final voices = voicesByMeasure[measureIndex];
      buffer.writeln('    <measure number="${_escapeXml(measure.label)}">');
      _writeAttributes(
        buffer,
        song.ticksPerBeat,
        part,
        measure,
        measureIndex == 0,
        measureIndex == 0 ||
            measures[measureIndex - 1].numerator != measure.numerator ||
            measures[measureIndex - 1].denominator != measure.denominator,
      );
      _writeTempoDirections(buffer, song, measure);
      _writeVoices(
        buffer,
        voices,
        measure.lengthTick,
        song.ticksPerBeat,
        part,
        previousStaffByVoice,
        validBarTieIds,
      );
      buffer.writeln('    </measure>');
    }
    buffer.writeln('  </part>');
  }

  List<MidiNote> _selectedNotes(MidiSongData song, MidiScorePart part) {
    final notes = <MidiNote>[];
    final tracksByIndex = {for (final track in song.tracks) track.index: track};
    for (final source in part.sources) {
      final track = tracksByIndex[source.trackIndex];
      if (track == null) continue;
      notes.addAll(
        track.notes.where((note) => source.channels.contains(note.channel)),
      );
    }
    notes.sort((a, b) {
      final onset = a.startTick.compareTo(b.startTick);
      return onset != 0 ? onset : a.noteNumber.compareTo(b.noteNumber);
    });
    return notes;
  }

  List<List<_ChordEvent>> _bucketEventsByMeasure(
    List<MidiNote> notes,
    List<MeasureInfo> measures,
    int ticksPerBeat,
    MidiScorePart part,
    Set<MidiNotationWarning> warnings,
    _ConversionBudget budget,
  ) {
    final candidates = _durationCandidates(ticksPerBeat);
    final decomposer = _DurationDecomposer(candidates, budget);
    final groupedByMeasure = List<Map<int, List<_NoteSegment>>>.generate(
      measures.length,
      (_) => <int, List<_NoteSegment>>{},
      growable: false,
    );
    if (measures.isEmpty) return const [];
    final minimumDuration = candidates.first.ticks;
    var onsetMeasureIndex = 0;
    var nextBarTieId = 0;
    for (final note in notes) {
      if (note.endTick <= note.startTick) continue;
      while (onsetMeasureIndex < measures.length &&
          measures[onsetMeasureIndex].endTick <= note.startTick) {
        onsetMeasureIndex++;
      }
      if (onsetMeasureIndex >= measures.length) break;
      final onsetMeasure = measures[onsetMeasureIndex];
      if (note.startTick < onsetMeasure.startTick) continue;
      final rawOffset = note.startTick - onsetMeasure.startTick;
      var quantizedOffset = _quantizeOnset(
        rawOffset,
        onsetMeasure.lengthTick,
        candidates,
      );
      if (onsetMeasure.lengthTick - quantizedOffset < minimumDuration) {
        quantizedOffset = math.max(
          0,
          onsetMeasure.lengthTick - minimumDuration,
        );
      }
      final quantizedStart = onsetMeasure.startTick + quantizedOffset;
      final availableSongDuration = measures.last.endTick - quantizedStart;
      if (availableSongDuration < minimumDuration) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
        continue;
      }
      final quantizedDuration = decomposer.nearest(
        note.endTick - note.startTick,
        availableSongDuration,
      );
      if (quantizedDuration == null) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
        continue;
      }
      final quantizedEnd = quantizedStart + quantizedDuration.duration;
      final fragments = <_PendingFragment>[];
      var hasBrokenCrossBarContinuity = false;
      var measureIndex = onsetMeasureIndex;
      while (measureIndex < measures.length &&
          measures[measureIndex].startTick < quantizedEnd) {
        budget.addFragment();
        final measure = measures[measureIndex];
        final fragmentStart = quantizedStart > measure.startTick
            ? quantizedStart
            : measure.startTick;
        final fragmentEnd = quantizedEnd < measure.endTick
            ? quantizedEnd
            : measure.endTick;
        final fragmentDuration = fragmentEnd - fragmentStart;
        final decomposition = decomposer.nearest(
          fragmentDuration,
          fragmentEnd - fragmentStart,
        );
        if (decomposition != null) {
          budget.addNotationElements(decomposition.notations.length);
          fragments.add(
            _PendingFragment(
              measureIndex: measureIndex,
              start: fragmentStart - measure.startTick,
              notations: decomposition.notations,
            ),
          );
        } else {
          hasBrokenCrossBarContinuity = true;
        }
        measureIndex++;
      }
      final actualDuration = fragments.fold<int>(
        0,
        (sum, fragment) =>
            sum +
            fragment.notations.fold<int>(
              0,
              (subtotal, notation) => subtotal + notation.ticks,
            ),
      );
      if ((quantizedStart - note.startTick).abs() > ticksPerBeat / 48 ||
          (actualDuration - (note.endTick - note.startTick)).abs() >
              ticksPerBeat / 48) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
      }
      final crossBarTieIds = <int?>[];
      for (var index = 0; index < fragments.length - 1; index++) {
        final current = fragments[index];
        final next = fragments[index + 1];
        final reachesMeasureEnd =
            current.start + current.duration ==
            measures[current.measureIndex].lengthTick;
        final startsAtMeasureStart = next.start == 0;
        final adjacentMeasures = next.measureIndex == current.measureIndex + 1;
        final canTieAcrossBar =
            adjacentMeasures && reachesMeasureEnd && startsAtMeasureStart;
        crossBarTieIds.add(canTieAcrossBar ? nextBarTieId++ : null);
        if (!canTieAcrossBar) hasBrokenCrossBarContinuity = true;
      }
      if (hasBrokenCrossBarContinuity) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
      }
      for (
        var fragmentIndex = 0;
        fragmentIndex < fragments.length;
        fragmentIndex++
      ) {
        final fragment = fragments[fragmentIndex];
        groupedByMeasure[fragment.measureIndex]
            .putIfAbsent(fragment.start, () => [])
            .add(
              _NoteSegment(
                noteNumber: note.noteNumber,
                notations: fragment.notations,
                barTieStopId: fragmentIndex > 0
                    ? crossBarTieIds[fragmentIndex - 1]
                    : null,
                barTieStartId: fragmentIndex < fragments.length - 1
                    ? crossBarTieIds[fragmentIndex]
                    : null,
              ),
            );
      }
    }
    return groupedByMeasure
        .map((grouped) {
          final events = grouped.entries.expand((entry) {
            final segments = List<_NoteSegment>.of(entry.value)
              ..sort((left, right) {
                final duration = right.duration.compareTo(left.duration);
                return duration != 0
                    ? duration
                    : left.noteNumber.compareTo(right.noteNumber);
              });
            final compatibleGroups = <String, List<_NoteSegment>>{};
            for (final segment in segments) {
              final key = segment.notations.length == 1
                  ? 'single'
                  : segment.notations
                        .map((notation) => notation.ticks)
                        .join(',');
              compatibleGroups.putIfAbsent(key, () => []).add(segment);
            }
            return compatibleGroups.values.map((compatibleSegments) {
              final duration = compatibleSegments
                  .map((segment) => segment.duration)
                  .reduce(math.max);
              final averagePitch =
                  compatibleSegments
                      .map((segment) => segment.noteNumber)
                      .reduce((left, right) => left + right) ~/
                  compatibleSegments.length;
              return _ChordEvent(
                start: entry.key,
                duration: duration,
                notes: compatibleSegments,
                staff:
                    part.staffMode == MidiStaffMode.grandStaff &&
                        averagePitch < 60
                    ? 2
                    : 1,
              );
            });
          }).toList();
          events.sort((a, b) {
            final onset = a.start.compareTo(b.start);
            if (onset != 0) return onset;
            return b.averagePitch.compareTo(a.averagePitch);
          });
          return events;
        })
        .toList(growable: false);
  }

  List<List<_ChordEvent>> _colorVoices(
    List<_ChordEvent> events,
    int measureLength,
    int ticksPerBeat,
    Set<MidiNotationWarning> warnings,
  ) {
    final voices = <List<_ChordEvent>>[];
    final ends = <int>[];
    final minimumNotation = _durationCandidates(ticksPerBeat).first;
    final minimumDuration = minimumNotation.ticks;
    for (final event in events) {
      var voiceIndex = -1;
      for (var index = 0; index < ends.length; index++) {
        if (ends[index] <= event.start) {
          voiceIndex = index;
          break;
        }
      }
      var placed = event;
      if (voiceIndex < 0 && voices.length < 4) {
        voiceIndex = voices.length;
        voices.add([]);
        ends.add(0);
      } else if (voiceIndex < 0) {
        warnings.add(MidiNotationWarning.densePassage);
        voiceIndex = 0;
        for (var index = 1; index < ends.length; index++) {
          if (ends[index] < ends[voiceIndex]) voiceIndex = index;
        }
        final shiftedStart = ends[voiceIndex];
        if (shiftedStart + minimumDuration > measureLength) continue;
        placed = event.copyWith(start: shiftedStart, notation: minimumNotation);
      }
      voices[voiceIndex].add(placed);
      ends[voiceIndex] = placed.end;
    }
    if (voices.isEmpty) voices.add([]);
    return voices;
  }

  Set<int> _validBarTieIds(
    List<List<List<_ChordEvent>>> voicesByMeasure,
    List<MeasureInfo> measures,
    Set<MidiNotationWarning> warnings,
  ) {
    final starts = <int, List<_PlacedBarTieEndpoint>>{};
    final stops = <int, List<_PlacedBarTieEndpoint>>{};
    for (
      var measureIndex = 0;
      measureIndex < voicesByMeasure.length;
      measureIndex++
    ) {
      for (final voice in voicesByMeasure[measureIndex]) {
        for (final event in voice) {
          for (final note in event.notes) {
            final startId = note.barTieStartId;
            final stopId = note.barTieStopId;
            if (startId == null && stopId == null) continue;
            final endpoint = _PlacedBarTieEndpoint(
              measureIndex: measureIndex,
              start: event.start,
              duration: note.duration,
              denseAdjusted: note.denseAdjusted,
            );
            if (startId != null) {
              starts.putIfAbsent(startId, () => []).add(endpoint);
            }
            if (stopId != null) {
              stops.putIfAbsent(stopId, () => []).add(endpoint);
            }
          }
        }
      }
    }
    final allIds = <int>{...starts.keys, ...stops.keys};
    final validIds = <int>{};
    for (final id in allIds) {
      final startEndpoints = starts[id] ?? const [];
      final stopEndpoints = stops[id] ?? const [];
      if (startEndpoints.length != 1 || stopEndpoints.length != 1) continue;
      final start = startEndpoints.single;
      final stop = stopEndpoints.single;
      final adjacentMeasures = stop.measureIndex == start.measureIndex + 1;
      final reachesMeasureEnd =
          start.start + start.duration ==
          measures[start.measureIndex].lengthTick;
      final startsAtMeasureStart = stop.start == 0;
      if (!start.denseAdjusted &&
          !stop.denseAdjusted &&
          adjacentMeasures &&
          reachesMeasureEnd &&
          startsAtMeasureStart) {
        validIds.add(id);
      }
    }
    if (validIds.length != allIds.length) {
      warnings
        ..add(MidiNotationWarning.densePassage)
        ..add(MidiNotationWarning.rhythmQuantized);
    }
    return validIds;
  }

  void _writeAttributes(
    StringBuffer buffer,
    int divisions,
    MidiScorePart part,
    MeasureInfo measure,
    bool firstMeasure,
    bool timeChanged,
  ) {
    buffer
      ..writeln('      <attributes>')
      ..writeln('        <divisions>$divisions</divisions>');
    if (timeChanged) {
      buffer
        ..writeln('        <time>')
        ..writeln('          <beats>${measure.numerator}</beats>')
        ..writeln('          <beat-type>${measure.denominator}</beat-type>')
        ..writeln('        </time>');
    }
    if (firstMeasure) {
      switch (part.staffMode) {
        case MidiStaffMode.grandStaff:
          buffer
            ..writeln('        <staves>2</staves>')
            ..writeln('        <clef number="1">')
            ..writeln('          <sign>G</sign><line>2</line>')
            ..writeln('        </clef>')
            ..writeln('        <clef number="2">')
            ..writeln('          <sign>F</sign><line>4</line>')
            ..writeln('        </clef>');
        case MidiStaffMode.percussionStaff:
          buffer
            ..writeln('        <clef>')
            ..writeln('          <sign>percussion</sign><line>2</line>')
            ..writeln('        </clef>');
        case MidiStaffMode.singleStaff:
          final bassClef =
              part.kind == MidiPartKind.bass ||
              (part.kind == MidiPartKind.strings &&
                  _looksLikeLowStrings(part.label));
          buffer
            ..writeln('        <clef>')
            ..writeln(
              bassClef
                  ? '          <sign>F</sign><line>4</line>'
                  : '          <sign>G</sign><line>2</line>',
            )
            ..writeln('        </clef>');
      }
    }
    buffer.writeln('      </attributes>');
  }

  void _writeVoices(
    StringBuffer buffer,
    List<List<_ChordEvent>> voices,
    int measureLength,
    int ticksPerBeat,
    MidiScorePart part,
    Map<int, int> previousStaffByVoice,
    Set<int> validBarTieIds,
  ) {
    for (var voiceIndex = 0; voiceIndex < voices.length; voiceIndex++) {
      if (voiceIndex > 0) {
        buffer.writeln(
          '      <backup><duration>$measureLength</duration></backup>',
        );
      }
      var cursor = 0;
      var previousStaff = previousStaffByVoice[voiceIndex];
      for (final event in voices[voiceIndex]) {
        if (event.start > cursor) {
          _writeRest(
            buffer,
            event.start - cursor,
            voiceIndex + 1,
            previousStaff ?? event.staff,
          );
        }
        var staff = event.staff;
        if (part.staffMode == MidiStaffMode.grandStaff &&
            previousStaff != null &&
            event.averagePitch >= 57 &&
            event.averagePitch <= 64) {
          staff = previousStaff;
        }
        final percussion =
            part.kind == MidiPartKind.percussion ||
            part.staffMode == MidiStaffMode.percussionStaff;
        if (event.notes.every((note) => note.notations.length == 1)) {
          for (var noteIndex = 0; noteIndex < event.notes.length; noteIndex++) {
            final note = event.notes[noteIndex];
            final tieStop =
                note.barTieStopId != null &&
                validBarTieIds.contains(note.barTieStopId);
            final tieStart =
                note.barTieStartId != null &&
                validBarTieIds.contains(note.barTieStartId);
            _writeNote(
              buffer,
              note,
              notation: note.notations.single,
              tieStop: tieStop,
              tieStart: tieStart,
              voice: voiceIndex + 1,
              staff: staff,
              chord: noteIndex > 0,
              percussion: percussion,
              ticksPerBeat: ticksPerBeat,
            );
          }
        } else {
          for (
            var notationIndex = 0;
            notationIndex < event.notes.first.notations.length;
            notationIndex++
          ) {
            for (
              var noteIndex = 0;
              noteIndex < event.notes.length;
              noteIndex++
            ) {
              final note = event.notes[noteIndex];
              final barTieStop =
                  note.barTieStopId != null &&
                  validBarTieIds.contains(note.barTieStopId);
              final barTieStart =
                  note.barTieStartId != null &&
                  validBarTieIds.contains(note.barTieStartId);
              _writeNote(
                buffer,
                note,
                notation: note.notations[notationIndex],
                tieStop: barTieStop || notationIndex > 0,
                tieStart:
                    barTieStart || notationIndex < note.notations.length - 1,
                voice: voiceIndex + 1,
                staff: staff,
                chord: noteIndex > 0,
                percussion: percussion,
                ticksPerBeat: ticksPerBeat,
              );
            }
          }
        }
        cursor = event.end;
        previousStaff = staff;
      }
      if (cursor < measureLength) {
        _writeRest(
          buffer,
          measureLength - cursor,
          voiceIndex + 1,
          previousStaff ?? 1,
        );
      }
      if (previousStaff != null) {
        previousStaffByVoice[voiceIndex] = previousStaff;
      }
    }
  }

  void _writeRest(StringBuffer buffer, int duration, int voice, int staff) {
    buffer
      ..writeln('      <note>')
      ..writeln('        <rest/>')
      ..writeln('        <duration>$duration</duration>')
      ..writeln('        <voice>$voice</voice>')
      ..writeln('        <staff>$staff</staff>')
      ..writeln('      </note>');
  }

  void _writeNote(
    StringBuffer buffer,
    _NoteSegment note, {
    required _DurationCandidate notation,
    required bool tieStop,
    required bool tieStart,
    required int voice,
    required int staff,
    required bool chord,
    required bool percussion,
    required int ticksPerBeat,
  }) {
    final exactNotation = _notationForExactDuration(
      notation.ticks,
      ticksPerBeat,
    );
    buffer.writeln('      <note>');
    if (chord) buffer.writeln('        <chord/>');
    if (percussion) {
      buffer
        ..writeln('        <unpitched>')
        ..writeln('          <display-step>C</display-step>')
        ..writeln('          <display-octave>5</display-octave>')
        ..writeln('        </unpitched>');
    } else {
      final pitch = _pitch(note.noteNumber);
      buffer
        ..writeln('        <pitch>')
        ..writeln('          <step>${pitch.step}</step>');
      if (pitch.alter != 0) {
        buffer.writeln('          <alter>${pitch.alter}</alter>');
      }
      buffer
        ..writeln('          <octave>${pitch.octave}</octave>')
        ..writeln('        </pitch>');
    }
    buffer.writeln('        <duration>${notation.ticks}</duration>');
    if (tieStop) buffer.writeln('        <tie type="stop"/>');
    if (tieStart) buffer.writeln('        <tie type="start"/>');
    buffer
      ..writeln('        <voice>$voice</voice>')
      ..writeln('        <type>${exactNotation.type}</type>');
    for (var index = 0; index < exactNotation.dots; index++) {
      buffer.writeln('        <dot/>');
    }
    if (exactNotation.triplet) {
      buffer
        ..writeln('        <time-modification>')
        ..writeln('          <actual-notes>3</actual-notes>')
        ..writeln('          <normal-notes>2</normal-notes>')
        ..writeln('        </time-modification>');
    }
    buffer.writeln('        <staff>$staff</staff>');
    if (tieStop || tieStart) {
      buffer.writeln('        <notations>');
      if (tieStop) buffer.writeln('          <tied type="stop"/>');
      if (tieStart) buffer.writeln('          <tied type="start"/>');
      buffer.writeln('        </notations>');
    }
    buffer.writeln('      </note>');
  }

  void _writeTempoDirections(
    StringBuffer buffer,
    MidiSongData song,
    MeasureInfo measure,
  ) {
    final byTick = <int, double>{
      for (final change in song.tempoChanges)
        if (change.tick >= measure.startTick && change.tick < measure.endTick)
          change.tick: change.bpm,
    };
    if (measure.startTick == 0 && !byTick.containsKey(0)) byTick[0] = 120;
    final ticks = byTick.keys.toList()..sort();
    for (final tick in ticks) {
      buffer.writeln('      <direction placement="above">');
      final offset = tick - measure.startTick;
      if (offset > 0) buffer.writeln('        <offset>$offset</offset>');
      buffer
        ..writeln('        <sound tempo="${_number(byTick[tick]!)}"/>')
        ..writeln('      </direction>');
    }
  }
}

class _NoteSegment {
  final int noteNumber;
  final List<_DurationCandidate> notations;
  final int? barTieStopId;
  final int? barTieStartId;
  final bool denseAdjusted;

  const _NoteSegment({
    required this.noteNumber,
    required this.notations,
    required this.barTieStopId,
    required this.barTieStartId,
    this.denseAdjusted = false,
  });

  int get duration =>
      notations.fold<int>(0, (total, notation) => total + notation.ticks);

  _NoteSegment withSingleNotation(_DurationCandidate notation) => _NoteSegment(
    noteNumber: noteNumber,
    notations: [notation],
    barTieStopId: barTieStopId,
    barTieStartId: barTieStartId,
    denseAdjusted: true,
  );
}

class _PlacedBarTieEndpoint {
  final int measureIndex;
  final int start;
  final int duration;
  final bool denseAdjusted;

  const _PlacedBarTieEndpoint({
    required this.measureIndex,
    required this.start,
    required this.duration,
    required this.denseAdjusted,
  });
}

class _PendingFragment {
  final int measureIndex;
  final int start;
  final List<_DurationCandidate> notations;

  const _PendingFragment({
    required this.measureIndex,
    required this.start,
    required this.notations,
  });

  int get duration =>
      notations.fold<int>(0, (total, notation) => total + notation.ticks);
}

class _DurationDecomposition {
  final List<_DurationCandidate> notations;

  const _DurationDecomposition(this.notations);

  int get duration =>
      notations.fold<int>(0, (total, notation) => total + notation.ticks);
}

class _ConversionBudget {
  final int maxFragments;
  final int maxNotationElements;
  final int maxDynamicStates;
  int _fragments = 0;
  int _notationElements = 0;
  int _dynamicStates = 0;

  _ConversionBudget({
    required this.maxFragments,
    required this.maxNotationElements,
    required this.maxDynamicStates,
  });

  void addFragment() {
    _fragments++;
    if (_fragments > maxFragments) {
      throw StateError('MIDI 切分片段超过 $maxFragments 个，无法生成谱面');
    }
  }

  void addNotationElements(int count) {
    _notationElements += count;
    if (_notationElements > maxNotationElements) {
      throw StateError('MusicXML 记谱元素超过 $maxNotationElements 个，无法生成谱面');
    }
  }

  void reserveDynamicStates(int count) {
    _dynamicStates += count;
    if (_dynamicStates > maxDynamicStates) {
      throw StateError('时值分解累计状态超过 $maxDynamicStates 个，无法生成谱面');
    }
  }
}

class _ChordEvent {
  final int start;
  final int duration;
  final List<_NoteSegment> notes;
  final int staff;

  const _ChordEvent({
    required this.start,
    required this.duration,
    required this.notes,
    required this.staff,
  });

  int get end => start + duration;

  int get averagePitch =>
      notes.map((note) => note.noteNumber).reduce((a, b) => a + b) ~/
      notes.length;

  _ChordEvent copyWith({
    required int start,
    required _DurationCandidate notation,
  }) => _ChordEvent(
    start: start,
    duration: notation.ticks,
    notes: notes
        .map((note) => note.withSingleNotation(notation))
        .toList(growable: false),
    staff: staff,
  );
}

class _DurationCandidate {
  final int ticks;
  final String type;
  final int dots;
  final bool triplet;
  final int complexity;

  const _DurationCandidate({
    required this.ticks,
    required this.type,
    required this.dots,
    required this.triplet,
    required this.complexity,
  });
}

class _DurationDecomposer {
  static const int _maxDecompositionElements = 2000000;
  final List<_DurationCandidate> _candidates;
  final _ConversionBudget _budget;
  final Map<int, List<_DurationCandidate>?> _exactCache = {};

  _DurationDecomposer(List<_DurationCandidate> candidates, this._budget)
    : _candidates = _deduplicateCandidates(candidates);

  _DurationDecomposition? nearest(int duration, int maximum) {
    if (duration <= 0 || maximum <= 0) return null;
    final target = math.min(duration, maximum);
    final upper = math.min(maximum, target + _candidates.first.ticks);
    for (var error = 0; error <= _candidates.first.ticks; error++) {
      final matches = <List<_DurationCandidate>>[];
      final shorter = target - error;
      if (shorter > 0 && shorter <= maximum) {
        final exact = _decomposeExact(shorter);
        if (exact != null) matches.add(exact);
      }
      final longer = target + error;
      if (error > 0 && longer <= upper) {
        final exact = _decomposeExact(longer);
        if (exact != null) matches.add(exact);
      }
      if (matches.isNotEmpty) {
        matches.sort(_compareDecompositions);
        return _DurationDecomposition(matches.first);
      }
    }
    return null;
  }

  List<_DurationCandidate>? _decomposeExact(int duration) {
    if (_exactCache.containsKey(duration)) return _exactCache[duration];
    final gcd = _candidates
        .map((candidate) => candidate.ticks)
        .reduce(_greatestCommonDivisor);
    if (duration % gcd != 0) {
      _exactCache[duration] = null;
      return null;
    }
    final scaledCandidates = _candidates
        .map((candidate) => candidate.ticks ~/ gcd)
        .toList(growable: false);
    final scaledDuration = duration ~/ gcd;
    final largest = scaledCandidates.last;
    var prefixCount = scaledDuration > _budget.maxDynamicStates
        ? (scaledDuration - _budget.maxDynamicStates + largest - 1) ~/ largest
        : 0;
    List<_DurationCandidate>? suffix;
    for (var attempt = 0; attempt <= 32 && prefixCount >= 0; attempt++) {
      final remainder = scaledDuration - prefixCount * largest;
      if (remainder > _budget.maxDynamicStates) break;
      suffix = _solveRemainder(remainder, scaledCandidates);
      if (suffix != null) break;
      prefixCount--;
    }
    if (suffix == null) {
      if (scaledDuration <= _budget.maxDynamicStates) {
        _exactCache[duration] = null;
        return null;
      }
      throw StateError('单次时值分解工作量超过 ${_budget.maxDynamicStates} 个状态');
    }
    if (prefixCount + suffix.length > _maxDecompositionElements) {
      throw StateError('单个时值的记谱元素超过 $_maxDecompositionElements 个');
    }
    final result = <_DurationCandidate>[
      ...List<_DurationCandidate>.filled(
        prefixCount,
        _candidates.last,
        growable: false,
      ),
      ...suffix,
    ];
    _exactCache[duration] = result;
    return result;
  }

  List<_DurationCandidate>? _solveRemainder(
    int target,
    List<int> scaledCandidates,
  ) {
    if (target == 0) return const [];
    _budget.reserveDynamicStates(target + 1);
    final bestCounts = List<int?>.filled(target + 1, null);
    final bestComplexities = List<int?>.filled(target + 1, null);
    final previousCandidate = List<int?>.filled(target + 1, null);
    bestCounts[0] = 0;
    bestComplexities[0] = 0;
    for (var amount = 1; amount <= target; amount++) {
      for (var index = 0; index < scaledCandidates.length; index++) {
        final previous = amount - scaledCandidates[index];
        if (previous < 0 || bestCounts[previous] == null) continue;
        final count = bestCounts[previous]! + 1;
        final complexity =
            bestComplexities[previous]! + _candidates[index].complexity;
        if (bestCounts[amount] == null ||
            count < bestCounts[amount]! ||
            (count == bestCounts[amount] &&
                complexity < bestComplexities[amount]!)) {
          bestCounts[amount] = count;
          bestComplexities[amount] = complexity;
          previousCandidate[amount] = index;
        }
      }
    }
    if (bestCounts[target] == null) return null;
    final result = <_DurationCandidate>[];
    var amount = target;
    while (amount > 0) {
      final candidateIndex = previousCandidate[amount]!;
      result.add(_candidates[candidateIndex]);
      amount -= scaledCandidates[candidateIndex];
    }
    result.sort((left, right) => right.ticks.compareTo(left.ticks));
    return result;
  }
}

int _compareDecompositions(
  List<_DurationCandidate> left,
  List<_DurationCandidate> right,
) {
  final elementCount = left.length.compareTo(right.length);
  if (elementCount != 0) return elementCount;
  final leftComplexity = left.fold<int>(
    0,
    (total, candidate) => total + candidate.complexity,
  );
  final rightComplexity = right.fold<int>(
    0,
    (total, candidate) => total + candidate.complexity,
  );
  final complexity = leftComplexity.compareTo(rightComplexity);
  if (complexity != 0) return complexity;
  for (var index = 0; index < left.length; index++) {
    final ticks = right[index].ticks.compareTo(left[index].ticks);
    if (ticks != 0) return ticks;
    final type = left[index].type.compareTo(right[index].type);
    if (type != 0) return type;
    final dots = left[index].dots.compareTo(right[index].dots);
    if (dots != 0) return dots;
    final triplet = (left[index].triplet ? 1 : 0).compareTo(
      right[index].triplet ? 1 : 0,
    );
    if (triplet != 0) return triplet;
  }
  return 0;
}

List<_DurationCandidate> _durationCandidates(int ticksPerBeat) {
  const definitions = <(String, int, int)>[
    ('whole', 4, 1),
    ('half', 2, 1),
    ('quarter', 1, 1),
    ('eighth', 1, 2),
    ('16th', 1, 4),
    ('32nd', 1, 8),
  ];
  final result = <_DurationCandidate>[];
  for (var typeIndex = 0; typeIndex < definitions.length; typeIndex++) {
    final definition = definitions[typeIndex];
    final base = ticksPerBeat * definition.$2 / definition.$3;
    for (var dots = 0; dots <= 2; dots++) {
      final factor = switch (dots) {
        0 => 1.0,
        1 => 1.5,
        _ => 1.75,
      };
      result.add(
        _DurationCandidate(
          ticks: math.max(1, (base * factor).round()),
          type: definition.$1,
          dots: dots,
          triplet: false,
          complexity: dots * 10 + typeIndex,
        ),
      );
    }
    result.add(
      _DurationCandidate(
        ticks: math.max(1, (base * 2 / 3).round()),
        type: definition.$1,
        dots: 0,
        triplet: true,
        complexity: 30 + typeIndex,
      ),
    );
  }
  result.sort((a, b) {
    final duration = a.ticks.compareTo(b.ticks);
    return duration != 0 ? duration : a.complexity.compareTo(b.complexity);
  });
  return result;
}

int _quantizeOnset(
  int offset,
  int measureLength,
  List<_DurationCandidate> candidates,
) {
  var best = 0;
  var bestError = offset.abs();
  var bestComplexity = 1 << 30;
  for (final candidate in candidates) {
    final multiple = (offset / candidate.ticks).round();
    final quantized = (multiple * candidate.ticks).clamp(0, measureLength);
    final error = (quantized - offset).abs();
    if (error < bestError ||
        (error == bestError && candidate.complexity < bestComplexity)) {
      best = quantized;
      bestError = error;
      bestComplexity = candidate.complexity;
    }
  }
  return best;
}

_DurationCandidate _notationForExactDuration(int duration, int ticksPerBeat) {
  final candidates = _durationCandidates(ticksPerBeat);
  for (final candidate in candidates) {
    if (candidate.ticks == duration) return candidate;
  }
  throw StateError('时值 $duration 没有一致的 MusicXML type');
}

List<_DurationCandidate> _deduplicateCandidates(
  List<_DurationCandidate> candidates,
) {
  final byTicks = <int, _DurationCandidate>{};
  for (final candidate in candidates) {
    final current = byTicks[candidate.ticks];
    if (current == null || candidate.complexity < current.complexity) {
      byTicks[candidate.ticks] = candidate;
    }
  }
  final result = byTicks.values.toList()
    ..sort((left, right) => left.ticks.compareTo(right.ticks));
  return result;
}

int _greatestCommonDivisor(int left, int right) {
  var a = left.abs();
  var b = right.abs();
  while (b != 0) {
    final remainder = a % b;
    a = b;
    b = remainder;
  }
  return a;
}

int _estimatedMeasureCount(MidiSongData song, {required int stopAfter}) {
  final totalTicks = song.totalTicks <= 0
      ? song.ticksPerBeat * 4
      : song.totalTicks;
  final changes = List<TimeSignatureChange>.from(song.timeSignatureChanges)
    ..sort((left, right) => left.tick.compareTo(right.tick));
  var numerator = 4;
  var denominator = 4;
  var currentTick = 0;
  var count = 0;
  var index = 0;
  while (index < changes.length && changes[index].tick <= 0) {
    numerator = changes[index].numerator;
    denominator = changes[index].denominator;
    index++;
  }
  while (currentTick < totalTicks) {
    final nextChangeTick = index < changes.length
        ? changes[index].tick.clamp(currentTick, totalTicks)
        : totalTicks;
    final segmentLength = nextChangeTick - currentTick;
    if (segmentLength > 0) {
      final safeNumerator = numerator <= 0 ? 4 : numerator;
      final safeDenominator = denominator <= 0 ? 4 : denominator;
      final measureLength =
          (song.ticksPerBeat * safeNumerator * 4 / safeDenominator)
              .round()
              .clamp(1, 1 << 30);
      count += (segmentLength + measureLength - 1) ~/ measureLength;
      if (count > stopAfter) return count;
      currentTick = nextChangeTick;
    }
    while (index < changes.length && changes[index].tick <= currentTick) {
      numerator = changes[index].numerator;
      denominator = changes[index].denominator;
      index++;
    }
  }
  return math.max(1, count);
}

({String step, int alter, int octave}) _pitch(int noteNumber) {
  const pitches = <(String, int)>[
    ('C', 0),
    ('C', 1),
    ('D', 0),
    ('D', 1),
    ('E', 0),
    ('F', 0),
    ('F', 1),
    ('G', 0),
    ('G', 1),
    ('A', 0),
    ('A', 1),
    ('B', 0),
  ];
  final pitch = pitches[noteNumber % 12];
  return (step: pitch.$1, alter: pitch.$2, octave: noteNumber ~/ 12 - 1);
}

bool _looksLikeLowStrings(String label) {
  final normalized = label.toLowerCase();
  return normalized.contains('bass') ||
      normalized.contains('cello') ||
      normalized.contains('低音') ||
      normalized.contains('大提琴');
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _number(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(3);
