import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    PlatformAudioPlugin.register(with: registry.registrar(forPlugin: "PlatformAudioPlugin")!)
    BleL2capPlugin.register(with: registry.registrar(forPlugin: "BleL2capPlugin")!)
    DawnMeshPlatformPlugin.register(with: registry.registrar(forPlugin: "DawnMeshPlatformPlugin")!)
    BonjourDiscoveryPlugin.register(with: registry.registrar(forPlugin: "BonjourDiscoveryPlugin")!)
  }
}
