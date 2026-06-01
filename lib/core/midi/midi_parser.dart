import 'dart:io';

import 'package:dart_midi_pro/dart_midi_pro.dart' as midi;
import 'package:flutter/foundation.dart';

import '../../models/midi_track.dart';
import 'tempo_map.dart';

/// MIDI 文件解析器
///
/// 使用 dart_midi_pro 解析原始 MIDI 数据，
/// 然后转换为我们的 MidiSongData 模型（绝对时间、音符配对）。
class MidiFileParser {
  final midi.MidiParser _parser = midi.MidiParser();

  /// 从文件路径解析
  Future<MidiSongData> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('MIDI file not found', filePath);
    }
    final bytes = await file.readAsBytes();
    return compute(
      _parseMidiFileInBackground,
      _MidiParseRequest(bytes, file.uri.pathSegments.last),
    );
  }

  /// 从字节数据解析
  MidiSongData parseBytes(Uint8List bytes, {String fileName = 'unknown.mid'}) {
    final midiFile = _parser.parseMidiFromBuffer(bytes);
    return _convertMidiFile(midiFile, fileName);
  }

  /// 将 dart_midi_pro 的 MidiFile 转换为我们的 MidiSongData
  MidiSongData _convertMidiFile(midi.MidiFile midiFile, String fileName) {
    final ticksPerBeat = midiFile.header.ticksPerBeat ?? 480;
    final rawTracks = midiFile.tracks;

    // 第一遍：提取全局 tempo 和拍号事件
    final tempoChanges = <TempoChange>[];
    final timeSignatureChanges = <TimeSignatureChange>[];
    _extractGlobalEvents(rawTracks, tempoChanges, timeSignatureChanges);

    // 构建 TempoMap
    final tempoMap = TempoMap(
      ticksPerBeat: ticksPerBeat,
      tempoChanges: tempoChanges,
    );

    // 第二遍：解析每个轨道
    final tracks = <MidiTrackInfo>[];
    final allTimelineEvents = <TimelineEvent>[];

    for (int i = 0; i < rawTracks.length; i++) {
      final trackInfo = _parseTrack(rawTracks[i], i, tempoMap);
      tracks.add(trackInfo);
      allTimelineEvents.addAll(trackInfo.events);
    }

    // 合并全局时间线并排序
    allTimelineEvents.sort();

    // 计算总时长
    final totalTicks = _findMaxTick(rawTracks);
    final totalDuration = tempoMap.tickToSeconds(totalTicks);

    // 为拍号变化设置绝对时间
    for (final ts in timeSignatureChanges) {
      ts.time = tempoMap.tickToSeconds(ts.tick);
    }

    return MidiSongData(
      fileName: fileName,
      format: midiFile.header.format,
      ticksPerBeat: ticksPerBeat,
      tracks: tracks,
      timeline: allTimelineEvents,
      tempoChanges: tempoMap.tempoChanges,
      timeSignatureChanges: timeSignatureChanges,
      totalTicks: totalTicks,
      totalDuration: totalDuration,
    );
  }

  /// 从所有轨道中提取 tempo 和拍号事件
  void _extractGlobalEvents(
    List<List<midi.MidiEvent>> rawTracks,
    List<TempoChange> tempoChanges,
    List<TimeSignatureChange> timeSignatureChanges,
  ) {
    for (final track in rawTracks) {
      int absoluteTick = 0;
      for (final event in track) {
        absoluteTick += event.deltaTime;

        if (event is midi.SetTempoEvent) {
          tempoChanges.add(
            TempoChange(
              tick: absoluteTick,
              microsecondsPerBeat: event.microsecondsPerBeat,
            ),
          );
        } else if (event is midi.TimeSignatureEvent) {
          timeSignatureChanges.add(
            TimeSignatureChange(
              tick: absoluteTick,
              numerator: event.numerator,
              denominator: event.denominator,
            ),
          );
        }
      }
    }

    // 按 tick 排序并去重
    tempoChanges.sort((a, b) => a.tick.compareTo(b.tick));
    timeSignatureChanges.sort((a, b) => a.tick.compareTo(b.tick));
  }

  /// 解析单个轨道：遍历事件、配对音符、应用绝对时间
  MidiTrackInfo _parseTrack(
    List<midi.MidiEvent> rawEvents,
    int trackIndex,
    TempoMap tempoMap,
  ) {
    final notes = <MidiNote>[];
    final events = <TimelineEvent>[];
    final channels = <int>{};
    final programByChannel = <int, int>{};
    final pendingNotes = <String, List<_PendingNote>>{};
    String trackName = '';
    int absoluteTick = 0;

    for (final event in rawEvents) {
      absoluteTick += event.deltaTime;

      if (event is midi.NoteOnEvent) {
        if (event.velocity == 0) {
          // NoteOn with velocity=0 等同于 NoteOff
          _handleNoteOff(
            event.noteNumber,
            event.channel,
            absoluteTick,
            trackIndex,
            pendingNotes,
            notes,
            events,
          );
        } else {
          _handleNoteOn(
            event,
            absoluteTick,
            trackIndex,
            channels,
            pendingNotes,
            events,
          );
        }
      } else if (event is midi.NoteOffEvent) {
        _handleNoteOff(
          event.noteNumber,
          event.channel,
          absoluteTick,
          trackIndex,
          pendingNotes,
          notes,
          events,
        );
      } else if (event is midi.ProgramChangeMidiEvent) {
        channels.add(event.channel);
        programByChannel[event.channel] = event.programNumber;
        events.add(
          TimelineEvent(
            type: MidiEventType.programChange,
            tick: absoluteTick,
            channel: event.channel,
            trackIndex: trackIndex,
            data1: event.programNumber,
          ),
        );
      } else if (event is midi.ControllerEvent) {
        channels.add(event.channel);
        events.add(
          TimelineEvent(
            type: MidiEventType.controlChange,
            tick: absoluteTick,
            channel: event.channel,
            trackIndex: trackIndex,
            data1: event.controllerType,
            data2: event.value,
          ),
        );
      } else if (event is midi.PitchBendEvent) {
        channels.add(event.channel);
        events.add(
          TimelineEvent(
            type: MidiEventType.pitchBend,
            tick: absoluteTick,
            channel: event.channel,
            trackIndex: trackIndex,
            data1: event.value,
          ),
        );
      } else if (event is midi.TrackNameEvent) {
        trackName = event.text;
      } else if (event is midi.EndOfTrackEvent) {
        events.add(
          TimelineEvent(
            type: MidiEventType.endOfTrack,
            tick: absoluteTick,
            trackIndex: trackIndex,
          ),
        );
      }
    }

    // 按 startTick 排序音符
    notes.sort((a, b) => a.startTick.compareTo(b.startTick));
    events.sort();

    // 批量应用绝对时间
    tempoMap.applyTimesToEvents(events);
    tempoMap.applyTimesToNotes(notes);

    return MidiTrackInfo(
      index: trackIndex,
      name: trackName,
      channels: channels,
      programByChannel: programByChannel,
      notes: notes,
      events: events,
    );
  }

  /// 处理 NoteOn 事件：记录待配对音符，生成时间线事件
  void _handleNoteOn(
    midi.NoteOnEvent event,
    int absoluteTick,
    int trackIndex,
    Set<int> channels,
    Map<String, List<_PendingNote>> pendingNotes,
    List<TimelineEvent> events,
  ) {
    channels.add(event.channel);
    final key = '${event.channel}-${event.noteNumber}';

    final pendingForNote = pendingNotes.putIfAbsent(key, () => []);
    pendingForNote.add(
      _PendingNote(
        noteNumber: event.noteNumber,
        velocity: event.velocity,
        channel: event.channel,
        startTick: absoluteTick,
      ),
    );

    events.add(
      TimelineEvent(
        type: MidiEventType.noteOn,
        tick: absoluteTick,
        channel: event.channel,
        trackIndex: trackIndex,
        data1: event.noteNumber,
        data2: event.velocity,
      ),
    );
  }

  /// 处理 NoteOff 事件：与待配对的 NoteOn 配对，生成 MidiNote
  void _handleNoteOff(
    int noteNumber,
    int channel,
    int absoluteTick,
    int trackIndex,
    Map<String, List<_PendingNote>> pendingNotes,
    List<MidiNote> notes,
    List<TimelineEvent> events,
  ) {
    final key = '$channel-$noteNumber';
    final pendingForNote = pendingNotes[key];
    final pending = pendingForNote == null || pendingForNote.isEmpty
        ? null
        : pendingForNote.removeAt(0);
    if (pendingForNote != null && pendingForNote.isEmpty) {
      pendingNotes.remove(key);
    }

    if (pending != null) {
      notes.add(
        MidiNote(
          noteNumber: pending.noteNumber,
          velocity: pending.velocity,
          channel: pending.channel,
          startTick: pending.startTick,
          endTick: absoluteTick,
        ),
      );
    }

    events.add(
      TimelineEvent(
        type: MidiEventType.noteOff,
        tick: absoluteTick,
        channel: channel,
        trackIndex: trackIndex,
        data1: noteNumber,
        data2: 0,
      ),
    );
  }

  /// 查找所有轨道中的最大 tick 值
  int _findMaxTick(List<List<midi.MidiEvent>> rawTracks) {
    int maxTick = 0;
    for (final track in rawTracks) {
      int absoluteTick = 0;
      for (final event in track) {
        absoluteTick += event.deltaTime;
      }
      if (absoluteTick > maxTick) {
        maxTick = absoluteTick;
      }
    }
    return maxTick;
  }
}

/// 待配对的音符（NoteOn 已收到，等待 NoteOff）
class _PendingNote {
  final int noteNumber;
  final int velocity;
  final int channel;
  final int startTick;

  _PendingNote({
    required this.noteNumber,
    required this.velocity,
    required this.channel,
    required this.startTick,
  });
}

MidiSongData _parseMidiFileInBackground(_MidiParseRequest request) {
  return MidiFileParser().parseBytes(request.bytes, fileName: request.fileName);
}

class _MidiParseRequest {
  final Uint8List bytes;
  final String fileName;

  const _MidiParseRequest(this.bytes, this.fileName);
}
