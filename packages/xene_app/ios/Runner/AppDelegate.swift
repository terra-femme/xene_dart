import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var xeneNativeHapticsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async { [weak self] in
      self?.setupXeneNativeHapticsChannel()
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DispatchQueue.main.async { [weak self] in
      self?.setupXeneNativeHapticsChannel()
    }
  }

  private func setupXeneNativeHapticsChannel(retry: Int = 0) {
    if xeneNativeHapticsChannel != nil { return }

    let rootController = window?.rootViewController
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow }?
        .rootViewController

    guard let controller = rootController as? FlutterViewController else {
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
    }
  }
}
