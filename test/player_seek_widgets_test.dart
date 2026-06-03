import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/follow/follow_mode_controller.dart';
import 'package:midi_music/core/midi/midi_engine.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/ui/widgets/player_helpers.dart';
import 'package:midi_music/ui/widgets/stage_console.dart';
import 'package:midi_music/ui/widgets/track_salon.dart';
import 'package:midi_music/ui/widgets/transport_deck.dart';

void main() {
  testWidgets('StageConsole 进度条 seek 会走外部回调', (tester) async {
    final player = _readyPlayer();
    final seeks = <double>[];

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: StageConsole(
              player: player,
              isFollowMode: false,
              followState: FollowModeState.idle,
              followSpeedFactor: 1,
              onSeek: seeks.add,
            ),
          ),
        ),
      ),
    );

    final slider = tester.widget<CupertinoSlider>(
      find.byKey(PlayerUiKeys.stageProgressSlider),
    );
    slider.onChanged!(0.5);

    expect(seeks, [5.0]);

    player.dispose();
  });

  testWidgets('TransportDeck seek 按钮会走外部回调', (tester) async {
    final player = _readyPlayer();
    player.seekTo(4);
    final seeks = <double>[];

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: TransportDeck(player: player, onSeek: seeks.add),
        ),
      ),
    );

    await tester.tap(find.byKey(PlayerUiKeys.transportForwardButton));

    expect(seeks, [14.0]);

    player.dispose();
  });

  testWidgets('TrackSalon 暴露稳定轨道控制 Key', (tester) async {
    final player = _readyPlayer();

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: TrackSalon(
            player: player,
            melodyTrackIndex: 0,
            onSetMelody: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(PlayerUiKeys.trackTile(0)), findsOneWidget);
    expect(find.byKey(PlayerUiKeys.trackMuteButton(0)), findsOneWidget);
    expect(find.byKey(PlayerUiKeys.trackMelodyButton(0)), findsOneWidget);
    expect(find.byKey(PlayerUiKeys.trackVolumeSlider(0)), findsOneWidget);

    player.dispose();
  });
}

MidiPlayerController _readyPlayer() {
  final player = MidiPlayerController(engine: _ReadyMidiPlaybackEngine());
  player.loadSong(
    MidiSongData(
      fileName: 'seek-test.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [
        MidiTrackInfo(
          index: 0,
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 80,
              channel: 0,
              startTick: 0,
              endTick: 480,
              startTime: 0,
              endTime: 1,
            ),
          ],
        ),
      ],
      timeline: const [],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: const [],
      totalTicks: 4800,
      totalDuration: 10,
    ),
  );
  return player;
}

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
