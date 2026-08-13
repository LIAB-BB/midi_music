import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:midi_music/app.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/settings/app_settings.dart';

void main() {
  testWidgets('App smoke test — renders without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
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

    expect(find.text('导入乐谱文件'), findsOneWidget);
    expect(find.text('乐谱广场'), findsWidgets);
    expect(find.byKey(const Key('score-masonry-grid')), findsOneWidget);
  });

  testWidgets('Home page shows score waterfall and filters categories', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
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

    expect(find.byKey(const Key('score-card-2')), findsOneWidget);
    expect(find.text('月光奏鸣曲 第一乐章'), findsOneWidget);
    expect(find.text('深夜爵士小品'), findsOneWidget);

    await tester.tap(find.byKey(const Key('score-category-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('score-category-爵士')));
    await tester.pumpAndSettle();

    expect(find.text('深夜爵士小品'), findsOneWidget);
    expect(find.text('黑键即兴'), findsOneWidget);
    expect(find.text('月光奏鸣曲 第一乐章'), findsNothing);
  });

  testWidgets('Score card opens practice reader page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
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

    await tester.tap(find.byKey(const Key('score-card-2')));
    await tester.pumpAndSettle();

    expect(find.text('月光奏鸣曲 第一乐章'), findsWidgets);
    expect(find.text('仅伴奏'), findsOneWidget);
    expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
    expect(find.byKey(const Key('midi-piano-roll')), findsNothing);
    expect(find.byKey(const Key('pdf-score-viewer')), findsNothing);
    expect(find.byKey(const Key('score-transport-bar')), findsOneWidget);
  });

  testWidgets('K.478 is presented as accompaniment only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
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

    await tester.tap(find.byKey(const Key('score-card-13')));
    await tester.pumpAndSettle();

    expect(find.text('仅伴奏'), findsOneWidget);
    expect(find.textContaining('PDF'), findsNothing);
    expect(find.byKey(const Key('interactive-score-view')), findsOneWidget);
    expect(find.byKey(const Key('pdf-score-viewer')), findsNothing);
    expect(find.byKey(const Key('midi-piano-roll')), findsNothing);
  });

  testWidgets('Settings page can be opened from home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
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

    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill));
    await tester.pumpAndSettle();

    expect(find.text('排练偏好'), findsOneWidget);
    expect(find.text('电子琴输入'), findsOneWidget);
  });
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
