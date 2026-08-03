import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../models/midi_track.dart';

/// 使用解析后的 MIDI 音符绘制的钢琴卷帘。
///
/// 这不是音频波形或示意谱面：每一个矩形都对应 MIDI 文件中的一个
/// [MidiNote]，横轴为秒、纵轴为 MIDI 音高。
class MidiPianoRoll extends StatelessWidget {
  final MidiSongData song;
  final double currentTime;
  final Color accent;
  final double visibleSeconds;

  const MidiPianoRoll({
    super.key,
    required this.song,
    required this.currentTime,
    required this.accent,
    this.visibleSeconds = 12,
  });

  @override
  Widget build(BuildContext context) {
    final trackCount = song.noteTracks.length;
    return Semantics(
      label: '真实 MIDI 钢琴卷帘，$trackCount 条音符轨',
      child: Container(
        key: const Key('midi-piano-roll'),
        decoration: BoxDecoration(
          color: const Color(0xFF17130F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.42)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7ED3AA),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7ED3AA).withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text(
                    '真实 MIDI 钢琴卷帘',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: CupertinoColors.white,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$trackCount 轨 · ${song.totalDuration.toStringAsFixed(0)} 秒',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCFC1AE),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(13),
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _MidiPianoRollPainter(
                      song: song,
                      currentTime: currentTime,
                      accent: accent,
                      visibleSeconds: visibleSeconds,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MidiPianoRollPainter extends CustomPainter {
  final MidiSongData song;
  final double currentTime;
  final Color accent;
  final double visibleSeconds;

  const _MidiPianoRollPainter({
    required this.song,
    required this.currentTime,
    required this.accent,
    required this.visibleSeconds,
  });

  static const _trackColors = [
    Color(0xFFE8A15B),
    Color(0xFF7CC7F2),
    Color(0xFFC79BEF),
    Color(0xFF7ED3AA),
    Color(0xFFF28AA1),
    Color(0xFFF1D46D),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final notes = song.noteTracks.expand((track) => track.notes).toList();
    if (notes.isEmpty) return;

    final pitchRange = _pitchRange(notes);
    const keyboardWidth = 30.0;
    final gridRect = Rect.fromLTWH(
      keyboardWidth,
      0,
      math.max(0, size.width - keyboardWidth),
      size.height,
    );
    final secondsWindow = math.min(
      visibleSeconds,
      math.max(1.0, song.totalDuration),
    );
    final windowStart = _windowStart(secondsWindow);
    final windowEnd = windowStart + secondsWindow;
    final rowHeight = gridRect.height / pitchRange.count;

    _drawPitchGrid(canvas, gridRect, pitchRange, rowHeight);
    _drawKeyboard(
      canvas,
      Rect.fromLTWH(0, 0, keyboardWidth, size.height),
      pitchRange,
      rowHeight,
    );
    _drawTimeGrid(canvas, gridRect, windowStart, secondsWindow);

    for (final track in song.noteTracks) {
      final color = _trackColors[track.index % _trackColors.length];
      final fill = Paint()..color = color.withValues(alpha: 0.85);
      final edge = Paint()
        ..color = color.withValues(alpha: 0.96)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7;
      for (final note in track.notes) {
        if (note.endTime < windowStart || note.startTime > windowEnd) continue;
        final startRatio = ((note.startTime - windowStart) / secondsWindow)
            .clamp(0.0, 1.0);
        final endRatio = ((note.endTime - windowStart) / secondsWindow).clamp(
          0.0,
          1.0,
        );
        final noteTop =
            gridRect.bottom -
            (note.noteNumber - pitchRange.low + 1) * rowHeight;
        final rect = Rect.fromLTWH(
          gridRect.left + gridRect.width * startRatio,
          noteTop + math.min(1.0, rowHeight * 0.13),
          math.max(2.0, gridRect.width * (endRatio - startRatio)),
          math.max(2.0, rowHeight * 0.74),
        );
        final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        canvas.drawRRect(rounded, fill);
        canvas.drawRRect(rounded, edge);
      }
    }

    final cursorRatio = ((currentTime - windowStart) / secondsWindow).clamp(
      0.0,
      1.0,
    );
    final cursorX = gridRect.left + gridRect.width * cursorRatio;
    final cursorPaint = Paint()
      ..color = accent
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(cursorX, 0),
      Offset(cursorX, gridRect.bottom),
      cursorPaint,
    );
    canvas.drawCircle(Offset(cursorX, 7), 4, Paint()..color = accent);
  }

  _PitchRange _pitchRange(List<MidiNote> notes) {
    var low = notes.map((note) => note.noteNumber).reduce(math.min);
    var high = notes.map((note) => note.noteNumber).reduce(math.max);
    low = math.max(21, ((low - 5) ~/ 12) * 12);
    high = math.min(108, ((high + 7) ~/ 12) * 12 + 11);
    if (high - low < 23) {
      final center = (high + low) ~/ 2;
      low = math.max(21, center - 12);
      high = math.min(108, low + 24);
    }
    return _PitchRange(low, high);
  }

  double _windowStart(double secondsWindow) {
    final preferred = currentTime - secondsWindow * 0.3;
    final maximum = math.max(0.0, song.totalDuration - secondsWindow);
    return preferred.clamp(0.0, maximum);
  }

  void _drawPitchGrid(
    Canvas canvas,
    Rect rect,
    _PitchRange range,
    double rowHeight,
  ) {
    final blackKeyPaint = Paint()..color = const Color(0xFF211A16);
    final linePaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.6;
    final cLinePaint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    for (var pitch = range.low; pitch <= range.high; pitch += 1) {
      final top = rect.bottom - (pitch - range.low + 1) * rowHeight;
      if (_isBlackKey(pitch)) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, top, rect.width, rowHeight),
          blackKeyPaint,
        );
      }
      canvas.drawLine(
        Offset(rect.left, top),
        Offset(rect.right, top),
        pitch % 12 == 0 ? cLinePaint : linePaint,
      );
    }
  }

  void _drawKeyboard(
    Canvas canvas,
    Rect rect,
    _PitchRange range,
    double rowHeight,
  ) {
    const labelStyle = TextStyle(fontSize: 8, color: Color(0xFFE7DCCB));
    for (var pitch = range.low; pitch <= range.high; pitch += 1) {
      final top = rect.bottom - (pitch - range.low + 1) * rowHeight;
      final keyRect = Rect.fromLTWH(rect.left, top, rect.width, rowHeight);
      final isBlack = _isBlackKey(pitch);
      canvas.drawRect(
        keyRect,
        Paint()
          ..color = isBlack ? const Color(0xFF0D0A08) : const Color(0xFFE8DED0),
      );
      canvas.drawRect(
        keyRect,
        Paint()
          ..color = const Color(0xFF604B3D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.45,
      );
      if (pitch % 12 == 0 && rowHeight >= 4) {
        final painter = TextPainter(
          text: TextSpan(text: 'C${pitch ~/ 12 - 1}', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width - 2);
        painter.paint(
          canvas,
          Offset(2, top + (rowHeight - painter.height) / 2),
        );
      }
    }
  }

  void _drawTimeGrid(
    Canvas canvas,
    Rect rect,
    double start,
    double secondsWindow,
  ) {
    final paint = Paint()
      ..color = CupertinoColors.white.withValues(alpha: 0.11)
      ..strokeWidth = 0.7;
    const labelStyle = TextStyle(fontSize: 9, color: Color(0xFFBDAF9C));
    final step = secondsWindow <= 8 ? 1 : 2;
    final first = (start / step).ceil() * step;
    for (var second = first; second <= start + secondsWindow; second += step) {
      final x = rect.left + rect.width * ((second - start) / secondsWindow);
      canvas.drawLine(Offset(x, 0), Offset(x, rect.bottom), paint);
      final painter = TextPainter(
        text: TextSpan(text: '${second}s', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x + 3, 3));
    }
  }

  bool _isBlackKey(int pitch) {
    return switch (pitch % 12) {
      1 || 3 || 6 || 8 || 10 => true,
      _ => false,
    };
  }

  @override
  bool shouldRepaint(covariant _MidiPianoRollPainter oldDelegate) {
    return oldDelegate.song != song ||
        oldDelegate.currentTime != currentTime ||
        oldDelegate.accent != accent ||
        oldDelegate.visibleSeconds != visibleSeconds;
  }
}

class _PitchRange {
  final int low;
  final int high;

  const _PitchRange(this.low, this.high);

  int get count => high - low + 1;
}
