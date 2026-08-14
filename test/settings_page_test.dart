import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/core/settings/app_settings.dart';
import 'package:midi_music/ui/pages/settings_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('恢复失败关闭提示后可再次恢复并在成功后关闭确认框', (tester) async {
    final storage = _ControlledSettingsStorage();
    final settings = await _pumpSettingsPage(tester, storage);
    await _openResetDialog(tester);

    await tester.tap(find.text('恢复'));
    await _pumpUntilWriteCount(tester, storage, 1);
    storage.writes[0].completeError(StateError('simulated reset failure'));
    await _pumpUntilWriteCount(tester, storage, 2);
    storage.writes[1].complete();
    await tester.pumpAndSettle();

    expect(find.text('恢复默认失败'), findsOneWidget);
    expect(find.textContaining('原设置已保留'), findsOneWidget);
    expect(settings.defaultPlaybackSpeed, 2.5);

    await tester.tap(find.text('好的'));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认设置？'), findsOneWidget);

    await tester.tap(find.text('恢复'));
    await _pumpUntilWriteCount(tester, storage, 3);
    storage.writes[2].complete();
    await tester.pumpAndSettle();

    expect(find.text('恢复默认设置？'), findsNothing);
    expect(settings.defaultPlaybackSpeed, 1.0);
    expect(storage.values['defaultPlaybackSpeed'], 1.0);
  });

  testWidgets('恢复写盘 pending 时取消和重复恢复都不可触发', (tester) async {
    final storage = _ControlledSettingsStorage();
    await _pumpSettingsPage(tester, storage);
    await _openResetDialog(tester);

    await tester.tap(find.text('恢复'));
    await _pumpUntilWriteCount(tester, storage, 1);

    final cancelAction = tester.widget<CupertinoDialogAction>(
      find.widgetWithText(CupertinoDialogAction, '取消'),
    );
    final pendingLabelIsAccurate = find.text('恢复中…').evaluate().isNotEmpty;
    final restoreActionFinder = pendingLabelIsAccurate
        ? find.widgetWithText(CupertinoDialogAction, '恢复中…')
        : find.widgetWithText(CupertinoDialogAction, '恢复');
    final restoreAction = tester.widget<CupertinoDialogAction>(
      restoreActionFinder,
    );
    final cancelWasDisabled = cancelAction.onPressed == null;
    final restoreWasDisabled = restoreAction.onPressed == null;

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final confirmStayedOpen = find.text('恢复默认设置？').evaluate().isNotEmpty;
    if (confirmStayedOpen) {
      await tester.tap(
        pendingLabelIsAccurate ? find.text('恢复中…') : find.text('恢复'),
      );
      await tester.pump();
    }
    final writeCountWhilePending = storage.writes.length;

    storage.writes.single.complete();
    await tester.pumpAndSettle();

    expect(cancelWasDisabled, isTrue);
    expect(restoreWasDisabled, isTrue);
    expect(pendingLabelIsAccurate, isTrue);
    expect(confirmStayedOpen, isTrue);
    expect(writeCountWhilePending, 1);
    expect(find.text('恢复默认设置？'), findsNothing);
  });
}

Future<AppSettingsController> _pumpSettingsPage(
  WidgetTester tester,
  _ControlledSettingsStorage storage,
) async {
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
  return settings;
}

Future<void> _openResetDialog(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('恢复默认'), 400);
  await tester.tap(find.text('恢复默认'));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilWriteCount(
  WidgetTester tester,
  _ControlledSettingsStorage storage,
  int expectedCount,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump();
    if (storage.writes.length >= expectedCount) return;
  }
  fail('Expected $expectedCount settings writes, got ${storage.writes.length}');
}

class _ControlledSettingsStorage implements AppSettingsStorage {
  Map<String, Object?> values = {
    'schemaVersion': AppSettingsController.settingsSchemaVersion,
    'defaultPlaybackSpeed': 2.5,
  };
  final List<Completer<void>> writes = [];

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    final write = Completer<void>();
    writes.add(write);
    await write.future;
    this.values = Map<String, Object?>.from(values);
  }
}
