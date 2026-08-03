import 'dart:io';
import 'dart:math' as math;

import '../../models/midi_track.dart';
import '../midi/tempo_map.dart';

/// 将 MusicXML 的谱面结构转换为播放器可用的 MIDI 时间线数据。
///
/// 当前实现覆盖 MVP 所需的 partwise MusicXML：音高、休止、和弦、
/// divisions、拍号和 direction/sound tempo。复杂记谱语义会被折叠为
/// MIDI 播放事件。
class MusicXmlParser {
  static const int ticksPerBeat = 480;

  Future<MidiSongData> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('MusicXML file not found', filePath);
    }
    final xml = await file.readAsString();
    return parseString(xml, fileName: file.uri.pathSegments.last);
  }

  MidiSongData parseString(String xml, {String fileName = 'score.musicxml'}) {
    final normalizedXml = _stripComments(xml);
    final partNames = _parsePartNames(normalizedXml);
    final parts = _parseParts(normalizedXml);
    if (parts.isEmpty) {
      throw const FormatException('MusicXML 中没有可解析的 part');
    }

    final tempoChanges = <TempoChange>[
      TempoChange(tick: 0, microsecondsPerBeat: 500000),
    ];
    final timeSignatureChanges = <TimeSignatureChange>[
      TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
    ];
    final tracks = <MidiTrackInfo>[];
    var maxTick = 0;

    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      final parsedPart = _parsePart(
        parts[partIndex],
        trackIndex: partIndex,
        trackName: partNames[parts[partIndex].id] ?? parts[partIndex].id,
        tempoChanges: tempoChanges,
        timeSignatureChanges: timeSignatureChanges,
      );
      tracks.add(parsedPart.track);
      maxTick = math.max(maxTick, parsedPart.maxTick);
    }

    _dedupeTempoChanges(tempoChanges);
    _dedupeTimeSignatures(timeSignatureChanges);
    final tempoMap = TempoMap(
      ticksPerBeat: ticksPerBeat,
      tempoChanges: tempoChanges,
    );

    final timeline = <TimelineEvent>[];
    for (final track in tracks) {
      tempoMap.applyTimesToNotes(track.notes);
      tempoMap.applyTimesToEvents(track.events);
      timeline.addAll(track.events);
    }
    timeline.addAll(_globalTimelineEvents(tempoChanges, timeSignatureChanges));
    tempoMap.applyTimesToEvents(timeline);
    timeline.sort();

    for (final signature in timeSignatureChanges) {
      signature.time = tempoMap.tickToSeconds(signature.tick);
    }

    return MidiSongData(
      fileName: fileName,
      format: 1,
      ticksPerBeat: ticksPerBeat,
      tracks: tracks,
      timeline: timeline,
      tempoChanges: tempoChanges,
      timeSignatureChanges: timeSignatureChanges,
      totalTicks: maxTick,
      totalDuration: tempoMap.tickToSeconds(maxTick),
    );
  }

  _ParsedPart _parsePart(
    _MusicXmlPart part, {
    required int trackIndex,
    required String trackName,
    required List<TempoChange> tempoChanges,
    required List<TimeSignatureChange> timeSignatureChanges,
  }) {
    final channel = _channelForTrack(trackIndex);
    final notes = <MidiNote>[];
    final events = <TimelineEvent>[
      TimelineEvent(
        type: MidiEventType.programChange,
        tick: 0,
        channel: channel,
        trackIndex: trackIndex,
        data1: 0,
      ),
    ];
    var divisions = 1;
    var currentTick = 0;
    var previousNoteStartTick = 0;
    var maxTick = 0;

    for (final measureXml in _elements(part.body, 'measure')) {
      final attributesXml = _firstElement(measureXml, 'attributes');
      if (attributesXml != null) {
        final parsedDivisions = _firstInt(attributesXml, 'divisions');
        if (parsedDivisions != null && parsedDivisions > 0) {
          divisions = parsedDivisions;
        }
        final timeXml = _firstElement(attributesXml, 'time');
        if (timeXml != null) {
          final beats = _firstInt(timeXml, 'beats');
          final beatType = _firstInt(timeXml, 'beat-type');
          if (beats != null && beatType != null) {
            timeSignatureChanges.add(
              TimeSignatureChange(
                tick: currentTick,
                numerator: beats,
                denominator: beatType,
              ),
            );
          }
        }
      }

      for (final directionXml in _elements(measureXml, 'direction')) {
        final tempo = _parseSoundTempo(directionXml);
        if (tempo != null && tempo > 0) {
          tempoChanges.add(
            TempoChange(
              tick: currentTick,
              microsecondsPerBeat: (60000000 / tempo).round(),
            ),
          );
        }
      }

      for (final token in _measurePlaybackTokens(measureXml)) {
        switch (token.name) {
          case 'note':
            final parsedNote = _parseNoteToken(
              token.body,
              divisions: divisions,
              currentTick: currentTick,
              previousNoteStartTick: previousNoteStartTick,
              channel: channel,
            );
            if (parsedNote.note != null) {
              final note = parsedNote.note!;
              notes.add(note);
              maxTick = math.max(maxTick, note.endTick);
              events
                ..add(
                  TimelineEvent(
                    type: MidiEventType.noteOn,
                    tick: note.startTick,
                    channel: channel,
                    trackIndex: trackIndex,
                    data1: note.noteNumber,
                    data2: note.velocity,
                  ),
                )
                ..add(
                  TimelineEvent(
                    type: MidiEventType.noteOff,
                    tick: note.endTick,
                    channel: channel,
                    trackIndex: trackIndex,
                    data1: note.noteNumber,
                  ),
                );
              previousNoteStartTick = note.startTick;
            }
            if (parsedNote.advanceTick > 0) {
              currentTick += parsedNote.advanceTick;
              maxTick = math.max(maxTick, currentTick);
            }
            break;
          case 'backup':
            currentTick = math.max(
              0,
              currentTick -
                  _durationToTicks(
                    _firstInt(token.body, 'duration') ?? 0,
                    divisions,
                  ),
            );
            break;
          case 'forward':
            currentTick += _durationToTicks(
              _firstInt(token.body, 'duration') ?? 0,
              divisions,
            );
            maxTick = math.max(maxTick, currentTick);
            break;
        }
      }
      maxTick = math.max(maxTick, currentTick);
    }

    notes.sort((a, b) => a.startTick.compareTo(b.startTick));
    events
      ..add(
        TimelineEvent(
          type: MidiEventType.endOfTrack,
          tick: maxTick,
          trackIndex: trackIndex,
        ),
      )
      ..sort();

    return _ParsedPart(
      track: MidiTrackInfo(
        index: trackIndex,
        name: _decodeXml(trackName),
        channels: {channel},
        programByChannel: {channel: 0},
        notes: notes,
        events: events,
      ),
      maxTick: maxTick,
    );
  }

  _ParsedNote _parseNoteToken(
    String noteXml, {
    required int divisions,
    required int currentTick,
    required int previousNoteStartTick,
    required int channel,
  }) {
    final duration = _firstInt(noteXml, 'duration') ?? 0;
    final durationTicks = _durationToTicks(duration, divisions);
    final isChord = _hasElement(noteXml, 'chord');
    final startTick = isChord ? previousNoteStartTick : currentTick;
    final advanceTick = isChord ? 0 : durationTicks;

    if (_hasElement(noteXml, 'rest')) {
      return _ParsedNote(note: null, advanceTick: advanceTick);
    }

    final pitchXml = _firstElement(noteXml, 'pitch');
    if (pitchXml == null || durationTicks <= 0) {
      return _ParsedNote(note: null, advanceTick: advanceTick);
    }

    final step = _firstText(pitchXml, 'step');
    final octave = _firstInt(pitchXml, 'octave');
    final alter = _firstInt(pitchXml, 'alter') ?? 0;
    if (step == null || octave == null) {
      return _ParsedNote(note: null, advanceTick: advanceTick);
    }

    final noteNumber = _musicXmlPitchToMidi(step, alter, octave);
    final velocity = _parseVelocity(noteXml);
    return _ParsedNote(
      note: MidiNote(
        noteNumber: _clampInt(noteNumber, 0, 127),
        velocity: velocity,
        channel: channel,
        startTick: startTick,
        endTick: startTick + durationTicks,
      ),
      advanceTick: advanceTick,
    );
  }

  List<TimelineEvent> _globalTimelineEvents(
    List<TempoChange> tempoChanges,
    List<TimeSignatureChange> timeSignatureChanges,
  ) {
    return [
      for (final tempo in tempoChanges)
        TimelineEvent(
          type: MidiEventType.tempo,
          tick: tempo.tick,
          data1: tempo.microsecondsPerBeat,
        ),
      for (final signature in timeSignatureChanges)
        TimelineEvent(
          type: MidiEventType.timeSignature,
          tick: signature.tick,
          data1: signature.numerator,
          data2: signature.denominator,
        ),
    ];
  }

  List<_MusicXmlPart> _parseParts(String xml) {
    final parts = <_MusicXmlPart>[];
    final partPattern = RegExp(
      r'<part(\s[^>]*)?>([\s\S]*?)</part>',
      caseSensitive: false,
    );
    for (final match in partPattern.allMatches(xml)) {
      final attributes = match.group(1) ?? '';
      final id = _attribute(attributes, 'id') ?? 'part-${parts.length + 1}';
      parts.add(_MusicXmlPart(id: id, body: match.group(2) ?? ''));
    }
    return parts;
  }

  Map<String, String> _parsePartNames(String xml) {
    final names = <String, String>{};
    final scorePartPattern = RegExp(
      r'<score-part\b([^>]*)>([\s\S]*?)</score-part>',
      caseSensitive: false,
    );
    for (final match in scorePartPattern.allMatches(xml)) {
      final id = _attribute(match.group(1) ?? '', 'id');
      final name = _firstText(match.group(2) ?? '', 'part-name');
      if (id != null && name != null) {
        names[id] = name;
      }
    }
    return names;
  }

  List<_MusicXmlToken> _measurePlaybackTokens(String measureXml) {
    final tokens = <_MusicXmlToken>[];
    final pattern = RegExp(
      r'<(note|backup|forward)\b[^>]*>([\s\S]*?)</\1>',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(measureXml)) {
      tokens.add(
        _MusicXmlToken(match.group(1)!.toLowerCase(), match.group(2) ?? ''),
      );
    }
    return tokens;
  }

  Iterable<String> _elements(String xml, String name) {
    final pattern = RegExp(
      '<$name\\b[^>]*>([\\s\\S]*?)</$name>',
      caseSensitive: false,
    );
    return pattern.allMatches(xml).map((match) => match.group(1) ?? '');
  }

  String? _firstElement(String xml, String name) {
    final pattern = RegExp(
      '<$name\\b[^>]*>([\\s\\S]*?)</$name>',
      caseSensitive: false,
    );
    return pattern.firstMatch(xml)?.group(1);
  }

  String? _firstText(String xml, String name) {
    final text = _firstElement(xml, name)?.trim();
    if (text == null || text.isEmpty) return null;
    return _decodeXml(text);
  }

  int? _firstInt(String xml, String name) {
    return int.tryParse(_firstText(xml, name) ?? '');
  }

  bool _hasElement(String xml, String name) {
    return RegExp('<$name\\b', caseSensitive: false).hasMatch(xml);
  }

  String? _attribute(String attributes, String name) {
    final pattern = RegExp(
      '$name\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
      caseSensitive: false,
    );
    return pattern.firstMatch(attributes)?.group(1);
  }

  double? _parseSoundTempo(String xml) {
    final soundPattern = RegExp(r'<sound\b([^>]*)/?>', caseSensitive: false);
    final soundMatch = soundPattern.firstMatch(xml);
    if (soundMatch == null) return null;
    return double.tryParse(
      _attribute(soundMatch.group(1) ?? '', 'tempo') ?? '',
    );
  }

  int _parseVelocity(String noteXml) {
    final dynamics = _firstInt(noteXml, 'velocity');
    if (dynamics != null) return _clampInt(dynamics, 1, 127);
    return 80;
  }

  int _channelForTrack(int trackIndex) {
    return _clampInt(trackIndex, 0, 15);
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  int _durationToTicks(int duration, int divisions) {
    if (duration <= 0 || divisions <= 0) return 0;
    return (duration * ticksPerBeat / divisions).round();
  }

  int _musicXmlPitchToMidi(String step, int alter, int octave) {
    const semitoneByStep = {
      'C': 0,
      'D': 2,
      'E': 4,
      'F': 5,
      'G': 7,
      'A': 9,
      'B': 11,
    };
    final semitone = semitoneByStep[step.toUpperCase()];
    if (semitone == null) {
      throw FormatException('不支持的 MusicXML 音名: $step');
    }
    return (octave + 1) * 12 + semitone + alter;
  }

  void _dedupeTempoChanges(List<TempoChange> changes) {
    changes.sort((a, b) => a.tick.compareTo(b.tick));
    final byTick = <int, TempoChange>{};
    for (final change in changes) {
      byTick[change.tick] = change;
    }
    changes
      ..clear()
      ..addAll(byTick.values);
  }

  void _dedupeTimeSignatures(List<TimeSignatureChange> changes) {
    changes.sort((a, b) => a.tick.compareTo(b.tick));
    final byTick = <int, TimeSignatureChange>{};
    for (final change in changes) {
      byTick[change.tick] = change;
    }
    changes
      ..clear()
      ..addAll(byTick.values);
  }

  String _stripComments(String xml) {
    return xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  }

  String _decodeXml(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }
}

class _MusicXmlPart {
  final String id;
  final String body;

  const _MusicXmlPart({required this.id, required this.body});
}

class _MusicXmlToken {
  final String name;
  final String body;

  const _MusicXmlToken(this.name, this.body);
}

class _ParsedNote {
  final MidiNote? note;
  final int advanceTick;

  const _ParsedNote({required this.note, required this.advanceTick});
}

class _ParsedPart {
  final MidiTrackInfo track;
  final int maxTick;

  const _ParsedPart({required this.track, required this.maxTick});
}
