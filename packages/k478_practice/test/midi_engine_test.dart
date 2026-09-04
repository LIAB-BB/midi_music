import 'dart:async';

import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k478_practice/src/core/midi_engine.dart';

class _FakeBackend extends MidiProBackend {
  bool initialized = false;
  bool disposed = false;
  int? failProgram;
  Completer<void>? playGate;
  final List<String> calls = [];
  final List<int> stopAllIds = [];
  final List<int> unloadedIds = [];

  @override
  bool get isInitialized => initialized;

  @override
  Future<void> configureAudioSession({
    required AudioSessionCategory category,
    required bool mixWithOthers,
  }) async {
    calls.add('configure:${category.name}:$mixWithOthers');
  }

  @override
  Future<void> init() async {
    initialized = true;
    calls.add('init');
  }

  @override
  Future<int> loadSoundfontAsset({
    required String assetPath,
    required int bank,
    required int program,
  }) async {
    calls.add('load:$program:$assetPath');
    if (program == failProgram) throw StateError('load failed');
    return program == 40 ? 11 : 22;
  }

  @override
  Future<void> selectInstrument({
    required int sfId,
    required int channel,
    required int bank,
    required int program,
  }) async {
    calls.add('select:$sfId:$channel:$program');
  }

  @override
  Future<void> playNote({
    required int sfId,
    required int channel,
    required int key,
    required int velocity,
  }) async {
    calls.add('on:$sfId:$channel:$key:$velocity');
    await playGate?.future;
  }

  @override
  Future<void> stopNote({
    required int sfId,
    required int channel,
    required int key,
  }) async {
    calls.add('off:$sfId:$channel:$key');
  }

  @override
  Future<void> controlChange({
    required int sfId,
    required int channel,
    required int controller,
    required int value,
  }) async {
    calls.add('cc:$sfId:$channel:$controller:$value');
  }

  @override
  Future<void> stopAllNotes({required int sfId}) async {
    stopAllIds.add(sfId);
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    unloadedIds.add(sfId);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    initialized = false;
  }
}

void main() {
  test('每个 channel 按 program 路由到对应的 SoundFont', () async {
    final backend = _FakeBackend();
    final engine = MidiEngine(backend: backend);

    await engine.loadSoundfontsFromAssets({40: 'violin.sf2', 42: 'cello.sf2'});
    await engine.setInstrument(channel: 1, program: 40);
    await engine.setInstrument(channel: 3, program: 42);
    await engine.noteOn(channel: 1, note: 64, velocity: 90);
    await engine.noteOn(channel: 3, note: 48, velocity: 80);
    await engine.noteOff(channel: 1, note: 64);
    await engine.noteOff(channel: 3, note: 48);

    expect(engine.isReady, isTrue);
    expect(engine.soundfontIdsByProgram, {40: 11, 42: 22});
    expect(
      backend.calls,
      containsAllInOrder(<String>[
        'select:11:1:40',
        'select:22:3:42',
        'on:11:1:64:90',
        'on:22:3:48:80',
        'off:11:1:64',
        'off:22:3:48',
      ]),
    );
  });

  test('allNotesOff 会等待执行中的音符操作再停止全部音源', () async {
    final backend = _FakeBackend()..playGate = Completer<void>();
    final engine = MidiEngine(backend: backend);
    await engine.loadSoundfontsFromAssets({40: 'violin.sf2', 42: 'cello.sf2'});
    await engine.setInstrument(channel: 1, program: 40);

    final note = engine.noteOn(channel: 1, note: 60, velocity: 100);
    await Future<void>.delayed(Duration.zero);
    final allOff = engine.allNotesOff();
    await Future<void>.delayed(Duration.zero);
    await engine.noteOn(channel: 1, note: 62, velocity: 100);

    expect(backend.stopAllIds, isEmpty);
    backend.playGate!.complete();
    await note;
    await allOff;
    expect(backend.stopAllIds, containsAll(<int>[11, 22]));
    expect(backend.calls.where((call) => call.startsWith('on:')), [
      'on:11:1:60:100',
    ]);
  });

  test('重新加载会卸载旧音源并清除旧 channel 绑定', () async {
    final backend = _FakeBackend();
    final engine = MidiEngine(backend: backend);
    await engine.loadSoundfontsFromAssets({40: 'violin.sf2'});
    await engine.setInstrument(channel: 1, program: 40);

    await engine.loadSoundfontsFromAssets({42: 'cello.sf2'});
    await engine.noteOn(channel: 1, note: 60, velocity: 100);

    expect(backend.unloadedIds, [11]);
    expect(backend.calls.where((call) => call.startsWith('on:')), isEmpty);
  });

  test('部分加载失败会回收已加载音源并保持未就绪', () async {
    final backend = _FakeBackend()..failProgram = 42;
    final engine = MidiEngine(backend: backend);

    await expectLater(
      engine.loadSoundfontsFromAssets({40: 'violin.sf2', 42: 'cello.sf2'}),
      throwsStateError,
    );

    expect(engine.isReady, isFalse);
    expect(engine.soundfontIdsByProgram, isEmpty);
    expect(backend.unloadedIds, [11]);
  });

  test('dispose 会停止、卸载全部音源并释放后端', () async {
    final backend = _FakeBackend();
    final engine = MidiEngine(backend: backend);
    await engine.loadSoundfontsFromAssets({40: 'violin.sf2', 42: 'cello.sf2'});

    await engine.dispose();

    expect(backend.stopAllIds, containsAll(<int>[11, 22]));
    expect(backend.unloadedIds, [11, 22]);
    expect(backend.disposed, isTrue);
    expect(engine.isReady, isFalse);
  });
}
