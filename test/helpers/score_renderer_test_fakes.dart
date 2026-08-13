import 'package:midi_music/core/score/score_playback_coordinator.dart';

class RecordingRendererPort implements ScoreRendererPort {
  final List<String> loadedXml = [];
  final List<int> highlighted = [];
  final List<bool> scrollFlags = [];
  int clearCount = 0;

  @override
  Future<void> loadMusicXml(String musicXml) {
    loadedXml.add(musicXml);
    return Future<void>.value();
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    highlighted.add(ordinal);
    scrollFlags.add(scrollIntoView);
    return Future<void>.value();
  }

  @override
  Future<void> clearHighlight() {
    clearCount += 1;
    return Future<void>.value();
  }
}
