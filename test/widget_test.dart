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
  });
}
