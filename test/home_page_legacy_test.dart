import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/settings/app_settings.dart';
import 'package:midi_music/ui/pages/home_page_legacy.dart' as legacy;

void main() {
  testWidgets('旧曲库和导入首页保留为未接入的后续能力', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) =>
                AppSettingsController(storage: _MemorySettingsStorage()),
          ),
          ChangeNotifierProvider(create: (_) => MidiPlayerController()),
        ],
        child: const CupertinoApp(home: legacy.ScoreLibraryPage()),
      ),
    );

    expect(find.text('导入乐谱文件'), findsOneWidget);
    expect(find.byKey(const Key('score-masonry-grid')), findsOneWidget);
    expect(find.text('月光奏鸣曲 第一乐章'), findsOneWidget);

    await tester.tap(find.byKey(const Key('score-category-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('score-category-爵士')));
    await tester.pumpAndSettle();

    expect(find.text('深夜爵士小品'), findsOneWidget);
    expect(find.text('月光奏鸣曲 第一乐章'), findsNothing);
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
