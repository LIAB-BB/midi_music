import '../midi/midi_player.dart';

abstract class FollowPlaybackTarget {
  bool get isPlaying;
  double get speed;

  Future<void> play();
  Future<void> pause();
  Future<void> setSpeed(double speed);
}

class MidiFollowPlaybackTarget implements FollowPlaybackTarget {
  final MidiPlayerController player;

  const MidiFollowPlaybackTarget(this.player);

  @override
  bool get isPlaying => player.isPlaying;

  @override
  double get speed => player.playbackSpeed;

  @override
  Future<void> play() async {
    player.play();
  }

  @override
  Future<void> pause() async {
    player.pause();
  }

  @override
  Future<void> setSpeed(double speed) async {
    player.setSpeed(speed);
  }
}
