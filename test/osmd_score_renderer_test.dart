import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/score/osmd_score_renderer.dart';
import 'package:midi_music/core/score/score_playback_coordinator.dart';
import 'package:midi_music/core/score/score_playback_port.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/models/score_session.dart';

void main() {
  test('刻谱页只允许本地页面，拒绝外部地址', () {
    expect(
      osmdNavigationAllowed(
        'https://appassets.androidplatform.net/flutter_assets/assets/score_renderer/index.html',
      ),
      isTrue,
    );
    expect(osmdNavigationAllowed('about:blank'), isTrue);
    expect(
      osmdNavigationAllowed(
        'https://cdn.jsdelivr.net/npm/opensheetmusicdisplay',
      ),
      isFalse,
    );
    expect(osmdNavigationAllowed('http://example.com/osmd.min.js'), isFalse);
  });

  test('本地刻谱资源固定版本且页面不发起连接', () {
    final library = File(osmdLibraryAsset).readAsBytesSync();
    final page = File(osmdPageAsset).readAsStringSync();
    expect(sha256.convert(library).toString(), osmdLibrarySha256);
    expect(page, contains("default-src 'none'"));
    expect(page, contains("connect-src 'none'"));
    expect(page.contains('http:'), isFalse);
    expect(page.contains('https:'), isFalse);
    expect(
      File(
        'assets/score_renderer/opensheetmusicdisplay.min.js.LICENSE.txt',
      ).readAsStringSync(),
      contains('Redistribution and use'),
    );
  });

  test('库尚未就绪时排队 MusicXML，布局消息会驱动跳转', () async {
    final scripts = <String>[];
    ScorePlaybackCoordinator? coordinator;
    final renderer = OsmdScoreRenderer(
      runJavaScript: (source) async {
        scripts.add(source);
      },
      onMessage: (message) {
        coordinator?.handleMessage(message);
      },
    );
    final player = _FakePlayer();
    coordinator = ScorePlaybackCoordinator(player: player, port: renderer);

    await renderer.loadMusicXml('<score/>');
    expect(scripts, isEmpty);
    await renderer.markLibraryReady();
    expect(scripts.single, contains('<score/>'));

    renderer.handleRawMessage(
      jsonEncode({
        'type': 'layout',
        'complete': true,
        'measures': [
          {'ordinal': 1, 'left': 0, 'top': 0, 'width': 20, 'height': 10},
        ],
      }),
    );
    renderer.handleRawMessage(
      jsonEncode({
        'type': 'gestureEnd',
        'x': 4,
        'y': 4,
        'travel': 0,
        'durationMs': 40,
        'pointerCount': 1,
      }),
    );
    expect(player.sought, [1]);
  });
}

class _FakePlayer implements ScorePlaybackPort {
  final sought = <int>[];

  @override
  ScoreSession? scoreSession = ScoreSession(
    songData: MidiSongData(
      fileName: 'x.mid',
      format: 1,
      ticksPerBeat: 480,
      tracks: const [],
      timeline: const [],
      tempoChanges: [TempoChange(tick: 0, microsecondsPerBeat: 500000)],
      timeSignatureChanges: [
        TimeSignatureChange(tick: 0, numerator: 4, denominator: 4),
      ],
      totalTicks: 480,
      totalDuration: 1,
    ),
    sourceType: ScoreSourceType.midiNotation,
    musicXml: '<score/>',
    measures: const [
      ScoreMeasureBoundary(ordinal: 1, label: '1', startTick: 0, endTick: 10),
    ],
    mappingStatus: ScoreMappingStatus.complete,
  );

  @override
  int? currentMeasureOrdinal = 1;

  @override
  bool seekToMeasure(int ordinal) {
    sought.add(ordinal);
    currentMeasureOrdinal = ordinal;
    return true;
  }
}
