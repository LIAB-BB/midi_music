import 'package:flutter/cupertino.dart';

class ScoreZoomControls extends StatelessWidget {
  static const defaultZoom = 0.7;
  static const minZoom = 0.5;
  static const maxZoom = 1.4;
  static const step = 0.1;

  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  const ScoreZoomControls({
    super.key,
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  @override
  Widget build(BuildContext context) {
    final canZoomOut = zoom > minZoom + 0.001;
    final canZoomIn = zoom < maxZoom - 0.001;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2403640),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x4DF2DEAA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomButton(
            key: const Key('score-zoom-out'),
            icon: CupertinoIcons.minus,
            semanticLabel: '缩小乐谱',
            onPressed: canZoomOut ? onZoomOut : null,
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF2DEAA),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _ZoomButton(
            key: const Key('score-zoom-in'),
            icon: CupertinoIcons.plus,
            semanticLabel: '放大乐谱',
            onPressed: canZoomIn ? onZoomIn : null,
          ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  const _ZoomButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onPressed,
          child: Icon(
            icon,
            size: 19,
            color: onPressed == null
                ? const Color(0x66F2DEAA)
                : const Color(0xFFF2DEAA),
          ),
        ),
      ),
    );
  }
}
