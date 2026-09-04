import '../../models/score_session.dart';
import '../midi/midi_player.dart';
import 'score_playback_port.dart';

/// 将完整 MIDI 播放器收窄为交互谱面协调器所需的播放端口。
class MidiPlayerScorePlaybackAdapter implements ScorePlaybackPort {
  final MidiPlayerController player;

  const MidiPlayerScorePlaybackAdapter(this.player);

  @override
  ScoreSession? get scoreSession => player.scoreSession;

  @override
  int? get currentMeasureOrdinal => player.currentMeasureOrdinal;

  @override
  bool seekToMeasure(int ordinal) => player.seekToMeasure(ordinal);
}
