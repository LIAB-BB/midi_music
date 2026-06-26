import 'score_document.dart';
import 'score_position.dart';
import 'score_source.dart';

class MusicXmlParseException implements Exception {
  final String message;

  const MusicXmlParseException(this.message);

  @override
  String toString() => message;
}

class MusicXmlScoreParser {
  const MusicXmlScoreParser();

  ScoreDocument parse(
    String xml, {
    String sourceId = 'musicxml',
    String? path,
  }) {
    final root = _SimpleXmlParser(xml).parse();
    if (root.name != 'score-partwise') {
      throw const MusicXmlParseException('只支持 score-partwise MusicXML。');
    }

    final partNames = _parsePartNames(root);
    final parts = <ScorePart>[];
    for (final partElement in root.elements('part')) {
      final partId = partElement.attribute('id');
      if (partId == null || partId.isEmpty) {
        throw const MusicXmlParseException('MusicXML part 缺少 id。');
      }
      parts.add(
        _parsePart(
          partElement,
          partId: partId,
          partName: partNames[partId] ?? partId,
          sourceId: sourceId,
          path: path,
        ),
      );
    }

    if (parts.isEmpty) {
      throw const MusicXmlParseException('MusicXML 中没有可解析的 part。');
    }

    return ScoreDocument(
      id: sourceId,
      title: _title(root, path),
      parts: parts,
      source: SourceReference(
        sourceId: sourceId,
        stableId: sourceId,
        sourceType: 'musicxml',
        path: path,
      ),
    );
  }

  Map<String, String> _parsePartNames(_XmlElement root) {
    final partList = root.firstElement('part-list');
    if (partList == null) return const {};

    final names = <String, String>{};
    for (final scorePart in partList.elements('score-part')) {
      final id = scorePart.attribute('id');
      if (id == null) continue;
      names[id] = scorePart.firstElement('part-name')?.text.trim() ?? id;
    }
    return names;
  }

  ScorePart _parsePart(
    _XmlElement partElement, {
    required String partId,
    required String partName,
    required String sourceId,
    required String? path,
  }) {
    var divisions = 1;
    var absoluteBeat = 0.0;
    var defaultMeasureBeats = 4.0;
    final measures = <ScoreMeasure>[];

    for (final measureElement in partElement.elements('measure')) {
      final attributes = measureElement.firstElement('attributes');
      if (attributes != null) {
        divisions = _intText(attributes.firstElement('divisions')) ?? divisions;
        defaultMeasureBeats =
            _measureBeats(attributes.firstElement('time')) ??
            defaultMeasureBeats;
      }

      final measureNumber =
          int.tryParse(measureElement.attribute('number') ?? '') ??
          measures.length + 1;
      final voiceEvents = <String, List<ScoreEvent>>{};
      var cursorBeat = 0.0;
      var lastNoteStartBeat = 0.0;
      var measuredBeats = 0.0;
      var noteIndex = 0;

      for (final child in measureElement.children.whereType<_XmlElement>()) {
        switch (child.name) {
          case 'note':
            noteIndex += 1;
            final isChord = child.firstElement('chord') != null;
            final noteStartBeat = isChord ? lastNoteStartBeat : cursorBeat;
            final event = _parseNote(
              child,
              partId: partId,
              measureNumber: measureNumber,
              noteIndex: noteIndex,
              cursorBeat: noteStartBeat,
              absoluteBeat: absoluteBeat + noteStartBeat,
              divisions: divisions,
              sourceId: sourceId,
              path: path,
            );
            final voiceId = _voiceId(child);
            voiceEvents.putIfAbsent(voiceId, () => []).add(event);

            final durationBeats = event.durationBeats;
            measuredBeats = _max(measuredBeats, noteStartBeat + durationBeats);
            if (!isChord) {
              lastNoteStartBeat = cursorBeat;
              cursorBeat += durationBeats;
            }
          case 'backup':
            cursorBeat = _max(0, cursorBeat - _durationBeats(child, divisions));
          case 'forward':
            cursorBeat += _durationBeats(child, divisions);
            measuredBeats = _max(measuredBeats, cursorBeat);
        }
      }

      final durationBeats = _max(defaultMeasureBeats, measuredBeats);
      measures.add(
        ScoreMeasure(
          number: measureNumber,
          startBeat: absoluteBeat,
          durationBeats: durationBeats,
          voices: [
            for (final entry in voiceEvents.entries)
              ScoreVoice(id: entry.key, events: entry.value),
          ],
        ),
      );
      absoluteBeat += durationBeats;
    }

    return ScorePart(id: partId, name: partName, measures: measures);
  }

  ScoreEvent _parseNote(
    _XmlElement noteElement, {
    required String partId,
    required int measureNumber,
    required int noteIndex,
    required double cursorBeat,
    required double absoluteBeat,
    required int divisions,
    required String sourceId,
    required String? path,
  }) {
    final durationBeats = _durationBeats(noteElement, divisions);
    final id = '$partId:m$measureNumber:n$noteIndex';
    final position = ScorePosition(
      measureNumber: measureNumber,
      beat: cursorBeat + 1,
      absoluteBeat: absoluteBeat,
    );
    final source = SourceReference(
      sourceId: sourceId,
      stableId: id,
      sourceType: 'musicxml',
      path: path,
    );

    if (noteElement.firstElement('rest') != null) {
      return ScoreRest(
        id: id,
        position: position,
        durationBeats: durationBeats,
        source: source,
      );
    }

    final pitchElement = noteElement.firstElement('pitch');
    if (pitchElement == null) {
      throw MusicXmlParseException('音符 $id 缺少 pitch 或 rest。');
    }

    return ScoreNote(
      id: id,
      position: position,
      durationBeats: durationBeats,
      pitch: _parsePitch(pitchElement),
      voice: int.tryParse(_voiceId(noteElement)) ?? 1,
      tieStart: _hasTie(noteElement, 'start'),
      tieStop: _hasTie(noteElement, 'stop'),
      isGrace: noteElement.firstElement('grace') != null,
      source: source,
    );
  }

  NotatedPitch _parsePitch(_XmlElement pitchElement) {
    final stepText = pitchElement.firstElement('step')?.text.trim();
    final octave = _intText(pitchElement.firstElement('octave'));
    if (stepText == null || octave == null) {
      throw const MusicXmlParseException('pitch 缺少 step 或 octave。');
    }

    final step = switch (stepText.toUpperCase()) {
      'C' => PitchStep.c,
      'D' => PitchStep.d,
      'E' => PitchStep.e,
      'F' => PitchStep.f,
      'G' => PitchStep.g,
      'A' => PitchStep.a,
      'B' => PitchStep.b,
      _ => throw MusicXmlParseException('不支持的 pitch step: $stepText。'),
    };
    final alter = _intText(pitchElement.firstElement('alter')) ?? 0;
    return NotatedPitch(
      step: step,
      alter: alter,
      octave: octave,
      midiPitch: _midiPitch(step, alter, octave),
    );
  }

  String _voiceId(_XmlElement noteElement) {
    final voice = noteElement.firstElement('voice')?.text.trim();
    return voice == null || voice.isEmpty ? '1' : voice;
  }

  bool _hasTie(_XmlElement noteElement, String type) {
    for (final tie in noteElement.elements('tie')) {
      if (tie.attribute('type') == type) return true;
    }
    final notations = noteElement.firstElement('notations');
    if (notations == null) return false;
    for (final tied in notations.elements('tied')) {
      if (tied.attribute('type') == type) return true;
    }
    return false;
  }

  double _durationBeats(_XmlElement element, int divisions) {
    final duration = _intText(element.firstElement('duration'));
    if (duration == null) return 0;
    return duration / divisions;
  }

  double? _measureBeats(_XmlElement? timeElement) {
    if (timeElement == null) return null;
    final beats = _intText(timeElement.firstElement('beats'));
    final beatType = _intText(timeElement.firstElement('beat-type'));
    if (beats == null || beatType == null || beatType == 0) return null;
    return beats * 4 / beatType;
  }

  String _title(_XmlElement root, String? path) {
    final movementTitle = root.firstElement('movement-title')?.text.trim();
    if (movementTitle != null && movementTitle.isNotEmpty) return movementTitle;
    if (path == null || path.isEmpty) return 'MusicXML Score';
    return path.split('/').last;
  }
}

int? _intText(_XmlElement? element) {
  if (element == null) return null;
  return int.tryParse(element.text.trim());
}

int _midiPitch(PitchStep step, int alter, int octave) {
  final semitone = switch (step) {
    PitchStep.c => 0,
    PitchStep.d => 2,
    PitchStep.e => 4,
    PitchStep.f => 5,
    PitchStep.g => 7,
    PitchStep.a => 9,
    PitchStep.b => 11,
  };
  return (octave + 1) * 12 + semitone + alter;
}

double _max(double a, double b) => a > b ? a : b;

class _SimpleXmlParser {
  final String source;
  var _index = 0;

  _SimpleXmlParser(this.source);

  _XmlElement parse() {
    while (!_isDone) {
      _skipText();
      if (_startsWith('<!--')) {
        _skipUntil('-->');
      } else if (_startsWith('<?')) {
        _skipUntil('?>');
      } else if (_startsWith('<!')) {
        _skipDeclaration();
      } else if (_startsWith('<')) {
        return _parseElement();
      } else {
        _index += 1;
      }
    }
    throw const MusicXmlParseException('XML 内容为空。');
  }

  _XmlElement _parseElement() {
    _expect('<');
    final name = _readName();
    final attributes = <String, String>{};

    while (!_isDone) {
      _skipWhitespace();
      if (_startsWith('/>')) {
        _index += 2;
        return _XmlElement(name, attributes, const []);
      }
      if (_startsWith('>')) {
        _index += 1;
        break;
      }
      final attrName = _readName();
      _skipWhitespace();
      _expect('=');
      _skipWhitespace();
      attributes[attrName] = _readQuotedValue();
    }

    final children = <Object>[];
    while (!_isDone) {
      if (_startsWith('</')) {
        _index += 2;
        final closeName = _readName();
        if (closeName != name) {
          throw MusicXmlParseException('XML 标签不匹配：$name / $closeName。');
        }
        _skipWhitespace();
        _expect('>');
        return _XmlElement(name, attributes, children);
      }
      if (_startsWith('<!--')) {
        _skipUntil('-->');
      } else if (_startsWith('<![CDATA[')) {
        _index += '<![CDATA['.length;
        children.add(_readUntil(']]>'));
      } else if (_startsWith('<?')) {
        _skipUntil('?>');
      } else if (_startsWith('<!')) {
        _skipDeclaration();
      } else if (_startsWith('<')) {
        children.add(_parseElement());
      } else {
        final text = _readText();
        if (text.isNotEmpty) children.add(_decodeEntities(text));
      }
    }

    throw MusicXmlParseException('XML 标签未闭合：$name。');
  }

  String _readName() {
    final start = _index;
    while (!_isDone) {
      final char = source[_index];
      if (char.trim().isEmpty || char == '/' || char == '=' || char == '>') {
        break;
      }
      _index += 1;
    }
    if (start == _index) {
      throw MusicXmlParseException('XML 解析失败：位置 $_index 缺少名称。');
    }
    return source.substring(start, _index);
  }

  String _readQuotedValue() {
    final quote = source[_index];
    if (quote != '"' && quote != "'") {
      throw MusicXmlParseException('XML 属性缺少引号：位置 $_index。');
    }
    _index += 1;
    final start = _index;
    while (!_isDone && source[_index] != quote) {
      _index += 1;
    }
    if (_isDone) {
      throw const MusicXmlParseException('XML 属性值未闭合。');
    }
    final value = source.substring(start, _index);
    _index += 1;
    return _decodeEntities(value);
  }

  String _readText() {
    final start = _index;
    while (!_isDone && source[_index] != '<') {
      _index += 1;
    }
    return source.substring(start, _index);
  }

  String _readUntil(String token) {
    final start = _index;
    final end = source.indexOf(token, _index);
    if (end < 0) {
      throw MusicXmlParseException('XML 缺少结束标记：$token。');
    }
    _index = end + token.length;
    return source.substring(start, end);
  }

  void _skipDeclaration() {
    var bracketDepth = 0;
    while (!_isDone) {
      final char = source[_index];
      if (char == '[') bracketDepth += 1;
      if (char == ']') bracketDepth -= 1;
      if (char == '>' && bracketDepth <= 0) {
        _index += 1;
        return;
      }
      _index += 1;
    }
  }

  void _skipText() {
    while (!_isDone && source[_index].trim().isEmpty) {
      _index += 1;
    }
  }

  void _skipWhitespace() => _skipText();

  void _skipUntil(String token) {
    _readUntil(token);
  }

  void _expect(String value) {
    if (!_startsWith(value)) {
      throw MusicXmlParseException('XML 解析失败：位置 $_index 期待 $value。');
    }
    _index += value.length;
  }

  bool _startsWith(String value) => source.startsWith(value, _index);

  bool get _isDone => _index >= source.length;
}

class _XmlElement {
  final String name;
  final Map<String, String> attributes;
  final List<Object> children;

  const _XmlElement(this.name, this.attributes, this.children);

  String? attribute(String name) => attributes[name];

  Iterable<_XmlElement> elements(String name) {
    return children.whereType<_XmlElement>().where(
      (child) => child.name == name,
    );
  }

  _XmlElement? firstElement(String name) {
    for (final child in elements(name)) {
      return child;
    }
    return null;
  }

  String get text {
    final buffer = StringBuffer();
    for (final child in children) {
      if (child is String) {
        buffer.write(child);
      } else if (child is _XmlElement) {
        buffer.write(child.text);
      }
    }
    return buffer.toString();
  }
}

String _decodeEntities(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
