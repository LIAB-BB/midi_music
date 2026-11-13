import 'package:flutter/cupertino.dart';

import '../../core/notation/piece_score_alignment.dart';
import '../theme/luxury_theme.dart';
import 'player_helpers.dart';

/// 曲目包的小节轨。它显示时间表上的小节，不渲染五线谱。
class K478MeasureRail extends StatefulWidget {
  final PieceScoreAlignment alignment;
  final int currentOrdinal;
  final ValueChanged<int>? onMeasureSelected;

  const K478MeasureRail({
    super.key,
    required this.alignment,
    required this.currentOrdinal,
    this.onMeasureSelected,
  });

  @override
  State<K478MeasureRail> createState() => _K478MeasureRailState();
}

class _K478MeasureRailState extends State<K478MeasureRail> {
  static const _itemExtent = 48.0;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(K478MeasureRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentOrdinal != widget.currentOrdinal) {
      _scheduleScroll();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final index = (widget.currentOrdinal - 1).clamp(
        0,
        widget.alignment.measures.length - 1,
      );
      final viewport = _controller.position.viewportDimension;
      final target = index * _itemExtent - (viewport - _itemExtent) / 2;
      final max = _controller.position.maxScrollExtent;
      _controller.jumpTo(target.clamp(0.0, max));
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectionEnabled = widget.onMeasureSelected != null;
    return LuxuryPanel(
      key: const Key('k478-measure-rail'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionEyebrow(label: 'MEASURE'),
              const Spacer(),
              Text(
                '第 ${widget.currentOrdinal} 小节',
                key: const Key('k478-current-measure'),
                style: const TextStyle(
                  fontSize: 13,
                  color: LuxuryPalette.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selectionEnabled
                ? '点小节回到该小节起点。位置来自 MIDI，还不是五线谱翻页。'
                : '跟随进行中，小节只显示当前位置。',
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: LuxuryPalette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              itemExtent: _itemExtent,
              itemCount: widget.alignment.measures.length,
              itemBuilder: (context, index) {
                final ordinal = widget.alignment.measures[index].ordinal;
                final selected = ordinal == widget.currentOrdinal;
                return CupertinoButton(
                  key: Key('k478-measure-$ordinal'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                  onPressed: selectionEnabled
                      ? () => widget.onMeasureSelected!(ordinal)
                      : null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? LuxuryPalette.gold.withValues(alpha: 0.22)
                          : CupertinoColors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? LuxuryPalette.goldBright
                            : LuxuryPalette.divider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$ordinal',
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? LuxuryPalette.goldBright
                              : LuxuryPalette.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
