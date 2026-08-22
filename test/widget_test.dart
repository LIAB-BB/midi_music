import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:midi_music/app.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/settings/app_settings.dart';

void main() {
  testWidgets('首页只暴露 K.478 的 USB MIDI 试用入口', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('K.478 排练'), findsWidgets);
    expect(find.text('钢琴四重奏\nK.478'), findsOneWidget);
    expect(find.byKey(const Key('start-k478-usb-practice')), findsOneWidget);
    expect(find.byKey(const Key('view-k478-pdf-score')), findsOneWidget);
    expect(find.text('导入乐谱文件'), findsNothing);
    expect(find.text('月光奏鸣曲 第一乐章'), findsNothing);
    expect(find.textContaining('MusicXML'), findsOneWidget);
  });

  testWidgets('开始按钮载入内置 K.478 并进入演奏台', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('start-k478-usb-practice')));
    await tester.pumpAndSettle();

    expect(find.text('mozart k478 piano quartet'), findsWidgets);
    expect(find.byKey(const Key('midi-piano-roll')), findsOneWidget);
  });

  testWidgets('分谱入口打开 K.478 离线页面阅读器', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('view-k478-pdf-score')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pdf-score-viewer')), findsOneWidget);
    expect(find.text('K.478 钢琴分谱'), findsOneWidget);
    expect(find.text('1 / 21'), findsOneWidget);
  });

  testWidgets('设置页说明不采集麦克风', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill));
    await tester.pumpAndSettle();

    expect(find.text('排练偏好'), findsOneWidget);
    expect(find.text('电子琴输入'), findsOneWidget);
    expect(find.textContaining('不采集麦克风音频'), findsOneWidget);
  });
}

Future<void> _pumpApp(WidgetTester tester) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              AppSettingsController(storage: _MemorySettingsStorage()),
        ),
        ChangeNotifierProvider(create: (_) => MidiPlayerController()),
      ],
      child: const MidiMusicApp(),
    ),
  );
}

class _MemorySettingsStorage implements AppSettingsStorage {
  Map<String, Object?> values = {};

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    this.values = Map<String, Object?>.from(values);
  }
}
