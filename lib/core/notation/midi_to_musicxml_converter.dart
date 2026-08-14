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
    if (!selectedParts.any((part) => _selectedNotes(song, part).isNotEmpty)) {
      throw StateError('所选声部中没有可记谱音符');
    }
    final tempoMap = TempoMap(
      ticksPerBeat: song.ticksPerBeat,
      tempoChanges: song.tempoChanges,
    );
    final sourceMeasures = MeasureMap(song: song, tempoMap: tempoMap).measures;
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
    final xml = _buildDocument(song, selectedParts, sourceMeasures, warnings);
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
    List<MeasureInfo> measures,
    Set<MidiNotationWarning> warnings,
  ) {
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
        'P${index + 1}',
        measures,
        warnings,
      );
    }
    buffer.writeln('</score-partwise>');
    return buffer.toString();
  }

  void _writePart(
    StringBuffer buffer,
    MidiSongData song,
    MidiScorePart part,
    String partId,
    List<MeasureInfo> measures,
    Set<MidiNotationWarning> warnings,
  ) {
    final notes = _selectedNotes(song, part);
    final previousStaffByVoice = <int, int>{};
    buffer.writeln('  <part id="$partId">');
    for (var measureIndex = 0; measureIndex < measures.length; measureIndex++) {
      final measure = measures[measureIndex];
      final events = _eventsForMeasure(
        notes,
        measure,
        song.ticksPerBeat,
        part,
        warnings,
      );
      final voices = _colorVoices(
        events,
        measure.lengthTick,
        song.ticksPerBeat,
        warnings,
      );
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
      );
      buffer.writeln('    </measure>');
    }
    buffer.writeln('  </part>');
  }

  List<MidiNote> _selectedNotes(MidiSongData song, MidiScorePart part) {
    final notes = <MidiNote>[];
    for (final source in part.sources) {
      for (final track in song.tracks) {
        if (track.index != source.trackIndex) continue;
        notes.addAll(
          track.notes.where((note) => source.channels.contains(note.channel)),
        );
      }
    }
    notes.sort((a, b) {
      final onset = a.startTick.compareTo(b.startTick);
      return onset != 0 ? onset : a.noteNumber.compareTo(b.noteNumber);
    });
    return notes;
  }

  List<_ChordEvent> _eventsForMeasure(
    List<MidiNote> notes,
    MeasureInfo measure,
    int ticksPerBeat,
    MidiScorePart part,
    Set<MidiNotationWarning> warnings,
  ) {
    final candidates = _durationCandidates(ticksPerBeat);
    final grouped = <int, List<_NoteSegment>>{};
    for (final note in notes) {
      if (note.endTick <= measure.startTick ||
          note.startTick >= measure.endTick ||
          note.endTick <= note.startTick) {
        continue;
      }
      final rawStart = math.max(note.startTick, measure.startTick);
      final rawEnd = math.min(note.endTick, measure.endTick);
      final offset = rawStart - measure.startTick;
      var quantizedOffset = note.startTick < measure.startTick
          ? 0
          : _quantizeOnset(offset, measure.lengthTick, candidates);
      final minimumDuration = candidates
          .map((candidate) => candidate.ticks)
          .reduce(math.min);
      if (measure.lengthTick - quantizedOffset < minimumDuration) {
        quantizedOffset = math.max(0, measure.lengthTick - minimumDuration);
      }
      final available = measure.lengthTick - quantizedOffset;
      if (available < minimumDuration) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
        continue;
      }
      final rawDuration = rawEnd - rawStart;
      final duration = note.endTick > measure.endTick
          ? available
          : _nearestDuration(rawDuration, available, candidates).ticks;
      if ((quantizedOffset - offset).abs() > ticksPerBeat / 48 ||
          (duration - rawDuration).abs() > ticksPerBeat / 48) {
        warnings.add(MidiNotationWarning.rhythmQuantized);
      }
      grouped
          .putIfAbsent(quantizedOffset, () => [])
          .add(
            _NoteSegment(
              noteNumber: note.noteNumber,
              duration: duration.clamp(1, available),
              tieStop: note.startTick < measure.startTick,
              tieStart: note.endTick > measure.endTick,
            ),
          );
    }
    final events = grouped.entries.map((entry) {
      final segments = List<_NoteSegment>.of(entry.value)
        ..sort((left, right) {
          final duration = right.duration.compareTo(left.duration);
          return duration != 0
              ? duration
              : left.noteNumber.compareTo(right.noteNumber);
        });
      final duration = segments
          .map((segment) => segment.duration)
          .reduce(math.max);
      final averagePitch =
          segments
              .map((segment) => segment.noteNumber)
              .reduce((left, right) => left + right) ~/
          segments.length;
      return _ChordEvent(
        start: entry.key,
        duration: duration,
        notes: segments,
        staff: part.staffMode == MidiStaffMode.grandStaff && averagePitch < 60
            ? 2
            : 1,
      );
    }).toList();
    events.sort((a, b) {
      final onset = a.start.compareTo(b.start);
      if (onset != 0) return onset;
      return b.averagePitch.compareTo(a.averagePitch);
    });
    return events;
  }

  List<List<_ChordEvent>> _colorVoices(
    List<_ChordEvent> events,
    int measureLength,
    int ticksPerBeat,
    Set<MidiNotationWarning> warnings,
  ) {
    final voices = <List<_ChordEvent>>[];
    final ends = <int>[];
    final minimumDuration = _durationCandidates(
      ticksPerBeat,
    ).map((candidate) => candidate.ticks).reduce(math.min);
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
        placed = event.copyWith(
          start: shiftedStart,
          duration: math.min(minimumDuration, measureLength - shiftedStart),
        );
      }
      voices[voiceIndex].add(placed);
      ends[voiceIndex] = placed.end;
    }
    if (voices.isEmpty) voices.add([]);
    return voices;
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
        for (var noteIndex = 0; noteIndex < event.notes.length; noteIndex++) {
          final noteDuration = noteIndex == 0
              ? event.duration
              : math.min(event.duration, event.notes[noteIndex].duration);
          _writeNote(
            buffer,
            event.notes[noteIndex],
            duration: noteDuration,
            voice: voiceIndex + 1,
            staff: staff,
            chord: noteIndex > 0,
            percussion:
                part.kind == MidiPartKind.percussion ||
                part.staffMode == MidiStaffMode.percussionStaff,
            ticksPerBeat: ticksPerBeat,
          );
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
    required int duration,
    required int voice,
    required int staff,
    required bool chord,
    required bool percussion,
    required int ticksPerBeat,
  }) {
    final notation = _notationForDuration(duration, ticksPerBeat);
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
    buffer.writeln('        <duration>$duration</duration>');
    if (note.tieStop) buffer.writeln('        <tie type="stop"/>');
    if (note.tieStart) buffer.writeln('        <tie type="start"/>');
    buffer
      ..writeln('        <voice>$voice</voice>')
      ..writeln('        <type>${notation.type}</type>');
    for (var index = 0; index < notation.dots; index++) {
      buffer.writeln('        <dot/>');
    }
    if (notation.triplet) {
      buffer
        ..writeln('        <time-modification>')
        ..writeln('          <actual-notes>3</actual-notes>')
        ..writeln('          <normal-notes>2</normal-notes>')
        ..writeln('        </time-modification>');
    }
    buffer.writeln('        <staff>$staff</staff>');
    if (note.tieStop || note.tieStart) {
      buffer.writeln('        <notations>');
      if (note.tieStop) buffer.writeln('          <tied type="stop"/>');
      if (note.tieStart) buffer.writeln('          <tied type="start"/>');
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
  final int duration;
  final bool tieStop;
  final bool tieStart;

  const _NoteSegment({
    required this.noteNumber,
    required this.duration,
    required this.tieStop,
    required this.tieStart,
  });
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

  _ChordEvent copyWith({required int start, required int duration}) =>
      _ChordEvent(start: start, duration: duration, notes: notes, staff: staff);
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

_DurationCandidate _nearestDuration(
  int duration,
  int maximum,
  List<_DurationCandidate> candidates,
) {
  final allowed = candidates.where((candidate) => candidate.ticks <= maximum);
  var best = allowed.first;
  var bestError = (best.ticks - duration).abs();
  for (final candidate in allowed.skip(1)) {
    final error = (candidate.ticks - duration).abs();
    if (error < bestError ||
        (error == bestError && candidate.complexity < best.complexity)) {
      best = candidate;
      bestError = error;
    }
  }
  return best;
}

_DurationCandidate _notationForDuration(int duration, int ticksPerBeat) {
  final candidates = _durationCandidates(ticksPerBeat);
  var best = candidates.first;
  var bestError = (best.ticks - duration).abs();
  for (final candidate in candidates.skip(1)) {
    final error = (candidate.ticks - duration).abs();
    if (error < bestError ||
        (error == bestError && candidate.complexity < best.complexity)) {
      best = candidate;
      bestError = error;
    }
  }
  return best;
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
