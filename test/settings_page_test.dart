import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/settings/app_settings.dart';
import 'package:midi_music/ui/pages/settings_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('恢复默认等待写盘成功，失败时保留确认框并明确提示', (tester) async {
    final storage = _GatedFailingSettingsStorage();
    final settings = AppSettingsController(storage: storage);
    final player = MidiPlayerController();
    addTearDown(player.dispose);
    await settings.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: player),
        ],
        child: const CupertinoApp(home: SettingsPage()),
      ),
    );
    await tester.scrollUntilVisible(find.text('恢复默认'), 400);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await storage.writeStarted.future;
    final confirmStayedOpenWhileWriting = find
        .text('恢复默认设置？')
        .evaluate()
        .isNotEmpty;

    storage.releaseWrite.completeError(StateError('simulated reset failure'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(confirmStayedOpenWhileWriting, isTrue);
    expect(find.text('恢复默认失败'), findsOneWidget);
    expect(find.textContaining('原设置已保留'), findsOneWidget);
    expect(settings.defaultPlaybackSpeed, 2.5);
  });
}

class _GatedFailingSettingsStorage implements AppSettingsStorage {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<Map<String, Object?>> read() async => {
    'schemaVersion': AppSettingsController.settingsSchemaVersion,
    'defaultPlaybackSpeed': 2.5,
  };

  @override
  Future<void> write(Map<String, Object?> values) async {
    writeStarted.complete();
    await releaseWrite.future;
  }
}
