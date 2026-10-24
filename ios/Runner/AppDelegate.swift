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
  private var pipObservation: NSKeyValueObservation?
  private var pipItemStatusObservation: NSKeyValueObservation?
  private var pipTimeoutWorkItem: DispatchWorkItem?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}
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
          self.ensureAudioSessionConfigured()
          let supported = AVPictureInPictureController.isPictureInPictureSupported()
          let active = self.pipController?.isPictureInPictureActive ?? false
          result([
            "supported": supported,
            "active": active
          ])
          return
        }
        if call.method == "enterPictureInPicture" {
          self.ensureAudioSessionConfigured()
          let supported = AVPictureInPictureController.isPictureInPictureSupported()
          guard supported else {
            result(["supported": false, "active": false, "requested": false, "error": "当前设备或系统未支持画中画功能"])
            return
          }
          let args = call.arguments as? [String: Any]
          let urlStr = args?["url"] as? String ?? ""
          let headers = args?["headers"] as? [String: String] ?? [:]
          let positionMs = args?["position"] as? Int ?? 0
          let speed = (args?["speed"] as? NSNumber)?.floatValue ?? 1.0

          let targetUrl = self.parseMediaUrl(urlStr)

          if let url = targetUrl {
            self.startPip(with: url, headers: headers, positionMs: positionMs, speed: speed, result: result)
          } else if let controller = self.pipController, controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            result(["supported": true, "active": false, "requested": true])
          } else {
            result([
              "supported": true,
              "active": false,
              "requested": false,
              "error": urlStr.isEmpty ? "未找到当前播放的视频地址" : "视频地址解析失败，请检查播放状态"
            ])
          }
          return
        }
        if call.method == "stopPictureInPicture" {
          let positionMs = Int((self.pipPlayer?.currentTime().seconds ?? 0) * 1000)
          self.pipController?.stopPictureInPicture()
          self.cleanUpPip()
          result(["stopped": true, "position": positionMs])
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

  private func ensureAudioSessionConfigured() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .moviePlayback)
      try audioSession.setActive(true)
    } catch {
      NSLog("[PiP] ensureAudioSessionConfigured failed: %@", error.localizedDescription)
    }
  }

  private func parseMediaUrl(_ urlStr: String) -> URL? {
    let clean = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    if clean.hasPrefix("/") {
      return URL(fileURLWithPath: clean)
    }
    if let direct = URL(string: clean) {
      return direct
    }
    if let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
       let parsed = URL(string: encoded) {
      return parsed
    }
    let fixed = clean
      .replacingOccurrences(of: "|", with: "%7C")
      .replacingOccurrences(of: " ", with: "%20")
      .replacingOccurrences(of: "^", with: "%5E")
      .replacingOccurrences(of: "`", with: "%60")
      .replacingOccurrences(of: "{", with: "%7B")
      .replacingOccurrences(of: "}", with: "%7D")
    return URL(string: fixed)
  }

  private var activeRootViewController: UIViewController? {
    if let root = self.window?.rootViewController {
      return root
    }
    if #available(iOS 13.0, *) {
      for scene in UIApplication.shared.connectedScenes {
        if let windowScene = scene as? UIWindowScene {
          for window in windowScene.windows where window.isKeyWindow || window.rootViewController != nil {
            if let root = window.rootViewController {
              return root
            }
          }
        }
      }
    }
    return UIApplication.shared.keyWindow?.rootViewController
  }

  private func cleanUpPip() {
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    self.pipObservation?.invalidate()
    self.pipObservation = nil
    self.pipItemStatusObservation?.invalidate()
    self.pipItemStatusObservation = nil
    self.pipPlayer?.pause()
    self.pipPlayer = nil
    self.pipPlayerLayer?.removeFromSuperlayer()
    self.pipPlayerLayer = nil
    self.pipContainerView?.removeFromSuperview()
    self.pipContainerView = nil
    self.pipController = nil
  }

  private func startPip(with url: URL, headers: [String: String], positionMs: Int, speed: Float, result: @escaping FlutterResult) {
    ensureAudioSessionConfigured()
    self.cleanUpPip()

    var assetOptions: [String: Any] = [:]
    if !headers.isEmpty {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: assetOptions)
    let playerItem = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: playerItem)
    player.actionAtItemEnd = .none
    if #available(iOS 16.0, *) {
      player.preventsDisplaySleepDuringVideoPlayback = true
    }
    self.pipPlayer = player

    guard let rootVC = self.activeRootViewController else {
      result([
        "supported": true,
        "active": false,
        "requested": false,
        "error": "无法获取应用窗口视图，请在界面显示后重试"
      ])
      return
    }

    var targetBounds = rootVC.view.bounds
    if targetBounds.width <= 0 || targetBounds.height <= 0 {
      targetBounds = UIScreen.main.bounds
    }

    // 宿主容器挂载于顶层并保留微透明度以确保参与 CoreAnimation 屏幕合成
    let view = UIView(frame: targetBounds)
    view.backgroundColor = UIColor.black.withAlphaComponent(0.005)
    view.isUserInteractionEnabled = false
    rootVC.view.addSubview(view)
    self.pipContainerView = view

    let layer = AVPlayerLayer(player: player)
    layer.frame = targetBounds
    layer.videoGravity = .resizeAspect
    view.layer.addSublayer(layer)
    self.pipPlayerLayer = layer

    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      self.cleanUpPip()
      result([
        "supported": false,
        "active": false,
        "requested": false,
        "error": "当前设备或系统暂不支持画中画功能"
      ])
      return
    }

    let controller = AVPictureInPictureController(playerLayer: layer)
    self.pipController = controller
    controller?.delegate = self
    if #available(iOS 14.2, *) {
      controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    var hasStartedPip = false
    let triggerPip: () -> Void = { [weak self] in
      guard let self = self, !hasStartedPip else { return }
      guard let pipCtrl = self.pipController else { return }
      self.pipPlayer?.playImmediately(atRate: speed)

      if pipCtrl.isPictureInPicturePossible {
        hasStartedPip = true
        pipCtrl.startPictureInPicture()
      } else {
        self.pipObservation?.invalidate()
        self.pipObservation = pipCtrl.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] c, change in
          guard let self = self else { return }
          if change.newValue == true && !hasStartedPip {
            hasStartedPip = true
            c.startPictureInPicture()
            self.pipObservation?.invalidate()
            self.pipObservation = nil
          }
        }
      }
    }

    // 监听 playerItem 状态，在 readyToPlay 时进行 seek 和触发
    self.pipItemStatusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
      guard let self = self else { return }
      switch item.status {
      case .readyToPlay:
        self.pipItemStatusObservation?.invalidate()
        self.pipItemStatusObservation = nil
        if positionMs > 0 {
          let seekTime = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
          player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
              triggerPip()
            }
          }
        } else {
          DispatchQueue.main.async {
            triggerPip()
          }
        }
      case .failed:
        self.pipItemStatusObservation?.invalidate()
        self.pipItemStatusObservation = nil
        let errorMsg = item.error?.localizedDescription ?? "视频加载异常"
        NSLog("[PiP] AVPlayerItem failed: %@", errorMsg)
        self.cleanUpPip()
        self.deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: [
          "active": false,
          "error": "画中画视频加载失败: \(errorMsg)"
        ])
      case .unknown:
        break
      @unknown default:
        break
      }
    }

    // 8 秒超时保护
    let timeoutItem = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if !(self.pipController?.isPictureInPictureActive ?? false) {
        NSLog("[PiP] Start PiP timeout (8s)")
        self.cleanUpPip()
        self.deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: [
          "active": false,
          "error": "启动画中画未就绪，请检查网络或系统画中画设置"
        ])
      }
    }
    self.pipTimeoutWorkItem = timeoutItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: timeoutItem)

    result(["supported": true, "active": false, "requested": true])
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    self.pipObservation?.invalidate()
    self.pipObservation = nil
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": true])
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let positionMs = Int((pipPlayer?.currentTime().seconds ?? 0) * 1000)
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": false, "position": positionMs])
    cleanUpPip()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": false, "error": error.localizedDescription])
    cleanUpPip()
  }
}
