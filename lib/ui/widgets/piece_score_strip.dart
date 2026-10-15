import 'package:flutter/cupertino.dart';

import '../../core/notation/piece_score_graphic.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';

/// 用曲目包 MusicXML 画出的试谱。它不是 OSMD 或 Verovio 正式刻谱。
class PieceScoreStrip extends StatefulWidget {
  final String musicXml;
  final int currentOrdinal;
  final ValueChanged<int>? onMeasureSelected;

  const PieceScoreStrip({
    super.key,
    required this.musicXml,
    required this.currentOrdinal,
    this.onMeasureSelected,
  });

  @override
  State<PieceScoreStrip> createState() => _PieceScoreStripState();
}

class _PieceScoreStripState extends State<PieceScoreStrip> {
  static const _itemExtent = 236.0;
  final ScrollController _controller = ScrollController();
  PieceScoreGraphic? _graphic;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parse();
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(PieceScoreStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicXml != widget.musicXml) _parse();
    if (oldWidget.currentOrdinal != widget.currentOrdinal ||
        oldWidget.musicXml != widget.musicXml) {
      _scheduleScroll();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    try {
      _graphic = PieceScoreGraphic.parse(widget.musicXml);
      _error = null;
    } on FormatException catch (error) {
      _graphic = null;
      _error = error.message;
    }
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final graphic = _graphic;
      if (!mounted || graphic == null || !_controller.hasClients) return;
      final index = graphic.measures.indexWhere(
        (measure) => measure.ordinal == widget.currentOrdinal,
      );
      if (index < 0) return;
      final viewport = _controller.position.viewportDimension;
      final target = index * _itemExtent - (viewport - _itemExtent) / 2;
      final max = _controller.position.maxScrollExtent;
      _controller.jumpTo(target.clamp(0.0, max));
    });
  }

  @override
  Widget build(BuildContext context) {
    final graphic = _graphic;
    final selectionEnabled = widget.onMeasureSelected != null;
    return LuxuryPanel(
      key: const Key('piece-score-strip'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow(label: 'MUSICXML'),
          const SizedBox(height: 8),
          Text(
            _error ?? '试排的钢琴谱，来自曲目包 MusicXML。还不是正式刻谱。',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: LuxuryPalette.textMuted,
            ),
          ),
          if (graphic != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 168,
              child: ListView.builder(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                itemExtent: _itemExtent,
                itemCount: graphic.measures.length,
                itemBuilder: (context, index) {
                  final measure = graphic.measures[index];
                  final selected = measure.ordinal == widget.currentOrdinal;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      key: Key('piece-score-measure-${measure.ordinal}'),
                      onTap: selectionEnabled
                          ? () => widget.onMeasureSelected!(measure.ordinal)
                          : null,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? LuxuryPalette.gold.withValues(alpha: 0.16)
                              : CupertinoColors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected
                                ? LuxuryPalette.goldBright
                                : LuxuryPalette.divider,
                          ),
                        ),
                        child: CustomPaint(
                          painter: _MeasurePainter(measure),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeasurePainter extends CustomPainter {
  final PieceScoreMeasure measure;

  const _MeasurePainter(this.measure);

  @override
  void paint(Canvas canvas, Size size) {
    const lineGap = 7.0;
    const trebleBottom = 58.0;
    const bassBottom = 124.0;
    final linePaint = Paint()
      ..color = LuxuryPalette.textSubtle
      ..strokeWidth = 1;
    for (var line = 0; line < 5; line++) {
      final trebleY = trebleBottom - line * lineGap;
      final bassY = bassBottom - line * lineGap;
      canvas
        ..drawLine(
          Offset(28, trebleY),
          Offset(size.width - 12, trebleY),
          linePaint,
        )
        ..drawLine(
          Offset(28, bassY),
          Offset(size.width - 12, bassY),
          linePaint,
        );
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${measure.ordinal}',
        style: const TextStyle(fontSize: 11, color: LuxuryPalette.textSubtle),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(8, 4));

    final notePaint = Paint()..color = LuxuryPalette.textPrimary;
    for (final note in measure.notes) {
      if (note.isRest || note.diatonic == null) continue;
      final bottom = note.staff == 2 ? bassBottom : trebleBottom;
      final origin = note.staff == 2 ? 18 : 30;
      final steps = note.diatonic! - origin;
      final y = bottom - steps * (lineGap / 2);
      final x =
          36 +
          (note.startDivisions / measure.lengthDivisions) * (size.width - 64);
      if (steps < 0 || steps > 8) {
        final ledgerY = bottom - (steps < 0 ? 0 : 8) * (lineGap / 2);
        canvas.drawLine(
          Offset(x - 7, steps < 0 ? bottom + lineGap : ledgerY - lineGap),
          Offset(x + 7, steps < 0 ? bottom + lineGap : ledgerY - lineGap),
          linePaint,
        );
      }
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 9, height: 7),
        notePaint,
      );
      if (note.alter != 0) {
        final accidental = TextPainter(
          text: TextSpan(
            text: note.alter > 0 ? '♯' : '♭',
            style: const TextStyle(
              fontSize: 11,
              color: LuxuryPalette.goldBright,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        accidental.paint(canvas, Offset(x - 14, y - 8));
      }
    }
  }

  @override
  bool shouldRepaint(_MeasurePainter oldDelegate) =>
      !identical(oldDelegate.measure, measure);
}
