import 'dart:convert';

const bundledPieceManifestAssets = <String>['assets/pieces/k478.json'];

enum PieceTrackRole { performer, accompaniment }

class PieceTrackSpec {
  final int index;
  final PieceTrackRole role;
  final int program;
  final String? name;

  const PieceTrackSpec({
    required this.index,
    required this.role,
    required this.program,
    this.name,
  });
}

/// 一首曲子的数据包声明。轨道角色和拍号来自数据，不写进播放器分支。
class PieceManifest {
  final String id;
  final String title;
  final String performanceFile;
  final int ticksPerBeat;
  final int? timeSignatureNumerator;
  final int? timeSignatureDenominator;
  final List<PieceTrackSpec> tracks;

  const PieceManifest({
    required this.id,
    required this.title,
    required this.performanceFile,
    required this.ticksPerBeat,
    required this.timeSignatureNumerator,
    required this.timeSignatureDenominator,
    required this.tracks,
  });

  Set<int> get performerTrackIndexes => {
    for (final track in tracks)
      if (track.role == PieceTrackRole.performer) track.index,
  };

  Set<int> get accompanimentTrackIndexes => {
    for (final track in tracks)
      if (track.role == PieceTrackRole.accompaniment) track.index,
  };

  static PieceManifest parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('曲目包必须是 JSON 对象');
    }
    final id = _requiredText(decoded, 'id');
    final title = _requiredText(decoded, 'title');
    final performanceFile = _requiredText(decoded, 'performanceFile');
    final ticksPerBeat = _requiredInt(decoded, 'ticksPerBeat');
    if (ticksPerBeat <= 0) {
      throw const FormatException('ticksPerBeat 必须大于 0');
    }
    final signature = _optionalSignature(decoded);
    final tracks = _tracks(decoded);
    return PieceManifest(
      id: id,
      title: title,
      performanceFile: performanceFile,
      ticksPerBeat: ticksPerBeat,
      timeSignatureNumerator: signature?.numerator,
      timeSignatureDenominator: signature?.denominator,
      tracks: tracks,
    );
  }
}

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key 必须是非空字符串');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key 必须是整数');
  }
  return value;
}

({int numerator, int denominator})? _optionalSignature(
  Map<String, dynamic> json,
) {
  final value = json['timeSignature'];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) {
    throw const FormatException('timeSignature 必须是对象');
  }
  final numerator = _requiredInt(value, 'numerator');
  final denominator = _requiredInt(value, 'denominator');
  if (numerator <= 0 || denominator <= 0) {
    throw const FormatException('拍号必须大于 0');
  }
  return (numerator: numerator, denominator: denominator);
}

List<PieceTrackSpec> _tracks(Map<String, dynamic> json) {
  final value = json['tracks'];
  if (value is! List<dynamic> || value.isEmpty) {
    throw const FormatException('tracks 必须是非空数组');
  }
  final tracks = <PieceTrackSpec>[];
  final seen = <int>{};
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      throw const FormatException('轨道声明必须是对象');
    }
    final index = _requiredInt(item, 'index');
    if (!seen.add(index)) {
      throw FormatException('轨道 $index 重复声明');
    }
    final program = _requiredInt(item, 'program');
    if (program < 0 || program > 127) {
      throw FormatException('轨道 $index 的 Program 超出 0–127');
    }
    String? name;
    final rawName = item['name'];
    if (rawName != null) {
      if (rawName is! String) {
        throw FormatException('轨道 $index 的名称必须是字符串');
      }
      name = rawName;
    }
    tracks.add(
      PieceTrackSpec(
        index: index,
        role: _role(item['role'], index),
        program: program,
        name: name,
      ),
    );
  }
  if (tracks.every((track) => track.role != PieceTrackRole.performer)) {
    throw const FormatException('曲目包至少要有一条演奏者轨道');
  }
  return List<PieceTrackSpec>.unmodifiable(tracks);
}

PieceTrackRole _role(Object? value, int index) {
  return switch (value) {
    'performer' => PieceTrackRole.performer,
    'accompaniment' => PieceTrackRole.accompaniment,
    _ => throw FormatException(
      '轨道 $index 的 role 必须是 performer 或 accompaniment',
    ),
  };
}
