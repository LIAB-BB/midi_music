import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:midi_music/app.dart';
import 'package:midi_music/core/midi/midi_player.dart';
import 'package:midi_music/ui/widgets/player_helpers.dart';

void main() {
  testWidgets('App smoke test — renders without crashing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MidiPlayerController(),
        child: const MidiMusicApp(),
      ),
    );

    expect(find.text('导入 MIDI 乐谱'), findsOneWidget);
    expect(find.byKey(HomeUiKeys.importMidiButton), findsOneWidget);
    expect(
      find.byKey(HomeUiKeys.demoSongButton('Beethoven-Moonlight-Sonata.mid')),
      findsOneWidget,
    );
    expect(find.byKey(HomeUiKeys.diagnosticsButton), findsOneWidget);

    await tester.tap(find.byKey(HomeUiKeys.diagnosticsButton));
    await tester.pumpAndSettle();

    expect(find.text('诊断'), findsOneWidget);
    expect(find.text('音色引擎'), findsOneWidget);
    expect(find.text('麦克风权限'), findsOneWidget);
    expect(find.text('构建信息'), findsOneWidget);
    expect(find.byKey(DiagnosticsUiKeys.copyReportButton), findsOneWidget);
    expect(find.byKey(DiagnosticsUiKeys.soundfontRetryButton), findsOneWidget);
  });
}
