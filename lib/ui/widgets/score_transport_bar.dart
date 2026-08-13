import 'package:flutter/cupertino.dart';

import '../../core/midi/midi_player.dart';

class ScoreTransportBar extends StatefulWidget {
  final MidiPlayerController player;
  final VoidCallback onPlaybackInteraction;

  const ScoreTransportBar({
    super.key,
    required this.player,
    required this.onPlaybackInteraction,
  });

  @override
  State<ScoreTransportBar> createState() => _ScoreTransportBarState();
}

class _ScoreTransportBarState extends State<ScoreTransportBar> {
  static const _foregroundColor = Color(0xFFF2DEAA);
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_handlePlayerChanged);
  }

  @override
  void didUpdateWidget(covariant ScoreTransportBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.player, widget.player)) return;
    oldWidget.player.removeListener(_handlePlayerChanged);
    widget.player.addListener(_handlePlayerChanged);
  }

  @override
  void dispose() {
    widget.player.removeListener(_handlePlayerChanged);
    super.dispose();
  }

  void _handlePlayerChanged() {
    if (mounted) setState(() {});
  }

  void _previousMeasure() {
    widget.player.seekToPreviousMeasure();
    widget.onPlaybackInteraction();
  }

  void _togglePlayback() {
    if (widget.player.isPlaying) {
      widget.player.pause();
    } else {
      widget.player.play();
    }
    widget.onPlaybackInteraction();
  }

  void _nextMeasure() {
    widget.player.seekToNextMeasure();
    widget.onPlaybackInteraction();
  }

  void _setAbLoop() {
    final player = widget.player;
    final start = player.loopStartTime;
    final end = player.loopEndTime;
    if (start == null) {
      player.setLoopStart(player.currentTime);
      return;
    }
    if (end == null) {
      if (player.currentTime <= start) return;
      player.setLoopEnd(player.currentTime);
      player.setLoopEnabled(enabled: true);
      return;
    }
    player.clearLoop();
  }

  Future<void> _chooseSpeed() async {
    final speed = await showCupertinoModalPopup<double>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('播放速度'),
        actions: [
          for (final speed in _speeds)
            CupertinoActionSheetAction(
              isDefaultAction: widget.player.playbackSpeed == speed,
              onPressed: () => Navigator.of(context).pop(speed),
              child: Text('${speed}x'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (speed != null) widget.player.setSpeed(speed);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return ColoredBox(
      color: const Color(0xFF403640),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 84,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TransportButton(
                key: const Key('score-speed'),
                icon: CupertinoIcons.speedometer,
                label: '${player.playbackSpeed}x',
                onPressed: _chooseSpeed,
              ),
              _TransportButton(
                key: const Key('score-previous-measure'),
                icon: CupertinoIcons.backward_end_fill,
                onPressed: _previousMeasure,
              ),
              CupertinoButton(
                key: const Key('score-play-pause'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(58, 58),
                onPressed: _togglePlayback,
                child: Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: CupertinoColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    player.isPlaying
                        ? CupertinoIcons.pause_fill
                        : CupertinoIcons.play_fill,
                    size: 28,
                    color: const Color(0xFF403640),
                  ),
                ),
              ),
              _TransportButton(
                key: const Key('score-next-measure'),
                icon: CupertinoIcons.forward_end_fill,
                onPressed: _nextMeasure,
              ),
              _TransportButton(
                key: const Key('score-ab-loop'),
                icon: CupertinoIcons.repeat,
                label: player.loopStartTime == null
                    ? 'AB'
                    : (player.loopEndTime == null ? 'A' : 'AB'),
                selected: player.loopStartTime != null,
                onPressed: _setAbLoop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final bool selected;
  final VoidCallback onPressed;

  const _TransportButton({
    super.key,
    required this.icon,
    this.label,
    this.selected = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: selected
                ? CupertinoColors.white
                : _ScoreTransportBarState._foregroundColor,
          ),
          if (label case final label?) ...[
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? CupertinoColors.white
                    : _ScoreTransportBarState._foregroundColor,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
