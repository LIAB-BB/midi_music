import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:midi_music/core/midi/midi_parser.dart';
import 'package:midi_music/models/midi_track.dart';

void main() {
  test('同一 channel/note 的重叠音符按 FIFO 配对 NoteOff', () {
    final song = MidiFileParser().parseBytes(
      _singleTrackMidi([
        0x00, 0x90, 0x3C, 0x40, // tick 0: note on C4
        0x0A, 0x90, 0x3C, 0x50, // tick 10: same note on
        0x0A, 0x80, 0x3C, 0x00, // tick 20: first note off
        0x0A, 0x80, 0x3C, 0x00, // tick 30: second note off
        0x00, 0xFF, 0x2F, 0x00, // end of track
      ]),
      fileName: 'overlap.mid',
    );

    final notes = song.noteTracks.single.notes;

    expect(notes, hasLength(2));
    expect(notes[0].startTick, 0);
    expect(notes[0].endTick, 20);
    expect(notes[1].startTick, 10);
    expect(notes[1].endTick, 30);
  });

  test('同 tick 事件排序保证 NoteOff 和控制事件先于 NoteOn', () {
    final events = [
      TimelineEvent(
        type: MidiEventType.noteOn,
        tick: 120,
        channel: 0,
        trackIndex: 0,
        data1: 60,
        data2: 80,
      ),
      TimelineEvent(type: MidiEventType.endOfTrack, tick: 120, trackIndex: 0),
      TimelineEvent(
        type: MidiEventType.programChange,
        tick: 120,
        channel: 0,
        trackIndex: 0,
        data1: 40,
      ),
      TimelineEvent(
        type: MidiEventType.noteOff,
        tick: 120,
        channel: 0,
        trackIndex: 0,
        data1: 60,
      ),
    ]..sort();

    expect(events.map((event) => event.type), [
      MidiEventType.noteOff,
      MidiEventType.programChange,
      MidiEventType.noteOn,
      MidiEventType.endOfTrack,
    ]);
  });
}

Uint8List _singleTrackMidi(List<int> trackData) {
  return Uint8List.fromList([
    0x4D, 0x54, 0x68, 0x64, // MThd
    0x00, 0x00, 0x00, 0x06, // header length
    0x00, 0x00, // format 0
    0x00, 0x01, // one track
    0x01, 0xE0, // 480 ticks per beat
    0x4D, 0x54, 0x72, 0x6B, // MTrk
    (trackData.length >> 24) & 0xFF,
    (trackData.length >> 16) & 0xFF,
    (trackData.length >> 8) & 0xFF,
    trackData.length & 0xFF,
    ...trackData,
  ]);
}
