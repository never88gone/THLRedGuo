import Flutter
import UIKit
import CFNetwork
import AVKit
import AVFoundation
import CoreMedia

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVPictureInPictureControllerDelegate {
  private var pipController: AVPictureInPictureController?
  private var pipPlayer: AVPlayer?
  private var pipPlayerLayer: AVPlayerLayer?
  private var pipContainerView: UIView?
  private var deviceChannel: FlutterMethodChannel?
  private var icloudChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    if UIDevice.current.userInterfaceIdiom == .pad {
      return .all
    }
    return .allButUpsideDown
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeviceSettings") {
      let channel = FlutterMethodChannel(name: "duanju/device", binaryMessenger: registrar.messenger())
      self.deviceChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "isPad" {
          result(UIDevice.current.userInterfaceIdiom == .pad)
          return
        }
        if call.method == "deviceInfo" {
          result([
            "television": false,
            "isPad": UIDevice.current.userInterfaceIdiom == .pad,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
          ])
          return
        }
        if call.method == "pictureInPictureStatus" {
          let supported = AVPictureInPictureController.isPictureInPictureSupported()
          let active = self.pipController?.isPictureInPictureActive ?? false
          result([
            "supported": supported,
            "active": active
          ])
          return
        }
        if call.method == "enterPictureInPicture" {
          guard AVPictureInPictureController.isPictureInPictureSupported() else {
            result(["supported": false, "active": false, "requested": false])
            return
          }
          let args = call.arguments as? [String: Any]
          let urlStr = args?["url"] as? String ?? ""
          let positionMs = args?["position"] as? Int ?? 0
          let speed = (args?["speed"] as? NSNumber)?.floatValue ?? 1.0

          let targetUrl: URL?
          if urlStr.hasPrefix("/") {
            targetUrl = URL(fileURLWithPath: urlStr)
          } else if !urlStr.isEmpty {
            targetUrl = URL(string: urlStr)
          } else {
            targetUrl = nil
          }

          if let url = targetUrl {
            self.startPip(with: url, positionMs: positionMs, speed: speed, result: result)
          } else if let controller = self.pipController, controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            result(["supported": true, "active": controller.isPictureInPictureActive, "requested": true])
          } else {
            result(["supported": true, "active": false, "requested": false])
          }
          return
        }
        guard call.method == "systemProxy" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
        func address(_ prefix: String) -> String {
          guard (settings["\(prefix)Enable"] as? NSNumber)?.boolValue == true,
                let host = settings["\(prefix)Proxy"] as? String,
                let port = settings["\(prefix)Port"] as? NSNumber,
                !host.isEmpty, port.intValue > 0 else { return "" }
          let name = host.contains(":") ? "[\(host)]" : host
          return "http://\(name):\(port.intValue)"
        }
        let http = address("HTTP")
        let https = address("HTTPS")
        result(["http": http, "https": https.isEmpty ? http : https,
                "bypass": settings["ExceptionsList"] as? [String] ?? [],
                "pac": (settings["ProxyAutoConfigEnable"] as? NSNumber)?.boolValue == true])
      }
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudSync") {
      let icloudChannel = FlutterMethodChannel(name: "duanju/icloud", binaryMessenger: registrar.messenger())
      self.icloudChannel = icloudChannel
      icloudChannel.setMethodCallHandler { call, result in
        let kv = NSUbiquitousKeyValueStore.default
        switch call.method {
        case "isAvailable":
          result(true)
        case "getString":
          let args = call.arguments as? [String: Any]
          let key = args?["key"] as? String ?? ""
          result(kv.string(forKey: key))
        case "setString":
          let args = call.arguments as? [String: Any]
          let key = args?["key"] as? String ?? ""
          let val = args?["value"] as? String ?? ""
          kv.set(val, forKey: key)
          kv.synchronize()
          result(true)
        case "remove":
          let args = call.arguments as? [String: Any]
          let key = args?["key"] as? String ?? ""
          kv.removeObject(forKey: key)
          kv.synchronize()
          result(true)
        case "synchronize":
          result(kv.synchronize())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: NSUbiquitousKeyValueStore.default,
        queue: .main
      ) { [weak self] _ in
        self?.icloudChannel?.invokeMethod("onICloudChanged", arguments: nil)
      }
    }
  }

  private func startPip(with url: URL, positionMs: Int, speed: Float, result: @escaping FlutterResult) {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}

    let playerItem = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: playerItem)
    self.pipPlayer = player

    if pipContainerView == nil {
      let view = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
      view.backgroundColor = .clear
      view.isUserInteractionEnabled = false
      view.alpha = 0.01
      self.window?.addSubview(view)
      self.pipContainerView = view
    }

    pipPlayerLayer?.removeFromSuperlayer()
    let layer = AVPlayerLayer(player: player)
    layer.frame = CGRect(x: 0, y: 0, width: 4, height: 4)
    pipContainerView?.layer.addSublayer(layer)
    self.pipPlayerLayer = layer

    let controller = AVPictureInPictureController(playerLayer: layer)
    self.pipController = controller
    controller?.delegate = self
    if #available(iOS 14.2, *) {
      controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    let seekTime = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
    player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      player.playImmediately(atRate: speed)
      controller?.startPictureInPicture()
      result(["supported": true, "active": true, "requested": true])
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": false])
    pipPlayer?.pause()
    pipPlayer = nil
    pipPlayerLayer?.removeFromSuperlayer()
    pipPlayerLayer = nil
    pipController = nil
  }
}
