import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 配置音频会话（只配置一次）
    configureAudioSession()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "CoreMidiInputPlugin"
    ) {
      CoreMidiInputPlugin.register(with: registrar)
    }
  }

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()

      // MIDI demo 只播放伴奏；电子琴自行发声，不占用麦克风输入。
      try session.setCategory(
        AVAudioSession.Category.playback,
        mode: AVAudioSession.Mode.default,
        options: [AVAudioSession.CategoryOptions.mixWithOthers]
      )

      // 激活音频会话
      try session.setActive(true)
    } catch {
      NSLog("[AudioSession] 配置失败: \(error.localizedDescription)")
    }
  }
}
