import 'dart:io';

import 'package:dart_midi_pro/dart_midi_pro.dart';

/// 打印一个 MIDI 文件的轨道摘要，便于确认跟随声部与 tempo。
void main(List<String> args) {
  final path = args.isEmpty
      ? '../../assets/midi/mozart_k478_piano_quartet.mid'
      : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('找不到 MIDI：$path');
    exitCode = 2;
    return;
  }
  final midi = MidiParser().parseMidiFromBuffer(file.readAsBytesSync());
  final ppq = midi.header.ticksPerBeat;
  stdout.writeln(
    'file=${file.path} format=${midi.header.format} tracks=${midi.tracks.length} ppq=$ppq',
  );

  for (var trackIndex = 0; trackIndex < midi.tracks.length; trackIndex++) {
    final events = midi.tracks[trackIndex];
    var tick = 0;
    var noteOns = 0;
    var noteOffs = 0;
    final programs = <int>{};
    final channels = <int>{};
    var name = '';
    var tempos = 0;
    for (final event in events) {
      tick += event.deltaTime;
      if (event is NoteOnEvent && event.velocity > 0) {
        noteOns++;
        channels.add(event.channel);
      } else if (event is NoteOffEvent ||
          (event is NoteOnEvent && event.velocity == 0)) {
        noteOffs++;
      } else if (event is ProgramChangeMidiEvent) {
        programs.add(event.programNumber);
        channels.add(event.channel);
      } else if (event is TrackNameEvent) {
        name = event.text;
      } else if (event is SetTempoEvent) {
        tempos++;
      }
    }
    stdout.writeln(
      '#$trackIndex name="$name" ch=$channels programs=$programs '
      'noteOns=$noteOns noteOffs=$noteOffs tempoEvents=$tempos '
      'endTick=$tick',
    );
  }
}
