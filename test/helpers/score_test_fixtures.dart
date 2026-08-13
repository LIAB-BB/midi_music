import 'dart:io';

import 'package:midi_music/core/import/musicxml_parser.dart';
import 'package:midi_music/core/midi/midi_engine.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/models/score_session.dart';

MidiPlayerController readyPlayer() =>
    MidiPlayerController(engine: _ReadyMidiPlaybackEngine());

ScoreSession interactiveSession() {
  final xml = File(
    'test/fixtures/interactive_score.musicxml',
  ).readAsStringSync();
  return MusicXmlParser()
      .parseDocumentString(xml, fileName: 'interactive_score.musicxml')
      .toSession(ScoreSourceType.musicXml);
}

ScoreSession partialSession() {
  final session = interactiveSession();
  return ScoreSession(
    songData: session.songData,
    musicXml: session.musicXml,
    sourceType: session.sourceType,
    measures: [
      session.measures.first,
      ScoreMeasureBoundary(
        ordinal: session.measures[1].ordinal,
        label: session.measures[1].label,
        startTick: session.measures[1].startTick,
        endTick: session.measures[1].endTick,
        isInteractive: false,
      ),
    ],
    mappingStatus: ScoreMappingStatus.partial,
    warnings: session.warnings,
  );
}

ScoreSession midiOnlySession() =>
    ScoreSession.midiOnly(interactiveSession().songData);

class _ReadyMidiPlaybackEngine implements MidiPlaybackEngine {
  @override
  bool get isReady => true;

  @override
  Future<void> allNotesOff() => Future<void>.value();

  @override
  Future<void> dispose() => Future<void>.value();

  @override
  Future<void> loadSoundfontFromAsset(String assetPath) => Future<void>.value();

  @override
  Future<void> loadSoundfontFromFile(String filePath) => Future<void>.value();

  @override
  Future<void> noteOff({required int channel, required int note}) =>
      Future<void>.value();

  @override
  Future<void> noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) => Future<void>.value();

  @override
  Future<void> setInstrument({
    required int channel,
    required int program,
    int bank = 0,
  }) => Future<void>.value();

  @override
  Future<void> waitForPendingOperations() => Future<void>.value();
}
