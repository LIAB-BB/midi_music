import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:midi_music/core/notation/midi_to_musicxml_converter.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生产 InteractiveScoreView 使用本地 OSMD 渲染生成谱面', (tester) async {
    final cases = _renderCases();
    for (final entry in cases.entries) {
      final finished = Completer<void>();
      var receivedReady = false;
      var receivedLayout = false;

      await tester.pumpWidget(
        CupertinoApp(
          home: InteractiveScoreView(
            key: ValueKey<String>(entry.key),
            musicXml: entry.value,
            onMessage: (message) {
              switch (message.type) {
                case ScoreRendererMessageType.ready:
                  receivedReady = true;
                case ScoreRendererMessageType.layout:
                  if (!message.layoutComplete) return;
                  if (message.measureRects.isEmpty) {
                    if (!finished.isCompleted) {
                      finished.completeError(
                        StateError('${entry.key} 返回空小节布局'),
                      );
                    }
                    return;
                  }
                  receivedLayout = true;
                case ScoreRendererMessageType.error:
                  if (!finished.isCompleted) {
                    finished.completeError(
                      StateError(
                        '${entry.key} OSMD 错误: ${message.errorMessage}',
                      ),
                    );
                  }
                case ScoreRendererMessageType.gestureEnd:
                  break;
              }
              if (receivedReady && receivedLayout && !finished.isCompleted) {
                finished.complete();
              }
            },
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => finished.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            '${entry.key} 在 15 秒内未收到 ready 与非空 layout',
          ),
        ),
      );
      expect(receivedReady, isTrue, reason: entry.key);
      expect(receivedLayout, isTrue, reason: entry.key);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  }, skip: !Platform.isIOS);
}

Map<String, String> _renderCases() => {
  'dotted-triplet-tie': _convert(
    tracks: [
      _track(0, 'Violin', 0, [
        _note(60, 0, 0, 720),
        _note(62, 0, 960, 1280),
        _note(67, 0, 1800, 2100),
      ]),
    ],
    parts: [
      _part(
        id: 'source:0:0',
        label: 'Violin',
        kind: MidiPartKind.strings,
        sources: [
          MidiPartSource(trackIndex: 0, channels: {0}),
        ],
        noteCount: 3,
      ),
    ],
    totalTicks: 3840,
  ),
  'multi-voice': _convert(
    tracks: [
      _track(0, 'Polyphony', 0, [
        _note(60, 0, 0, 1000),
        _note(62, 0, 120, 1120),
        _note(64, 0, 240, 1240),
        _note(65, 0, 360, 1360),
      ]),
    ],
    parts: [
      _part(
        id: 'source:0:0',
        label: 'Polyphony',
        kind: MidiPartKind.strings,
        sources: [
          MidiPartSource(trackIndex: 0, channels: {0}),
        ],
        noteCount: 4,
      ),
    ],
    totalTicks: 1920,
  ),
  'grand-staff': _convert(
    tracks: [
      _track(0, 'Upper', 0, [_note(72, 0, 480, 960)]),
      _track(1, 'Lower', 1, [_note(43, 1, 0, 960)]),
    ],
    parts: [
      _part(
        id: 'piano:0:0,1:1',
        label: 'Piano',
        kind: MidiPartKind.piano,
        sources: [
          MidiPartSource(trackIndex: 0, channels: {0}),
          MidiPartSource(trackIndex: 1, channels: {1}),
        ],
        noteCount: 2,
        staffMode: MidiStaffMode.grandStaff,
      ),
    ],
    totalTicks: 1920,
  ),
  'percussion': _convert(
    tracks: [
      _track(0, 'Drums', 9, [_note(36, 9, 0, 240), _note(42, 9, 480, 720)]),
    ],
    parts: [
      _part(
        id: 'source:0:9',
        label: 'Drums',
        kind: MidiPartKind.percussion,
        sources: [
          MidiPartSource(trackIndex: 0, channels: {9}),
        ],
        noteCount: 2,
        staffMode: MidiStaffMode.percussionStaff,
      ),
    ],
    totalTicks: 1920,
  ),
};

String _convert({
  required List<MidiTrackInfo> tracks,
  required List<MidiScorePart> parts,
  required int totalTicks,
}) {
  final song = MidiSongData(
    fileName: 'osmd-smoke.mid',
    format: 1,
    ticksPerBeat: 480,
    tracks: tracks,
    timeline: const [],
    tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
    timeSignatureChanges: [
      TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
    ],
    totalTicks: totalTicks,
    totalDuration: totalTicks / 960,
  );
  final catalog = MidiScoreCatalog(
    fingerprint: 'osmd-smoke',
    parts: parts,
    recommendedPartIds: parts.map((part) => part.id).toSet(),
    recommendedOrigin: MidiSelectionOrigin.automaticEnsemble,
  );
  return MidiToMusicXmlConverter()
      .convertSync(
        song,
        catalog: catalog,
        selectedPartIds: catalog.recommendedPartIds,
      )
      .musicXml;
}

MidiScorePart _part({
  required String id,
  required String label,
  required MidiPartKind kind,
  required List<MidiPartSource> sources,
  required int noteCount,
  MidiStaffMode staffMode = MidiStaffMode.singleStaff,
}) => MidiScorePart(
  id: id,
  label: label,
  kind: kind,
  sources: sources,
  noteCount: noteCount,
  staffMode: staffMode,
);

MidiTrackInfo _track(
  int index,
  String name,
  int channel,
  List<MidiNote> notes,
) => MidiTrackInfo(
  index: index,
  name: name,
  channels: {channel},
  programByChannel: {channel: channel == 9 ? 0 : 40},
  notes: notes,
);

MidiNote _note(int noteNumber, int channel, int startTick, int endTick) =>
    MidiNote(
      noteNumber: noteNumber,
      velocity: 96,
      channel: channel,
      startTick: startTick,
      endTick: endTick,
    );
