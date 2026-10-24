import Flutter
import UIKit
import CFNetwork
import AVKit
import AVFoundation
import CoreMedia

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVPictureInPictureControllerDelegate {
  private let encryptedMediaStream = EncryptedMediaStream()
  private var pipController: AVPictureInPictureController?
  private var pipPlayer: AVPlayer?
  private var pipPlayerLayer: AVPlayerLayer?
  private var pipContainerView: UIView?
  private var deviceChannel: FlutterMethodChannel?
  private var icloudChannel: FlutterMethodChannel?
  private var pipObservation: NSKeyValueObservation?
  private var pipItemStatusObservation: NSKeyValueObservation?
  private var pipReadyForDisplayObservation: NSKeyValueObservation?
  private var pipTimeoutWorkItem: DispatchWorkItem?
  private var pipCheckTimer: Timer?
  private var currentPipDramaId: String?
  private var currentPipEpisodeIndex: Int = 0
  private var currentPipMetadata: [String: Any]?
  private var pipEndObserver: NSObjectProtocol?
  private var pipReplaceStatusObservation: NSKeyValueObservation?

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EncryptedMediaStream") {
      let channel = FlutterMethodChannel(name: "duanju/encrypted_stream", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.encryptedMediaStream.handle(call, result: result)
      }
    }
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

          self.currentPipDramaId = args?["dramaId"] as? String
          self.currentPipEpisodeIndex = args?["episodeIndex"] as? Int ?? 0
          self.currentPipMetadata = args?["detail"] as? [String: Any]

          let sourceX = (args?["x"] as? NSNumber)?.doubleValue
          let sourceY = (args?["y"] as? NSNumber)?.doubleValue
          let sourceW = (args?["width"] as? NSNumber)?.doubleValue
          let sourceH = (args?["height"] as? NSNumber)?.doubleValue
          var sourceRect: CGRect? = nil
          if let x = sourceX, let y = sourceY, let w = sourceW, let h = sourceH, w > 0, h > 0 {
            sourceRect = CGRect(x: x, y: y, width: w, height: h)
          }

          let targetUrl = self.parseMediaUrl(urlStr)

          if let url = targetUrl {
            self.startPip(with: url, headers: headers, positionMs: positionMs, speed: speed, sourceRect: sourceRect, result: result)
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
        if call.method == "replacePictureInPictureItem" {
          let args = call.arguments as? [String: Any]
          let urlStr = args?["url"] as? String ?? ""
          let headers = args?["headers"] as? [String: String] ?? [:]
          let episodeIndex = args?["episodeIndex"] as? Int ?? self.currentPipEpisodeIndex
          let speed = (args?["speed"] as? NSNumber)?.floatValue ?? 1.0
          guard let url = self.parseMediaUrl(urlStr) else {
            result(["replaced": false, "error": "视频地址解析失败"])
            return
          }
          self.replacePipItem(with: url, headers: headers, episodeIndex: episodeIndex, speed: speed, result: result)
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
          result(true)
        case "remove":
          let args = call.arguments as? [String: Any]
          let key = args?["key"] as? String ?? ""
          kv.removeObject(forKey: key)
          result(true)
        case "synchronize":
          result(kv.synchronize())
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      NotificationCenter.default.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        self?.icloudChannel?.invokeMethod("onICloudChanged", arguments: ["reason": reason ?? 0])
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
    if clean.hasPrefix("file://") {
      let path = String(clean.dropFirst(7))
      return URL(fileURLWithPath: path)
    }
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

  private func logPip(_ message: String) {
    NSLog("[PiP-Native] %@", message)
    DispatchQueue.main.async { [weak self] in
      self?.deviceChannel?.invokeMethod("pipLog", arguments: message)
    }
  }

  private func cleanUpPip() {
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    self.pipCheckTimer?.invalidate()
    self.pipCheckTimer = nil
    self.pipObservation?.invalidate()
    self.pipObservation = nil
    self.pipReadyForDisplayObservation?.invalidate()
    self.pipReadyForDisplayObservation = nil
    self.pipItemStatusObservation?.invalidate()
    self.pipItemStatusObservation = nil
    self.pipReplaceStatusObservation?.invalidate()
    self.pipReplaceStatusObservation = nil
    if let observer = self.pipEndObserver {
      NotificationCenter.default.removeObserver(observer)
      self.pipEndObserver = nil
    }
    self.pipPlayer?.pause()
    self.pipPlayer = nil
    self.pipPlayerLayer?.removeFromSuperlayer()
    self.pipPlayerLayer = nil
    self.pipContainerView?.removeFromSuperview()
    self.pipContainerView = nil
    self.pipController = nil
  }

  private func observePipItemEnd(_ item: AVPlayerItem) {
    if let observer = self.pipEndObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    self.pipEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self = self, self.pipController?.isPictureInPictureActive ?? false else { return }
      self.logPip("PiP item reached end: episode=\(self.currentPipEpisodeIndex)")
      self.deviceChannel?.invokeMethod("pictureInPictureEnded", arguments: [
        "episodeIndex": self.currentPipEpisodeIndex
      ])
    }
  }

  private func replacePipItem(
    with url: URL,
    headers: [String: String],
    episodeIndex: Int,
    speed: Float,
    result: @escaping FlutterResult
  ) {
    guard let player = self.pipPlayer, self.pipController?.isPictureInPictureActive ?? false else {
      result(["replaced": false, "error": "画中画已关闭"])
      return
    }
    logPip("replacePipItem: episode=\(episodeIndex), url=\(url.absoluteString)")
    var assetOptions: [String: Any] = [:]
    if !url.isFileURL && !headers.isEmpty {
      assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: assetOptions))
    self.pipReplaceStatusObservation?.invalidate()
    self.pipReplaceStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch observed.status {
        case .readyToPlay:
          self.pipReplaceStatusObservation?.invalidate()
          self.pipReplaceStatusObservation = nil
          self.pipPlayer?.playImmediately(atRate: speed)
        case .failed:
          self.pipReplaceStatusObservation?.invalidate()
          self.pipReplaceStatusObservation = nil
          let message = observed.error?.localizedDescription ?? "视频加载异常"
          self.logPip("replacePipItem failed: \(message)")
          self.deviceChannel?.invokeMethod("pictureInPictureItemFailed", arguments: [
            "episodeIndex": episodeIndex,
            "error": message
          ])
        default:
          break
        }
      }
    }
    self.currentPipEpisodeIndex = episodeIndex
    self.observePipItemEnd(item)
    player.replaceCurrentItem(with: item)
    player.playImmediately(atRate: speed)
    result(["replaced": true])
  }

  private func startPip(
    with url: URL,
    headers: [String: String],
    positionMs: Int,
    speed: Float,
    sourceRect: CGRect?,
    result: @escaping FlutterResult
  ) {
    logPip("startPip: url=\(url.absoluteString), pos=\(positionMs), speed=\(speed), sourceRect=\(String(describing: sourceRect))")
    ensureAudioSessionConfigured()
    self.cleanUpPip()

    var assetOptions: [String: Any] = [:]
    if !url.isFileURL && !headers.isEmpty {
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
    self.observePipItemEnd(playerItem)

    guard let rootVC = self.activeRootViewController else {
      result([
        "supported": true,
        "active": false,
        "requested": false,
        "error": "无法获取应用窗口视图，请在界面显示后重试"
      ])
      return
    }

    let targetBounds = sourceRect ?? rootVC.view.bounds

    let view = UIView(frame: targetBounds)
    view.backgroundColor = .black
    view.alpha = 0
    view.isUserInteractionEnabled = false
    rootVC.view.addSubview(view)
    self.pipContainerView = view

    let layer = AVPlayerLayer(player: player)
    layer.frame = view.bounds
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
    let attemptStartPip: () -> Void = { [weak self] in
      guard let self = self, !hasStartedPip else { return }
      guard let pipCtrl = self.pipController else { return }

      let isPossible = pipCtrl.isPictureInPicturePossible
      let isReady = self.pipPlayerLayer?.isReadyForDisplay ?? false
      self.logPip("attemptStartPip check: isPossible=\(isPossible), isReadyForDisplay=\(isReady)")

      guard isPossible && isReady else {
        return
      }

      hasStartedPip = true
      self.logPip("Calling pipCtrl.startPictureInPicture() with layer ready!")
      self.pipCheckTimer?.invalidate()
      self.pipCheckTimer = nil
      self.pipObservation?.invalidate()
      self.pipObservation = nil
      self.pipReadyForDisplayObservation?.invalidate()
      self.pipReadyForDisplayObservation = nil

      self.pipContainerView?.alpha = 1.0
      self.ensureAudioSessionConfigured()
      pipCtrl.startPictureInPicture()
    }

    // 监听 playerItem 状态，在 readyToPlay 时进行 seek 和播放
    self.pipItemStatusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
      guard let self = self else { return }
      switch item.status {
      case .readyToPlay:
        self.pipItemStatusObservation?.invalidate()
        self.pipItemStatusObservation = nil

        var hasTriggeredPlay = false
        let beginPlayAndObserve = { [weak self] in
          guard let self = self, !hasTriggeredPlay else { return }
          hasTriggeredPlay = true
          self.logPip("beginPlayAndObserve: start playing and observing")
          self.pipPlayer?.playImmediately(atRate: speed)

          // 1. 监听 isReadyForDisplay：首帧画面渲染到屏幕
          self.pipReadyForDisplayObservation = self.pipPlayerLayer?.observe(\.isReadyForDisplay, options: [.new, .initial]) { _, _ in
            DispatchQueue.main.async {
              attemptStartPip()
            }
          }

          // 2. 监听 isPictureInPicturePossible：系统通道就绪
          self.pipObservation = self.pipController?.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { _, _ in
            DispatchQueue.main.async {
              attemptStartPip()
            }
          }

          // 3. 轻量轮询保底（每 200ms 检测一次）
          self.pipCheckTimer?.invalidate()
          self.pipCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
              timer.invalidate()
              return
            }
            if hasStartedPip || (self.pipController?.isPictureInPictureActive ?? false) {
              timer.invalidate()
            } else {
              attemptStartPip()
            }
          }
        }

        if positionMs > 0 {
          let seekTime = CMTime(value: CMTimeValue(positionMs), timescale: 1000)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            beginPlayAndObserve()
          }
          let tolerance = CMTime(value: 500, timescale: 1000)
          player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            DispatchQueue.main.async {
              beginPlayAndObserve()
            }
          }
        } else {
          DispatchQueue.main.async {
            beginPlayAndObserve()
          }
        }
      case .failed:
        self.pipItemStatusObservation?.invalidate()
        self.pipItemStatusObservation = nil
        let errorMsg = item.error?.localizedDescription ?? "视频加载异常"
        self.logPip("AVPlayerItem failed: \(errorMsg)")
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
        self.logPip("Start PiP timeout (8s)")
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
    logPip("didStartPictureInPicture triggered successfully!")
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    self.pipCheckTimer?.invalidate()
    self.pipCheckTimer = nil
    self.pipObservation?.invalidate()
    self.pipObservation = nil
    self.pipReadyForDisplayObservation?.invalidate()
    self.pipReadyForDisplayObservation = nil
    self.pipContainerView?.isHidden = true
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": true])
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    let positionMs = Int((pipPlayer?.currentTime().seconds ?? 0) * 1000)
    logPip("restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: pos=\(positionMs)")
    var args: [String: Any] = [
      "position": positionMs,
      "episodeIndex": self.currentPipEpisodeIndex
    ]
    if let dramaId = self.currentPipDramaId {
      args["dramaId"] = dramaId
    }
    if let metadata = self.currentPipMetadata {
      args["detail"] = metadata
    }
    deviceChannel?.invokeMethod("restorePictureInPictureUI", arguments: args, result: { _ in
      completionHandler(true)
    })
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let positionMs = Int((pipPlayer?.currentTime().seconds ?? 0) * 1000)
    logPip("didStopPictureInPicture at pos=\(positionMs)")
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": false, "position": positionMs])
    cleanUpPip()
    self.currentPipDramaId = nil
    self.currentPipMetadata = nil
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    let err = error as NSError
    logPip("failedToStartPictureInPictureWithError: domain=\(err.domain), code=\(err.code), desc=\(err.localizedDescription), userInfo=\(err.userInfo)")
    self.pipTimeoutWorkItem?.cancel()
    self.pipTimeoutWorkItem = nil
    self.cleanUpPip()
    deviceChannel?.invokeMethod("pictureInPictureChanged", arguments: ["active": false, "error": error.localizedDescription])
  }
}
