import 'dart:async';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_engine.dart';

void main() {
  test('同通道操作按顺序等待 instrument change 后再发音', () async {
    final midiPro = _FakeMidiPro();
    final engine = MidiEngine.readyForTesting(midiPro: midiPro, soundfontId: 7);
    final selectGate = Completer<void>();
    midiPro.selectGate = selectGate;

    final selectFuture = engine.setInstrument(channel: 0, program: 40);
    final noteFuture = engine.noteOn(channel: 0, note: 60, velocity: 100);
    await pumpEventQueue();

    expect(midiPro.calls, ['select:0:40']);

    selectGate.complete();
    await Future.wait([selectFuture, noteFuture]);

    expect(midiPro.calls, ['select:0:40', 'selectDone:0:40', 'play:0:60']);
  });

  test('不同通道操作互不阻塞', () async {
    final midiPro = _FakeMidiPro();
    final engine = MidiEngine.readyForTesting(midiPro: midiPro, soundfontId: 7);
    final selectGate = Completer<void>();
    midiPro.selectGate = selectGate;

    final selectFuture = engine.setInstrument(channel: 0, program: 40);
    final noteFuture = engine.noteOn(channel: 1, note: 64, velocity: 100);
    await noteFuture;

    expect(midiPro.calls, ['select:0:40', 'play:1:64']);

    selectGate.complete();
    await selectFuture;
  });

  test('allNotesOff 会取消尚未开始的排队音符', () async {
    final midiPro = _FakeMidiPro();
    final engine = MidiEngine.readyForTesting(midiPro: midiPro, soundfontId: 7);
    final selectGate = Completer<void>();
    midiPro.selectGate = selectGate;

    final selectFuture = engine.setInstrument(channel: 0, program: 40);
    final noteFuture = engine.noteOn(channel: 0, note: 60, velocity: 100);
    await pumpEventQueue();

    await engine.allNotesOff();
    selectGate.complete();
    await Future.wait([selectFuture, noteFuture]);

    expect(midiPro.calls, ['select:0:40', 'stopAll:7', 'selectDone:0:40']);
    expect(midiPro.calls, isNot(contains('play:0:60')));
  });
}

class _FakeMidiPro extends MidiPro {
  final calls = <String>[];
  Completer<void>? selectGate;

  @override
  Future<void> selectInstrument({
    required int sfId,
    required int program,
    int channel = 0,
    int bank = 0,
  }) async {
    calls.add('select:$channel:$program');
    await selectGate?.future;
    calls.add('selectDone:$channel:$program');
  }

  @override
  Future<void> playNote({
    int channel = 0,
    required int key,
    int velocity = 127,
    int sfId = 1,
  }) async {
    calls.add('play:$channel:$key');
  }

  @override
  Future<void> stopNote({
    int channel = 0,
    required int key,
    int sfId = 1,
  }) async {
    calls.add('stop:$channel:$key');
  }

  @override
  Future<void> stopAllNotes({int sfId = 1}) async {
    calls.add('stopAll:$sfId');
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    calls.add('unload:$sfId');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}
