import AVFoundation
import AudioToolbox
import Darwin
import Foundation

struct SoundfontCase {
    let path: String
    let program: UInt8
    let note: UInt8
}

let cases = [
    SoundfontCase(
        path: "assets/soundfonts/k478_violin.sf2",
        program: 40,
        note: 69
    ),
    SoundfontCase(
        path: "assets/soundfonts/k478_cello.sf2",
        program: 42,
        note: 48
    ),
]

func renderPeak(for soundfont: SoundfontCase) throws -> Float {
    let url = URL(fileURLWithPath: soundfont.path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw NSError(
            domain: "K478SoundfontValidation",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "文件不存在：\(url.path)"]
        )
    }

    var samplerDescription = AudioComponentDescription(
        componentType: kAudioUnitType_MusicDevice,
        componentSubType: kAudioUnitSubType_Sampler,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    guard AudioComponentFindNext(nil, &samplerDescription) != nil else {
        throw NSError(
            domain: "K478SoundfontValidation",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "当前 macOS 会话未提供 Apple Sampler Audio Unit"
            ]
        )
    }

    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    guard let format = AVAudioFormat(
        standardFormatWithSampleRate: 44_100,
        channels: 2
    ) else {
        throw NSError(
            domain: "K478SoundfontValidation",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "无法创建离线音频格式"]
        )
    }

    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(
        .offline,
        format: format,
        maximumFrameCount: 4_096
    )
    try sampler.loadSoundBankInstrument(
        at: url,
        program: soundfont.program,
        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
        bankLSB: UInt8(kAUSampler_DefaultBankLSB)
    )
    try engine.start()

    sampler.startNote(soundfont.note, withVelocity: 100, onChannel: 0)
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat,
        frameCapacity: engine.manualRenderingMaximumFrameCount
    ) else {
        throw NSError(
            domain: "K478SoundfontValidation",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "无法创建离线渲染缓冲区"]
        )
    }

    var peak: Float = 0
    var renderedBuffers = 0
    var attempts = 0
    while renderedBuffers < 12 && attempts < 100 {
        attempts += 1
        let status = try engine.renderOffline(
            engine.manualRenderingMaximumFrameCount,
            to: buffer
        )
        switch status {
        case .success:
            renderedBuffers += 1
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        peak = max(peak, abs(channels[channel][frame]))
                    }
                }
            }
        case .cannotDoInCurrentContext:
            continue
        case .insufficientDataFromInputNode:
            continue
        case .error:
            throw NSError(
                domain: "K478SoundfontValidation",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Apple 离线渲染失败"]
            )
        @unknown default:
            throw NSError(
                domain: "K478SoundfontValidation",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "未知离线渲染状态"]
            )
        }
    }

    sampler.stopNote(soundfont.note, onChannel: 0)
    engine.stop()
    return peak
}

do {
    for soundfont in cases {
        let peak = try renderPeak(for: soundfont)
        guard peak > 0.000_001 else {
            throw NSError(
                domain: "K478SoundfontValidation",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(soundfont.path) 能加载但渲染结果为静音"
                ]
            )
        }
        print("PASS \(soundfont.path) program=\(soundfont.program) peak=\(peak)")
    }
} catch {
    fputs("FAIL \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
