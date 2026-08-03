import CoreMIDI
import Flutter
import Foundation
import MachO

final class CoreMidiInputPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "com.midimusic.midi_music/midi_input/methods"
  private static let eventChannelName = "com.midimusic.midi_music/midi_input/events"

  private var midiClient = MIDIClientRef()
  private var inputPort = MIDIPortRef()
  private var connectedSources = Set<MIDIEndpointRef>()
  private var eventSink: FlutterEventSink?
  private var isListening = false
  private var runningStatus: UInt8?
  private var pendingData = [UInt8]()

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CoreMidiInputPlugin()
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    instance.createMidiClient()
  }

  deinit {
    stopListening()
    if inputPort != 0 {
      MIDIPortDispose(inputPort)
    }
    if midiClient != 0 {
      MIDIClientDispose(midiClient)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      startListening()
      result(devicePayload())
    case "stop":
      stopListening()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    emitDeviceState()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func createMidiClient() {
    let clientStatus = MIDIClientCreateWithBlock(
      "MidiMusic USB Input" as CFString,
      &midiClient
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.isListening else { return }
        self.refreshSources()
      }
    }
    guard clientStatus == noErr else {
      NSLog("[CoreMIDI] 无法创建 MIDI client: \(clientStatus)")
      return
    }

    let portStatus = MIDIInputPortCreateWithBlock(
      midiClient,
      "MidiMusic USB Input Port" as CFString,
      &inputPort
    ) { [weak self] packetList, _ in
      self?.handlePacketList(packetList)
    }
    if portStatus != noErr {
      NSLog("[CoreMIDI] 无法创建 MIDI input port: \(portStatus)")
    }
  }

  private func startListening() {
    guard midiClient != 0, inputPort != 0 else { return }
    isListening = true
    refreshSources()
  }

  private func stopListening() {
    guard inputPort != 0 else { return }
    for source in connectedSources {
      MIDIPortDisconnectSource(inputPort, source)
    }
    connectedSources.removeAll()
    isListening = false
    runningStatus = nil
    pendingData.removeAll(keepingCapacity: true)
  }

  private func refreshSources() {
    for source in connectedSources {
      MIDIPortDisconnectSource(inputPort, source)
    }
    connectedSources.removeAll()

    for index in 0..<MIDIGetNumberOfSources() {
      let source = MIDIGetSource(index)
      guard source != 0 else { continue }
      if MIDIPortConnectSource(inputPort, source, nil) == noErr {
        connectedSources.insert(source)
      }
    }
    emitDeviceState()
  }

  private func devicePayload() -> [[String: String]] {
    connectedSources.map { source in
      [
        "id": String(source),
        "name": midiDisplayName(for: source),
      ]
    }.sorted { $0["name", default: ""] < $1["name", default: ""] }
  }

  private func emitDeviceState() {
    let payload: [String: Any] = [
      "type": "devices",
      "devices": devicePayload(),
    ]
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  private func midiDisplayName(for endpoint: MIDIEndpointRef) -> String {
    var property: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(
      endpoint,
      kMIDIPropertyDisplayName,
      &property
    )
    if status == noErr, let property {
      return property.takeRetainedValue() as String
    }
    return "USB MIDI \(endpoint)"
  }

  private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
    let dataOffset = MemoryLayout.offset(of: \MIDIPacket.data) ?? 0
    for packet in packetList.unsafeSequence() {
      let byteCount = Int(packet.pointee.length)
      let dataPointer = UnsafeRawPointer(packet)
        .advanced(by: dataOffset)
        .assumingMemoryBound(to: UInt8.self)
      let bytes = UnsafeBufferPointer(start: dataPointer, count: byteCount)
      parse(bytes, timestamp: packet.pointee.timeStamp)
    }
  }

  private func parse(
    _ bytes: UnsafeBufferPointer<UInt8>,
    timestamp: MIDITimeStamp
  ) {
    for byte in bytes {
      if byte >= 0xF8 {
        continue
      }
      if byte >= 0xF0 {
        runningStatus = nil
        pendingData.removeAll(keepingCapacity: true)
        continue
      }
      if byte & 0x80 != 0 {
        runningStatus = byte
        pendingData.removeAll(keepingCapacity: true)
        continue
      }
      guard let status = runningStatus else { continue }
      pendingData.append(byte)
      let command = status & 0xF0
      let expectedCount = command == 0xC0 || command == 0xD0 ? 1 : 2
      guard pendingData.count >= expectedCount else { continue }

      emitMidiMessage(
        status: status,
        data1: pendingData[0],
        data2: expectedCount == 2 ? pendingData[1] : 0,
        timestamp: timestamp
      )
      pendingData.removeAll(keepingCapacity: true)
    }
  }

  private func emitMidiMessage(
    status: UInt8,
    data1: UInt8,
    data2: UInt8,
    timestamp: MIDITimeStamp
  ) {
    let payload: [String: Any] = [
      "type": "midi",
      "status": Int(status),
      "data1": Int(data1),
      "data2": Int(data2),
      "timestampMicros": Int64(hostTimeMicros(timestamp)),
    ]
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  private func hostTimeMicros(_ timestamp: MIDITimeStamp) -> UInt64 {
    let hostTime = timestamp == 0 ? mach_absolute_time() : timestamp
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let nanos = Double(hostTime) * Double(info.numer) / Double(info.denom)
    return UInt64(nanos / 1_000)
  }
}
