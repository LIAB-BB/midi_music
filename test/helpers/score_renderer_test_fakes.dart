import 'dart:async';

import 'package:midi_music/core/score/score_renderer_port.dart';

class RecordingRendererPort implements ScoreRendererPort {
  final List<String> loadedXml = [];
  final List<double> zoomLevels = [];
  final List<String> operations = [];
  final List<int> highlighted = [];
  final List<bool> scrollFlags = [];
  int clearCount = 0;

  @override
  Future<void> loadMusicXml(String musicXml) {
    loadedXml.add(musicXml);
    operations.add('load');
    return Future<void>.value();
  }

  @override
  Future<void> setZoom(double zoom) {
    zoomLevels.add(zoom);
    operations.add('zoom:$zoom');
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

class ControllableRendererPort implements ScoreRendererPort {
  final List<String> loadedXml = [];
  final List<double> zoomLevels = [];
  final List<int> highlighted = [];
  final List<bool> scrollFlags = [];
  final List<Completer<void>> highlightCompleters = [];
  final List<Completer<void>> clearCompleters = [];
  int clearCount = 0;

  @override
  Future<void> loadMusicXml(String musicXml) {
    loadedXml.add(musicXml);
    return Future<void>.value();
  }

  @override
  Future<void> setZoom(double zoom) {
    zoomLevels.add(zoom);
    return Future<void>.value();
  }

  @override
  Future<void> highlightMeasure(int ordinal, {required bool scrollIntoView}) {
    highlighted.add(ordinal);
    scrollFlags.add(scrollIntoView);
    final completer = Completer<void>();
    highlightCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<void> clearHighlight() {
    clearCount += 1;
    final completer = Completer<void>();
    clearCompleters.add(completer);
    return completer.future;
  }
}
