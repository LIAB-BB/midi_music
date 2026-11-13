class PieceScoreNote {
  final int staff;
  final int? diatonic;
  final int alter;
  final int startDivisions;
  final int durationDivisions;
  final bool isRest;

  const PieceScoreNote({
    required this.staff,
    required this.diatonic,
    required this.alter,
    required this.startDivisions,
    required this.durationDivisions,
    required this.isRest,
  });
}

class PieceScoreMeasure {
  final int ordinal;
  final int divisions;
  final int lengthDivisions;
  final List<PieceScoreNote> notes;

  const PieceScoreMeasure({
    required this.ordinal,
    required this.divisions,
    required this.lengthDivisions,
    required this.notes,
  });
}

/// 从曲目包派生的 partwise MusicXML 抽出可绘制的小节。
///
/// 只覆盖当前转换器写出的音高、休止、和弦、backup 和 forward。
class PieceScoreGraphic {
  final List<PieceScoreMeasure> measures;

  const PieceScoreGraphic(this.measures);

  static PieceScoreGraphic parse(String musicXml) {
    final part = RegExp(
      r'<part\b[^>]*>([\s\S]*?)</part>',
      caseSensitive: false,
    ).firstMatch(musicXml);
    if (part == null) {
      throw const FormatException('MusicXML 中没有 part');
    }
    final body = part.group(1) ?? '';
    final measures = <PieceScoreMeasure>[];
    var divisions = 1;
    var beats = 4;
    var beatType = 4;
    final measurePattern = RegExp(
      r'<measure\b([^>]*)>([\s\S]*?)</measure>',
      caseSensitive: false,
    );
    for (final match in measurePattern.allMatches(body)) {
      final attributes = match.group(1) ?? '';
      final measureBody = match.group(2) ?? '';
      final number = int.tryParse(_attribute(attributes, 'number') ?? '');
      final parsedAttributes = _attributes(measureBody);
      if (parsedAttributes.divisions != null &&
          parsedAttributes.divisions! > 0) {
        divisions = parsedAttributes.divisions!;
      }
      if (parsedAttributes.beats != null && parsedAttributes.beatType != null) {
        beats = parsedAttributes.beats!;
        beatType = parsedAttributes.beatType!;
      }
      final length = (beats * divisions * 4 / beatType).round();
      measures.add(
        PieceScoreMeasure(
          ordinal: number ?? measures.length + 1,
          divisions: divisions,
          lengthDivisions: length <= 0 ? 1 : length,
          notes: _notes(measureBody),
        ),
      );
    }
    if (measures.isEmpty) {
      throw const FormatException('MusicXML 中没有小节');
    }
    return PieceScoreGraphic(List<PieceScoreMeasure>.unmodifiable(measures));
  }
}

class _Attributes {
  final int? divisions;
  final int? beats;
  final int? beatType;

  const _Attributes(this.divisions, this.beats, this.beatType);
}

_Attributes _attributes(String measureBody) {
  final attributes = _firstElement(measureBody, 'attributes');
  if (attributes == null) return const _Attributes(null, null, null);
  final time = _firstElement(attributes, 'time');
  return _Attributes(
    int.tryParse(_firstText(attributes, 'divisions') ?? ''),
    time == null ? null : int.tryParse(_firstText(time, 'beats') ?? ''),
    time == null ? null : int.tryParse(_firstText(time, 'beat-type') ?? ''),
  );
}

List<PieceScoreNote> _notes(String measureBody) {
  final notes = <PieceScoreNote>[];
  final pattern = RegExp(
    r'<(note|backup|forward)\b[^>]*>([\s\S]*?)</\1>',
    caseSensitive: false,
  );
  var cursor = 0;
  var previousStart = 0;
  for (final match in pattern.allMatches(measureBody)) {
    final name = match.group(1)!.toLowerCase();
    final token = match.group(2) ?? '';
    final duration = int.tryParse(_firstText(token, 'duration') ?? '') ?? 0;
    switch (name) {
      case 'backup':
        cursor = cursor - duration < 0 ? 0 : cursor - duration;
      case 'forward':
        cursor += duration;
      case 'note':
        final isChord = RegExp(
          r'<chord\b',
          caseSensitive: false,
        ).hasMatch(token);
        final start = isChord ? previousStart : cursor;
        final pitch = _firstElement(token, 'pitch');
        final isRest =
            RegExp(r'<rest\b', caseSensitive: false).hasMatch(token) ||
            pitch == null;
        final step = pitch == null ? null : _firstText(pitch, 'step');
        final octave = pitch == null
            ? null
            : int.tryParse(_firstText(pitch, 'octave') ?? '');
        final alter =
            int.tryParse(
              pitch == null ? '' : (_firstText(pitch, 'alter') ?? ''),
            ) ??
            0;
        final staff = int.tryParse(_firstText(token, 'staff') ?? '') ?? 1;
        notes.add(
          PieceScoreNote(
            staff: staff,
            diatonic: step == null || octave == null
                ? null
                : _diatonic(step, octave),
            alter: alter,
            startDivisions: start,
            durationDivisions: duration,
            isRest: isRest,
          ),
        );
        if (!isChord) {
          previousStart = start;
          cursor += duration;
        }
    }
  }
  return List<PieceScoreNote>.unmodifiable(notes);
}

int? _diatonic(String step, int octave) {
  const values = {'C': 0, 'D': 1, 'E': 2, 'F': 3, 'G': 4, 'A': 5, 'B': 6};
  final value = values[step.toUpperCase()];
  if (value == null) return null;
  return octave * 7 + value;
}

String? _attribute(String attributes, String name) {
  return RegExp(
    '$name\\s*=\\s*["\\\']([^"\\\']+)["\\\']',
    caseSensitive: false,
  ).firstMatch(attributes)?.group(1);
}

String? _firstElement(String xml, String name) {
  return RegExp(
    '<$name\\b[^>]*>([\\s\\S]*?)</$name>',
    caseSensitive: false,
  ).firstMatch(xml)?.group(1);
}

String? _firstText(String xml, String name) {
  final text = _firstElement(xml, name)?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
