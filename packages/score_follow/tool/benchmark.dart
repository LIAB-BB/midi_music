// ignore_for_file: avoid_print
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_midi_pro/dart_midi_pro.dart';
import 'package:score_follow/score_follow.dart';

const _pianoTrackIndexes = [4, 5];
const _midiPath = '../../assets/midi/mozart_k478_piano_quartet.mid';

void main(List<String> args) {
  final path = args.isEmpty ? _midiPath : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('找不到 MIDI：$path');
    exitCode = 2;
    return;
  }

  final midi = MidiParser().parseMidiFromBuffer(file.readAsBytesSync());
  final ppq = midi.header.ticksPerBeat ?? 480;
  final tempo = _TempoMap.fromMidi(midi, ppq);
  _printTrackSummary(midi);

  final notes = <ScoreNote>[];
  for (final trackIndex in _pianoTrackIndexes) {
    notes.addAll(_readTrackNotes(midi.tracks[trackIndex], tempo));
  }
  final score = Score.fromNotes(notes, title: 'K.478 piano (tracks 4/5)');
  print(
    '跟随谱面：${score.length} 个 onset，'
    '${notes.length} 个音符，参考时长 ${_clock(score.duration)}',
  );

  final scenarios = <_Scenario>[
    _Scenario(
      name: 'A 干净演奏（rubato + 抖动 + 和弦拆分）',
      seed: 7,
      wrongRate: 0,
      missingRate: 0,
      extraRate: 0,
    ),
    _Scenario(
      name: 'B 真实失误（3% 错音 / 1.5% 漏音 / 2% 装饰音）',
      seed: 11,
      wrongRate: 0.03,
      missingRate: 0.015,
      extraRate: 0.02,
    ),
    _Scenario(
      name: 'C 中段跳页（从 onset 1/3 处跳到 +10）',
      seed: 19,
      wrongRate: 0.02,
      missingRate: 0.01,
      extraRate: 0.01,
      jumpAt: score.length ~/ 3,
      jumpBy: 10,
    ),
  ];

  print('');
  print(
    '${'场景'.padRight(40)} ${'算法'.padRight(8)} '
    '${'精确%'.padLeft(7)} ${'±1%'.padLeft(7)} '
    '${'速度MAE/中位'.padLeft(12)} ${'锁定'.padLeft(5)} '
    '${'最大跳'.padLeft(6)} ${'跳页恢复'.padLeft(8)}',
  );
  for (final scenario in scenarios) {
    final performance = _perform(score, scenario);
    final v1 = _runStrict(score, performance);
    final v2 = _runAdaptive(score, performance);
    _printMetrics(scenario.name, 'v1 严格', v1);
    _printMetrics('', 'v2 多假设', v2);
    print('');
  }

  print('说明：');
  print('  精确% = 估计位置与真实 onset 完全一致的比例；v1 在失误/跳页后不会前进。');
  print('  速度MAE/中位 只统计“已锁定且位置完全正确”的音符；v1 在 B/C 中样本极少。');
  print('  跳页恢复 = 跳页后连续 3 个音位置误差 <=1 所需的音数；— 表示无跳页。');
}

class _Scenario {
  _Scenario({
    required this.name,
    required this.seed,
    required this.wrongRate,
    required this.missingRate,
    required this.extraRate,
    this.jumpAt,
    this.jumpBy = 0,
  });

  final String name;
  final int seed;
  final double wrongRate;
  final double missingRate;
  final double extraRate;
  final int? jumpAt;
  final int jumpBy;
}

class _Performance {
  _Performance({required this.notes, required this.jumpPerformedIndex});

  final List<_PerformedNote> notes;
  final int? jumpPerformedIndex;
}

class _PerformedNote {
  const _PerformedNote({
    required this.pitch,
    required this.time,
    required this.trueOnsetIndex,
    required this.trueScoreTime,
    required this.kind,
  });

  final int pitch;
  final double time;
  final int trueOnsetIndex;
  final double trueScoreTime;
  final _NoteKind kind;
}

enum _NoteKind { correct, wrong, extra, chordTrailing }

class _Metrics {
  int total = 0;
  int exact = 0;
  int withinOne = 0;
  int withinTwo = 0;
  int wrong = 0;
  int speedSamples = 0;
  final List<double> speedErrors = [];
  int lockNotes = 0;
  int maxJump = 0;
  int recoveryNotes = -1;
  int? previousPosition;
  final List<int> positions = [];
}

_Metrics _runStrict(Score score, _Performance performance) {
  final follower = _StrictFollower(score);
  final metrics = _Metrics();
  var locked = false;
  for (var index = 0; index < performance.notes.length; index++) {
    final note = performance.notes[index];
    follower.onNote(note.pitch, note.time);
    if (!locked && follower.matched) {
      locked = true;
      metrics.lockNotes = index + 1;
    }
    _record(metrics, follower.position, note, follower.speed, locked);
    metrics.previousPosition = follower.position;
  }
  _recovery(metrics, performance);
  return metrics;
}

_Metrics _runAdaptive(Score score, _Performance performance) {
  final follower = AdaptiveScoreFollower(score: score);
  final metrics = _Metrics();
  var locked = false;
  for (var index = 0; index < performance.notes.length; index++) {
    final note = performance.notes[index];
    final update = follower.onNoteOn(note.pitch, note.time);
    if (!locked && update.confidence >= 0.5) {
      locked = true;
      metrics.lockNotes = index + 1;
    }
    _record(metrics, update.positionOnsetIndex, note, update.speed, locked);
    metrics.previousPosition = update.positionOnsetIndex;
  }
  _recovery(metrics, performance);
  return metrics;
}

void _record(
  _Metrics metrics,
  int position,
  _PerformedNote note,
  double speed,
  bool locked,
) {
  metrics
    ..total += 1
    ..positions.add(position);
  final difference = (position - note.trueOnsetIndex).abs();
  if (difference == 0) {
    metrics.exact++;
  } else if (difference == 1) {
    metrics.withinOne++;
  } else if (difference == 2) {
    metrics.withinTwo++;
  } else {
    metrics.wrong++;
  }

  final previousPosition = metrics.previousPosition;
  if (previousPosition != null) {
    final jump = (position - previousPosition).abs();
    if (jump > metrics.maxJump) metrics.maxJump = jump;
  }

  if (locked && difference == 0 && note.kind == _NoteKind.correct) {
    metrics.speedSamples++;
    metrics.speedErrors.add((speed - _speedAt(note.trueScoreTime)).abs());
  }
}

void _recovery(_Metrics metrics, _Performance performance) {
  final jump = performance.jumpPerformedIndex;
  if (jump == null || jump <= 0) {
    metrics.recoveryNotes = -1;
    return;
  }
  var stable = 0;
  for (var index = jump; index < performance.notes.length; index++) {
    final difference =
        (metrics.positions[index] - performance.notes[index].trueOnsetIndex)
            .abs();
    if (difference <= 1) {
      stable++;
      if (stable >= 3) {
        metrics.recoveryNotes = index - jump + 1;
        return;
      }
    } else {
      stable = 0;
    }
  }
  metrics.recoveryNotes = 999;
}

void _printMetrics(String scenario, String algorithm, _Metrics metrics) {
  final total = math.max(1, metrics.total);
  final exact = metrics.exact * 100 / total;
  final withinOne = (metrics.exact + metrics.withinOne) * 100 / total;
  final speedMae = metrics.speedSamples == 0
      ? double.nan
      : metrics.speedErrors.reduce((a, b) => a + b) / metrics.speedSamples;
  final sortedSpeed = List<double>.of(metrics.speedErrors)..sort();
  final speedMedian = sortedSpeed.isEmpty
      ? double.nan
      : sortedSpeed[sortedSpeed.length ~/ 2];
  final speedText =
      '${speedMae.toStringAsFixed(3)}/${speedMedian.toStringAsFixed(3)}';
  final recovery = metrics.recoveryNotes < 0
      ? '—'
      : metrics.recoveryNotes >= 999
      ? '未恢复'
      : '${metrics.recoveryNotes} 音';
  print(
    '${scenario.padRight(40)} ${algorithm.padRight(8)} '
    '${exact.toStringAsFixed(1).padLeft(7)} '
    '${withinOne.toStringAsFixed(1).padLeft(7)} '
    '${speedText.padLeft(12)} '
    '${metrics.lockNotes.toString().padLeft(5)} '
    '${metrics.maxJump.toString().padLeft(6)} '
    '${recovery.padLeft(8)}',
  );
}

double _speedAt(double scoreSeconds) {
  final value =
      1 +
      0.10 * math.sin(scoreSeconds / 8.0) +
      0.05 * math.sin(scoreSeconds / 2.3);
  return value.clamp(0.72, 1.28);
}

_Performance _perform(Score score, _Scenario scenario) {
  final random = math.Random(scenario.seed);
  final notes = <_PerformedNote>[];
  int? jumpPerformedIndex;
  var performanceTime = 0.0;
  var previousScoreTime = 0.0;
  var index = 0;
  var jumped = false;

  while (index < score.length) {
    if (!jumped &&
        scenario.jumpAt != null &&
        index >= scenario.jumpAt! &&
        scenario.jumpBy > 0) {
      index = math.min(score.length - 1, index + scenario.jumpBy);
      performanceTime += 0.5;
      jumped = true;
      jumpPerformedIndex = notes.length;
      previousScoreTime = score.onsets[index].time;
    }

    final onset = score.onsets[index];
    if (index > 0) {
      final delta = onset.time - previousScoreTime;
      if (delta > 0) {
        final middle = (onset.time + previousScoreTime) / 2;
        performanceTime += delta / _speedAt(middle);
      }
    }
    previousScoreTime = onset.time;

    final jitter = (random.nextDouble() - 0.5) * 0.03;
    final onsetTime = performanceTime + jitter;

    final missing = random.nextDouble() < scenario.missingRate;
    if (!missing) {
      for (var noteIndex = 0; noteIndex < onset.notes.length; noteIndex++) {
        final note = onset.notes[noteIndex];
        var pitch = note.pitch;
        var kind = noteIndex == 0 ? _NoteKind.correct : _NoteKind.chordTrailing;
        if (noteIndex == 0 && random.nextDouble() < scenario.wrongRate) {
          pitch = _wrongPitch(score, onset.index, random);
          kind = _NoteKind.wrong;
        }
        final chordOffset = noteIndex * (0.012 + random.nextDouble() * 0.018);
        notes.add(
          _PerformedNote(
            pitch: pitch,
            time: onsetTime + chordOffset,
            trueOnsetIndex: onset.index,
            trueScoreTime: onset.time,
            kind: kind,
          ),
        );
      }
    }

    if (random.nextDouble() < scenario.extraRate) {
      notes.add(
        _PerformedNote(
          pitch: _wrongPitch(score, onset.index, random),
          time: onsetTime + 0.06,
          trueOnsetIndex: onset.index,
          trueScoreTime: onset.time,
          kind: _NoteKind.extra,
        ),
      );
    }
    index++;
  }

  notes.sort((a, b) => a.time.compareTo(b.time));
  return _Performance(notes: notes, jumpPerformedIndex: jumpPerformedIndex);
}

int _wrongPitch(Score score, int onsetIndex, math.Random random) {
  final forbidden = <int>{};
  for (
    var offset = 0;
    offset < 3 && onsetIndex + offset < score.length;
    offset++
  ) {
    forbidden.addAll(score.onsets[onsetIndex + offset].pitches);
  }
  for (var attempt = 0; attempt < 16; attempt++) {
    final pitch = 48 + random.nextInt(40);
    if (!forbidden.contains(pitch)) return pitch;
  }
  return 96;
}

void _printTrackSummary(MidiFile midi) {
  print('MIDI：${midi.tracks.length} 轨，PPQ=${midi.header.ticksPerBeat}');
  for (var index = 0; index < midi.tracks.length; index++) {
    var tick = 0;
    var noteOns = 0;
    var name = '';
    final programs = <int>{};
    final channels = <int>{};
    for (final event in midi.tracks[index]) {
      tick += event.deltaTime;
      if (event is NoteOnEvent && event.velocity > 0) {
        noteOns++;
        channels.add(event.channel);
      } else if (event is ProgramChangeMidiEvent) {
        programs.add(event.programNumber);
      } else if (event is TrackNameEvent) {
        name = event.text;
      }
    }
    print(
      '  #$index "$name" ch=$channels program=$programs '
      'noteOns=$noteOns endTick=$tick',
    );
  }
}

List<ScoreNote> _readTrackNotes(List<MidiEvent> events, _TempoMap tempo) {
  final notes = <ScoreNote>[];
  final pending = <String, Queue<({int startTick, int pitch, int velocity})>>{};
  var tick = 0;

  void closeNote(int channel, int noteNumber) {
    final key = '$channel-$noteNumber';
    final queue = pending[key];
    if (queue == null || queue.isEmpty) return;
    final start = queue.removeFirst();
    notes.add(
      ScoreNote(
        pitch: start.pitch,
        start: tempo.tickToSeconds(start.startTick),
        end: tempo.tickToSeconds(tick),
        velocity: start.velocity,
        startTick: start.startTick,
        endTick: tick,
      ),
    );
  }

  for (final event in events) {
    tick += event.deltaTime;
    if (event is NoteOnEvent && event.velocity > 0) {
      final key = '${event.channel}-${event.noteNumber}';
      pending
          .putIfAbsent(
            key,
            () => Queue<({int startTick, int pitch, int velocity})>(),
          )
          .add((
            startTick: tick,
            pitch: event.noteNumber,
            velocity: event.velocity,
          ));
    } else if (event is NoteOffEvent) {
      closeNote(event.channel, event.noteNumber);
    } else if (event is NoteOnEvent && event.velocity == 0) {
      closeNote(event.channel, event.noteNumber);
    }
  }
  return notes;
}

class _TempoMap {
  _TempoMap(this.ppq, this._changes) : _segmentTimes = <double>[] {
    _segmentTimes.add(0);
    for (var index = 1; index < _changes.length; index++) {
      final previous = _changes[index - 1];
      final current = _changes[index];
      final secondsPerTick = previous.microsecondsPerBeat / (ppq * 1000000.0);
      _segmentTimes.add(
        _segmentTimes[index - 1] +
            (current.tick - previous.tick) * secondsPerTick,
      );
    }
  }

  factory _TempoMap.fromMidi(MidiFile midi, int ppq) {
    final byTick = <int, int>{};
    for (final track in midi.tracks) {
      var tick = 0;
      for (final event in track) {
        tick += event.deltaTime;
        if (event is SetTempoEvent) {
          byTick[tick] = event.microsecondsPerBeat;
        }
      }
    }
    byTick.putIfAbsent(0, () => 500000);
    final ticks = byTick.keys.toList()..sort();
    final changes = <_TempoChange>[
      for (final tick in ticks)
        _TempoChange(tick: tick, microsecondsPerBeat: byTick[tick]!),
    ];
    return _TempoMap(ppq, changes);
  }

  final int ppq;
  final List<_TempoChange> _changes;
  final List<double> _segmentTimes;

  double tickToSeconds(int tick) {
    var low = 0;
    var high = _changes.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_changes[middle].tick <= tick) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final change = _changes[low];
    final ticks = tick - change.tick;
    return _segmentTimes[low] +
        ticks * change.microsecondsPerBeat / (ppq * 1000000.0);
  }
}

class _TempoChange {
  const _TempoChange({required this.tick, required this.microsecondsPerBeat});

  final int tick;
  final int microsecondsPerBeat;
}

String _clock(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final rest = total % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

/// 旧实现的等价基线：只允许当前期待 onset，3 次错音后仍把位置锁在
/// 期待处。它没有 look-ahead，也无法在漏音/跳段后前进。
class _StrictFollower {
  _StrictFollower(this.score);

  final Score score;
  int _expected = 0;
  int? _lastMatchedIndex;
  double _lastMatchedTime = 0;
  double _speed = 1;
  int _unmatched = 0;

  int get position => _expected == 0 ? 0 : _expected - 1;

  double get speed => _speed;

  bool get matched => _lastMatchedIndex != null;

  void onNote(int pitch, double time) {
    if (_expected >= score.length) return;
    final previousIndex = _lastMatchedIndex;
    if (previousIndex != null &&
        previousIndex == _expected - 1 &&
        time - _lastMatchedTime <= 0.08 &&
        score.onsets[previousIndex].containsPitch(pitch)) {
      return;
    }

    final expected = score.onsets[_expected];
    if (expected.containsPitch(pitch)) {
      if (previousIndex != null) {
        final scoreDelta = expected.time - score.onsets[previousIndex].time;
        final wallDelta = time - _lastMatchedTime;
        if (scoreDelta > 0.02 && wallDelta > 0) {
          final raw = (scoreDelta / wallDelta).clamp(0.25, 2.0);
          _speed = _speed * 0.7 + raw * 0.3;
        }
      }
      _lastMatchedIndex = _expected;
      _lastMatchedTime = time;
      _expected++;
      _unmatched = 0;
      return;
    }

    _unmatched++;
    if (_unmatched >= 3) {
      // 旧实现只把播放器 seek 回“期待位置”，期待位置本身不前进。
      _lastMatchedTime = time;
    }
  }
}
