import Flutter
import AudioToolbox
import AVFoundation
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var xeneNativeHapticsChannel: FlutterMethodChannel?
  private var xeneNowPlayingChannel: FlutterMethodChannel?
  private var lastXeneSystemVibrationAt: CFAbsoluteTime = 0
  private var nowPlayingArtworkTask: URLSessionDataTask?
  private var nowPlayingGeneration = 0
  private var lastXeneNowPlayingInfo: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async { [weak self] in
      self?.setupXeneNativeHapticsChannel()
      self?.setupXeneNowPlayingChannel()
    }
    return result
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    reassertXeneNowPlayingInfo()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    reassertXeneNowPlayingInfo()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DispatchQueue.main.async { [weak self] in
      self?.setupXeneNativeHapticsChannel()
      self?.setupXeneNowPlayingChannel()
    }
  }

  private func flutterRootController() -> FlutterViewController? {
    let rootController = window?.rootViewController
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController

    return rootController as? FlutterViewController
  }

  private func setupXeneNativeHapticsChannel(retry: Int = 0) {
    if xeneNativeHapticsChannel != nil { return }

    guard let controller = flutterRootController() else {
      if retry < 8 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          self?.setupXeneNativeHapticsChannel(retry: retry + 1)
        }
      } else {
        print("[xeneHaptics] FlutterViewController unavailable; native haptics channel not registered")
      }
      return
    }

    let channel = FlutterMethodChannel(
      name: "xene/native_haptics",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "impact" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let args = call.arguments as? [String: Any]
      let kind = args?["kind"] as? String ?? "medium"
      self?.fireXeneNativeImpact(kind: kind)
      result(true)
    }
    xeneNativeHapticsChannel = channel
    print("[xeneHaptics] native haptics channel registered")
  }

  private func setupXeneNowPlayingChannel(retry: Int = 0) {
    if xeneNowPlayingChannel != nil { return }

    guard let controller = flutterRootController() else {
      if retry < 8 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          self?.setupXeneNowPlayingChannel(retry: retry + 1)
        }
      } else {
        print("[xeneNowPlaying] FlutterViewController unavailable; now playing channel not registered")
      }
      return
    }

    let channel = FlutterMethodChannel(
      name: "xene/now_playing_metadata",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "update":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Expected metadata map", details: nil))
          return
        }
        self?.updateXeneNowPlaying(args)
        result(true)
      case "clear":
        self?.clearXeneNowPlaying()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    xeneNowPlayingChannel = channel
    print("[xeneNowPlaying] metadata channel registered")
  }

  private func updateXeneNowPlaying(_ args: [String: Any]) {
    nowPlayingGeneration += 1
    let generation = nowPlayingGeneration
    nowPlayingArtworkTask?.cancel()

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("[xeneNowPlaying] audio session activation failed: \(error)")
    }
    UIApplication.shared.beginReceivingRemoteControlEvents()

    let title = nonEmptyString(args["title"]) ?? "Unknown Track"
    let artist = nonEmptyString(args["artist"]) ?? "Xene"
    let platform = nonEmptyString(args["platform"]) ?? "Xene"
    let isPlaying = args["isPlaying"] as? Bool ?? true

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyArtist: artist,
      MPMediaItemPropertyAlbumTitle: platform.capitalized,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
    ]

    if let duration = numberAsDouble(args["durationSeconds"]), duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let elapsed = numberAsDouble(args["elapsedSeconds"]), elapsed >= 0 {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    }

    lastXeneNowPlayingInfo = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    guard let artworkUrlString = nonEmptyString(args["artworkUrl"]),
          let artworkUrl = URL(string: artworkUrlString) else {
      return
    }

    nowPlayingArtworkTask = URLSession.shared.dataTask(with: artworkUrl) { [weak self] data, _, _ in
      guard let self = self,
            let data,
            let image = UIImage(data: data) else {
        return
      }

      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard generation == self.nowPlayingGeneration else { return }
        var latest = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
        latest[MPMediaItemPropertyArtwork] = artwork
        self.lastXeneNowPlayingInfo = latest
        MPNowPlayingInfoCenter.default().nowPlayingInfo = latest
      }
    }
    nowPlayingArtworkTask?.resume()
  }

  private func clearXeneNowPlaying() {
    nowPlayingGeneration += 1
    nowPlayingArtworkTask?.cancel()
    nowPlayingArtworkTask = nil
    lastXeneNowPlayingInfo = nil
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    UIApplication.shared.endReceivingRemoteControlEvents()
  }

  private func reassertXeneNowPlayingInfo() {
    guard let info = lastXeneNowPlayingInfo else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info

    // WKWebView can publish its own generic media-session payload during the
    // lock transition; reapply Xene's payload after that handoff settles.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let info = self?.lastXeneNowPlayingInfo else { return }
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
  }

  private func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private func numberAsDouble(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let double = value as? Double { return double }
    if let int = value as? Int { return Double(int) }
    return nil
  }

  private func fireXeneNativeImpact(kind: String) {
    DispatchQueue.main.async {
      let generator: UIImpactFeedbackGenerator
      if #available(iOS 13.0, *) {
        generator = UIImpactFeedbackGenerator(style: kind == "light" ? .medium : .rigid)
      } else {
        generator = UIImpactFeedbackGenerator(style: kind == "light" ? .medium : .heavy)
      }

      generator.prepare()
      if #available(iOS 13.0, *) {
        generator.impactOccurred(intensity: kind == "heavy" ? 1.0 : 0.9)
      } else {
        generator.impactOccurred()
      }

      if kind != "light" {
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.lastXeneSystemVibrationAt >= 0.18 {
          self.lastXeneSystemVibrationAt = now
          AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
      }
    }
  }
}
