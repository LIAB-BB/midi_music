import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:midi_music/core/notation/midi_to_musicxml_converter.dart';
import 'package:midi_music/core/score/score_renderer_port.dart';
import 'package:midi_music/core/score/score_renderer_protocol.dart';
import 'package:midi_music/models/midi_score_part.dart';
import 'package:midi_music/models/midi_track.dart';
import 'package:midi_music/ui/widgets/interactive_score_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生产 InteractiveScoreView 使用本地 OSMD 渲染生成谱面', (tester) async {
    final cases = _renderCases();
    for (final entry in cases.entries) {
      final renderCase = entry.value;
      final result = renderCase.result;
      final expectedOrdinals = result.measures
          .map((measure) => measure.ordinal)
          .toList(growable: false);
      expect(
        expectedOrdinals,
        List<int>.generate(result.measures.length, (index) => index + 1),
        reason: '${entry.key} 转换结果小节序号',
      );
      for (final construct in renderCase.expectedXmlConstructs) {
        expect(result.musicXml, contains(construct), reason: entry.key);
      }
      final finished = Completer<void>();
      var receivedReady = false;
      var receivedLayout = false;
      var renderedOrdinals = <int>[];
      var renderedRects = <ScoreMeasureRect>[];
      Completer<void>? nextLayoutFinished;
      late ScoreRendererPort rendererPort;

      void handleMessage(ScoreRendererMessage message) {
        switch (message.type) {
          case ScoreRendererMessageType.ready:
            receivedReady = true;
          case ScoreRendererMessageType.layout:
            if (!message.layoutComplete) return;
            renderedRects = message.measureRects;
            renderedOrdinals = message.measureRects
                .map((rect) => rect.ordinal)
                .toList(growable: false);
            if (!_sameOrdinals(renderedOrdinals, expectedOrdinals)) {
              final error = StateError(
                '${entry.key} 小节布局序号不匹配: '
                '$renderedOrdinals != $expectedOrdinals',
              );
              if (nextLayoutFinished case final next? when !next.isCompleted) {
                next.completeError(error);
              } else if (!finished.isCompleted) {
                finished.completeError(error);
              }
              return;
            }
            receivedLayout = true;
            if (nextLayoutFinished case final next? when !next.isCompleted) {
              next.complete();
            }
          case ScoreRendererMessageType.error:
            final error = StateError(
              '${entry.key} OSMD 错误: ${message.errorMessage}',
            );
            if (nextLayoutFinished case final next? when !next.isCompleted) {
              next.completeError(error);
            } else if (!finished.isCompleted) {
              finished.completeError(error);
            }
          case ScoreRendererMessageType.gestureEnd:
            break;
        }
        if (receivedReady && receivedLayout && !finished.isCompleted) {
          finished.complete();
        }
      }

      Widget buildScore({double? width}) {
        final score = InteractiveScoreView(
          key: ValueKey<String>(entry.key),
          musicXml: result.musicXml,
          zoom: 0.7,
          onMessage: handleMessage,
          onPortReady: (port) => rendererPort = port,
        );
        return CupertinoApp(
          home: width == null
              ? score
              : Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: width, child: score),
                ),
        );
      }

      await tester.pumpWidget(buildScore());
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
      expect(renderedOrdinals, expectedOrdinals, reason: entry.key);
      final scoreWidth = tester
          .getSize(find.byKey(const Key('interactive-score-webview')))
          .width;
      final furthestRight = renderedRects
          .map((rect) => rect.left + rect.width)
          .reduce((left, right) => left > right ? left : right);
      expect(
        furthestRight,
        greaterThan(scoreWidth * 0.65),
        reason: '${entry.key} 70% 缩放的小节 rect 必须使用 WebView 文档 CSS 坐标',
      );

      if (entry.key == 'dotted-triplet-tie') {
        final initialBottom = renderedRects
            .map((rect) => rect.top + rect.height)
            .reduce((top, bottom) => top > bottom ? top : bottom);
        nextLayoutFinished = Completer<void>();
        await rendererPort.setZoom(0.5);
        await tester.runAsync(
          () => nextLayoutFinished!.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw TimeoutException('OSMD 缩放后 15 秒内未收到 complete layout'),
          ),
        );
        final zoomedBottom = renderedRects
            .map((rect) => rect.top + rect.height)
            .reduce((top, bottom) => top > bottom ? top : bottom);
        expect(renderedOrdinals, expectedOrdinals);
        expect(
          zoomedBottom,
          lessThan(initialBottom * 0.9),
          reason: '50% 必须比 70% 产生更紧凑的纵向谱面',
        );

        final surface = find.byKey(const Key('interactive-score-webview'));
        nextLayoutFinished = Completer<void>();
        final resizedWidth = scoreWidth * 0.72;
        await tester.pumpWidget(buildScore(width: resizedWidth));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await nextLayoutFinished!.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
              'WebView resize 后 15 秒内未收到 complete layout',
            ),
          );
        });
        final actualResizedWidth = tester.getSize(surface).width;
        final resizedFurthestRight = renderedRects
            .map((rect) => rect.left + rect.width)
            .reduce((left, right) => left > right ? left : right);
        expect(
          resizedFurthestRight,
          greaterThan(actualResizedWidth * 0.75),
          reason: 'resize 后 rect 必须重新映射到新的 CSS 宽度',
        );
        expect(
          resizedFurthestRight,
          lessThan(furthestRight - 20),
          reason: 'resize 后必须发布新 layout，不能沿用旧坐标',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  }, skip: !Platform.isIOS);

  testWidgets('真实 WKWebView 的非首小节点击与 layout 使用同一文档坐标', (tester) async {
    final renderCase = _renderCases()['dotted-triplet-tie']!;
    var layoutFinished = Completer<ScoreRendererMessage>();
    var gestureFinished = Completer<ScoreRendererMessage>();
    var completeLayoutCount = 0;
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'ScoreBridge',
      onMessageReceived: (raw) {
        final message = ScoreRendererMessage.parse(raw.message);
        switch (message.type) {
          case ScoreRendererMessageType.layout:
            if (message.layoutComplete && !layoutFinished.isCompleted) {
              completeLayoutCount += 1;
              layoutFinished.complete(message);
            } else if (message.layoutComplete) {
              completeLayoutCount += 1;
            }
          case ScoreRendererMessageType.gestureEnd:
            if (!gestureFinished.isCompleted) {
              gestureFinished.complete(message);
            }
          case ScoreRendererMessageType.error:
            final error = StateError('OSMD bridge 错误: ${message.errorMessage}');
            if (!layoutFinished.isCompleted) {
              layoutFinished.completeError(error);
            }
            if (!gestureFinished.isCompleted) {
              gestureFinished.completeError(error);
            }
          case ScoreRendererMessageType.ready:
            break;
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (!url.endsWith('/assets/score_renderer/index.html')) return;
          final encoded = base64Encode(utf8.encode(renderCase.result.musicXml));
          unawaited(
            controller.runJavaScript(
              'window.scoreBridge.setZoom(0.7, 1);'
              'window.scoreBridge.loadMusicXmlBase64(${jsonEncode(encoded)})',
            ),
          );
        },
      ),
    );
    await controller.loadFlutterAsset('assets/score_renderer/index.html');

    await tester.pumpWidget(
      CupertinoApp(
        home: WebViewWidget(
          key: const Key('gesture-contract-webview'),
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    final layout = (await tester.runAsync(
      () => layoutFinished.future.timeout(const Duration(seconds: 15)),
    ))!;
    final target = layout.measureRects[1];

    await controller.runJavaScript('''
      (() => {
        const target = document.querySelector('[data-ordinal="2"]');
        if (!target) throw new Error('找不到第二小节 overlay');
        const rect = target.getBoundingClientRect();
        const options = {
          bubbles: true,
          pointerId: 1,
          isPrimary: true,
          clientX: rect.left + rect.width / 2,
          clientY: rect.top + rect.height / 2,
        };
        document.dispatchEvent(new PointerEvent('pointerdown', options));
        document.dispatchEvent(new PointerEvent('pointerup', options));
      })();
    ''');
    final gesture = (await tester.runAsync(
      () => gestureFinished.future.timeout(const Duration(seconds: 5)),
    ))!;

    expect(
      target.contains(gesture.tapX!, gesture.tapY!),
      isTrue,
      reason: 'gestureEnd 必须命中第二小节的 published layout rect',
    );
    expect(gesture.gesturePointerCount, 1);
    expect(gesture.gestureTravel, 0);

    layoutFinished = Completer<ScoreRendererMessage>();
    gestureFinished = Completer<ScoreRendererMessage>();
    await controller.runJavaScript('window.scoreBridge.setZoom(0.5, 2)');
    final zoomedLayout = (await tester.runAsync(
      () => layoutFinished.future.timeout(const Duration(seconds: 15)),
    ))!;
    final zoomedTarget = zoomedLayout.measureRects[1];
    await controller.runJavaScript('''
      (() => {
        const target = document.querySelector('[data-ordinal="2"]');
        if (!target) throw new Error('缩放后找不到第二小节 overlay');
        const rect = target.getBoundingClientRect();
        const options = {
          bubbles: true,
          pointerId: 2,
          isPrimary: true,
          clientX: rect.left + rect.width / 2,
          clientY: rect.top + rect.height / 2,
        };
        document.dispatchEvent(new PointerEvent('pointerdown', options));
        document.dispatchEvent(new PointerEvent('pointerup', options));
      })();
    ''');
    final zoomedGesture = (await tester.runAsync(
      () => gestureFinished.future.timeout(const Duration(seconds: 5)),
    ))!;
    expect(
      zoomedTarget.contains(zoomedGesture.tapX!, zoomedGesture.tapY!),
      isTrue,
      reason: '50% 缩放后 gestureEnd 仍须命中第二小节的新 layout rect',
    );

    final layoutsBeforeBurst = completeLayoutCount;
    layoutFinished = Completer<ScoreRendererMessage>();
    await controller.runJavaScript('''
      window.scoreBridge.setZoom(0.6, 3);
      window.scoreBridge.setZoom(0.7, 4);
      window.scoreBridge.setZoom(0.5, 5);
    ''');
    await tester.runAsync(() async {
      await layoutFinished.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    expect(
      completeLayoutCount - layoutsBeforeBurst,
      1,
      reason: '连续点击缩放必须合并为最后一次 OSMD 全量重排，避免排版队列造成明显延迟',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isIOS);
}

Map<String, _RenderCase> _renderCases() => {
  'dotted-triplet-tie': _RenderCase(
    result: _convert(
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
    expectedXmlConstructs: const [
      '<dot/>',
      '<time-modification>',
      '<tie type="start"/>',
      '<tie type="stop"/>',
    ],
  ),
  'multi-voice': _RenderCase(
    result: _convert(
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
    expectedXmlConstructs: const ['<voice>4</voice>', '<backup>'],
  ),
  'grand-staff': _RenderCase(
    result: _convert(
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
    expectedXmlConstructs: const [
      '<staves>2</staves>',
      '<clef number="1">',
      '<clef number="2">',
    ],
  ),
  'percussion': _RenderCase(
    result: _convert(
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
    expectedXmlConstructs: const ['<sign>percussion</sign>', '<unpitched>'],
  ),
};

MidiNotationResult _convert({
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
  return MidiToMusicXmlConverter().convertSync(
    song,
    catalog: catalog,
    selectedPartIds: catalog.recommendedPartIds,
  );
}

class _RenderCase {
  final MidiNotationResult result;
  final List<String> expectedXmlConstructs;

  const _RenderCase({
    required this.result,
    required this.expectedXmlConstructs,
  });
}

bool _sameOrdinals(List<int> actual, List<int> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
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
