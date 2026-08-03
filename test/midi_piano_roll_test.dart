import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/ui/widgets/midi_piano_roll.dart';

void main() {
  testWidgets('真实 MIDI 钢琴卷帘绘制解析音符', (tester) async {
    final song = MidiSongData(
      fileName: 'roll-test.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: [
        MidiTrackInfo(
          index: 0,
          name: 'Piano',
          notes: [
            MidiNote(
              noteNumber: 60,
              velocity: 96,
              channel: 0,
              startTick: 0,
              endTick: 480,
              startTime: 0,
              endTime: 0.5,
            ),
            MidiNote(
              noteNumber: 64,
              velocity: 88,
              channel: 0,
              startTick: 480,
              endTick: 960,
              startTime: 0.5,
              endTime: 1,
            ),
          ],
        ),
      ],
      timeline: [],
      tempoChanges: [],
      timeSignatureChanges: [],
      totalTicks: 960,
      totalDuration: 1,
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(
            width: 360,
            height: 260,
            child: MidiPianoRoll(
              song: song,
              currentTime: 0.25,
              accent: CupertinoColors.systemPurple,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('midi-piano-roll')), findsOneWidget);
    expect(find.text('真实 MIDI 钢琴卷帘'), findsOneWidget);
    expect(find.text('1 轨 · 1 秒'), findsOneWidget);
  });
}
