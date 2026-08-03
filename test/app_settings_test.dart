import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/settings/app_settings.dart';

void main() {
  test('USB MIDI 跟随默认使用精确音符匹配', () {
    final settings = AppSettingsController(storage: _MemorySettingsStorage());

    expect(settings.followModeConfig.noteMatchTolerance, 0);
    expect(settings.followModeConfig.allowOctaveError, isFalse);
  });

  test('加载设置时会裁剪到安全范围并生成跟随配置', () async {
    final settings = AppSettingsController(
      storage: _MemorySettingsStorage(
        initialValues: {
          'schemaVersion': AppSettingsController.settingsSchemaVersion,
          'defaultPlaybackSpeed': 8.0,
          'microphoneMinPrecision': 1.0,
          'onsetVolumeThreshold': 0.00001,
          'noteMatchTolerance': 9,
          'allowOctaveError': false,
          'minMeasuredSpeedFactor': 1.2,
          'maxMeasuredSpeedFactor': 0.8,
          'restThresholdSeconds': 9.0,
        },
      ),
    );

    await settings.load();

    expect(settings.defaultPlaybackSpeed, 4.0);
    expect(settings.microphoneMinPrecision, 0.95);
    expect(settings.onsetVolumeThreshold, 0.0001);
    expect(settings.noteMatchTolerance, 4);
    expect(settings.allowOctaveError, isFalse);
    expect(settings.minMeasuredSpeedFactor, 1.0);
    expect(settings.maxMeasuredSpeedFactor, 1.0);
    expect(settings.restThresholdSeconds, 3.0);

    expect(settings.followSessionConfig.minPrecision, 0.95);
    expect(settings.onsetDetectorConfig.volumeThreshold, 0.0001);
    expect(settings.followModeConfig.allowOctaveError, isFalse);
    expect(settings.followModeConfig.noteMatchTolerance, 4);
  });

  test('旧版麦克风容错设置迁移为 USB MIDI 精确匹配', () async {
    final settings = AppSettingsController(
      storage: _MemorySettingsStorage(
        initialValues: {
          'schemaVersion': 1,
          'noteMatchTolerance': 2,
          'allowOctaveError': true,
        },
      ),
    );

    await settings.load();

    expect(settings.noteMatchTolerance, 0);
    expect(settings.allowOctaveError, isFalse);
  });

  test('更新设置会持久化，恢复默认会写回推荐值', () async {
    final storage = _MemorySettingsStorage();
    final settings = AppSettingsController(storage: storage);

    settings.setDefaultPlaybackSpeed(2.5);
    settings.setAllowOctaveError(value: false);
    await settings.flush();

    expect(storage.values['defaultPlaybackSpeed'], 2.5);
    expect(storage.values['allowOctaveError'], isFalse);
    expect(
      storage.values['schemaVersion'],
      AppSettingsController.settingsSchemaVersion,
    );

    settings.resetToDefaults();
    await settings.flush();

    expect(
      storage.values['defaultPlaybackSpeed'],
      AppSettingsController.defaultPlaybackSpeedValue,
    );
    expect(
      storage.values['allowOctaveError'],
      AppSettingsController.defaultAllowOctaveErrorValue,
    );
  });

  test('flush 会等待串行写入并保留最后一次状态', () async {
    final storage = _DelayedMemorySettingsStorage(
      writeDelay: const Duration(milliseconds: 5),
    );
    final settings = AppSettingsController(storage: storage);

    settings.setDefaultPlaybackSpeed(1.25);
    settings.setDefaultPlaybackSpeed(2.75);
    settings.setAllowOctaveError(value: false);
    await settings.flush();

    expect(storage.maxConcurrentWrites, 1);
    expect(storage.writeCount, 3);
    expect(storage.values['defaultPlaybackSpeed'], 2.75);
    expect(storage.values['allowOctaveError'], isFalse);
    expect(settings.lastPersistenceError, isNull);
  });

  test('写入失败会记录错误，后续 flush 可恢复', () async {
    final storage = _MemorySettingsStorage(failNextWrite: true);
    final settings = AppSettingsController(storage: storage);

    settings.setDefaultPlaybackSpeed(1.5);
    await settings.flush();

    expect(settings.lastPersistenceError, isNotNull);
    expect(storage.values['defaultPlaybackSpeed'], isNull);

    settings.setDefaultPlaybackSpeed(2.0);
    await settings.flush();

    expect(settings.lastPersistenceError, isNull);
    expect(storage.values['defaultPlaybackSpeed'], 2.0);
  });

  test('文件存储在主文件损坏时从 backup 恢复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'midi_music_settings_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final storage = FileAppSettingsStorage(
      directoryProvider: () async {
        return directory;
      },
    );

    await storage.write({'defaultPlaybackSpeed': 1.75});
    await File('${directory.path}/settings.json').writeAsString('not-json');

    final values = await storage.read();

    expect(values['defaultPlaybackSpeed'], 1.75);
  });
}

class _MemorySettingsStorage implements AppSettingsStorage {
  Map<String, Object?> values;
  bool failNextWrite;

  _MemorySettingsStorage({
    Map<String, Object?>? initialValues,
    this.failNextWrite = false,
  }) : values = Map<String, Object?>.from(initialValues ?? const {});

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('simulated write failure');
    }
    this.values = Map<String, Object?>.from(values);
  }
}

class _DelayedMemorySettingsStorage extends _MemorySettingsStorage {
  final Duration writeDelay;
  int _activeWrites = 0;
  int maxConcurrentWrites = 0;
  int writeCount = 0;

  _DelayedMemorySettingsStorage({required this.writeDelay});

  @override
  Future<void> write(Map<String, Object?> values) async {
    _activeWrites++;
    writeCount++;
    if (_activeWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _activeWrites;
    }
    try {
      await Future<void>.delayed(writeDelay);
      await super.write(values);
    } finally {
      _activeWrites--;
    }
  }
}
