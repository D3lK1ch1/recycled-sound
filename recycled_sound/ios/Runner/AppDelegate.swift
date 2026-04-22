import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register Object Capture (LiDAR 3D scanning) platform channel + view.
    // Use the plugin registry's registrar to get the binary messenger —
    // window?.rootViewController is nil with scene-based lifecycle.
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ObjectCaptureView")
    if let registrar = registrar {
      ObjectCapturePluginRegistrar.register(
        with: registrar.messenger(),
        registrar: registrar
      )
    }
  }
}
