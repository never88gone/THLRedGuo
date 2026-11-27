import AVFoundation
import AVKit
import Flutter
import UIKit

final class AirPlayCastBridge: NSObject, AVRoutePickerViewDelegate {
  private weak var channel: FlutterMethodChannel?
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var containerView: UIView?
  private var routePickerView: AVRoutePickerView?

  private var externalPlaybackObs: NSKeyValueObservation?
  private var timeControlObs: NSKeyValueObservation?
  private var itemStatusObs: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var statusTimer: Timer?
  private var cancelCheckTimer: Timer?

  private var currentRate: Float = 1.0
  private var currentEpisodeIndex: Int = 0
  private var hasActivatedExternal: Bool = false

  func bind(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "startAirPlayPicker":
      guard let args = call.arguments as? [String: Any],
            let urlStr = args["url"] as? String,
            let url = URL(string: urlStr) else {
        result(FlutterError(code: "INVALID_ARGS", message: "无效的视频投屏地址", details: nil))
        return
      }
      let headers = args["headers"] as? [String: String] ?? [:]
      let position = (args["position"] as? NSNumber)?.doubleValue ?? 0.0
      let rate = (args["rate"] as? NSNumber)?.floatValue ?? 1.0
      let episodeIndex = args["episodeIndex"] as? Int ?? 0
      startAirPlayPicker(
        url: url,
        headers: headers,
        position: position,
        rate: rate,
        episodeIndex: episodeIndex,
        result: result
      )
    case "replaceItem":
      guard let args = call.arguments as? [String: Any],
            let urlStr = args["url"] as? String,
            let url = URL(string: urlStr) else {
        result(FlutterError(code: "INVALID_ARGS", message: "无效的视频投屏地址", details: nil))
        return
      }
      let headers = args["headers"] as? [String: String] ?? [:]
      let position = (args["position"] as? NSNumber)?.doubleValue ?? 0.0
      let rate = (args["rate"] as? NSNumber)?.floatValue ?? currentRate
      let episodeIndex = args["episodeIndex"] as? Int ?? currentEpisodeIndex
      replaceItem(
        url: url,
        headers: headers,
        position: position,
        rate: rate,
        episodeIndex: episodeIndex,
        result: result
      )
    case "control":
      guard let args = call.arguments as? [String: Any],
            let action = args["action"] as? String else {
        result(false)
        return
      }
      handleControl(action: action, args: args, result: result)
    case "stop":
      stop()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func activeRootViewController() -> UIViewController? {
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

  private func configureAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
      try session.setActive(true)
    } catch {
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {}
    }
  }

  private func buildItem(url: URL, headers: [String: String]) -> AVPlayerItem {
    var options: [String: Any] = [:]
    if !url.isFileURL && !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: options)
    return AVPlayerItem(asset: asset)
  }

  private func startAirPlayPicker(
    url: URL,
    headers: [String: String],
    position: Double,
    rate: Float,
    episodeIndex: Int,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        result(false)
        return
      }
      self.stop(notifyFlutter: false)
      self.configureAudioSession()
      self.currentRate = rate > 0 ? rate : 1.0
      self.currentEpisodeIndex = episodeIndex
      self.hasActivatedExternal = false

      guard let rootVC = self.activeRootViewController() else {
        result(FlutterError(code: "NO_ROOT_VC", message: "未找到可用窗口", details: nil))
        return
      }

      let item = self.buildItem(url: url, headers: headers)
      let avPlayer = AVPlayer(playerItem: item)
      avPlayer.allowsExternalPlayback = true
      avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
      avPlayer.isMuted = true
      if #available(iOS 16.0, *) {
        avPlayer.preventsDisplaySleepDuringVideoPlayback = true
      }
      self.player = avPlayer

      let container = UIView(frame: CGRect(x: -4, y: -4, width: 2, height: 2))
      container.backgroundColor = .clear
      container.isUserInteractionEnabled = false
      rootVC.view.addSubview(container)
      self.containerView = container

      let layer = AVPlayerLayer(player: avPlayer)
      layer.frame = container.bounds
      container.layer.addSublayer(layer)
      self.playerLayer = layer

      self.observePlayer(avPlayer, item: item)

      if position > 0 {
        let target = CMTime(seconds: position, preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
      }

      if avPlayer.isExternalPlaybackActive {
        self.activateExternalPlayback(avPlayer)
      } else {
        avPlayer.play()
      }

      let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
      picker.delegate = self
      if #available(iOS 13.0, *) {
        picker.prioritizesVideoDevices = true
      }
      picker.alpha = 0.01
      rootVC.view.addSubview(picker)
      self.routePickerView = picker

      var triggered = false
      for sub in picker.subviews {
        if let btn = sub as? UIButton {
          btn.sendActions(for: .touchUpInside)
          triggered = true
          break
        }
      }
      result(triggered)
    }
  }

  private func replaceItem(
    url: URL,
    headers: [String: String],
    position: Double,
    rate: Float,
    episodeIndex: Int,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let avPlayer = self.player else {
        result(false)
        return
      }
      self.currentRate = rate > 0 ? rate : 1.0
      self.currentEpisodeIndex = episodeIndex
      let item = self.buildItem(url: url, headers: headers)
      self.observeItemStatusAndEnd(avPlayer, item: item)
      avPlayer.replaceCurrentItem(with: item)
      if position > 0 {
        let target = CMTime(seconds: position, preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
      }
      avPlayer.playImmediately(atRate: self.currentRate)
      result(true)
    }
  }

  private func observePlayer(_ avPlayer: AVPlayer, item: AVPlayerItem) {
    externalPlaybackObs = avPlayer.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] p, _ in
      DispatchQueue.main.async {
        guard let self, self.player === p else { return }
        if p.isExternalPlaybackActive {
          self.activateExternalPlayback(p)
        } else if self.hasActivatedExternal {
          let pos = self.safeSeconds(p.currentTime().seconds)
          self.stop(notifyFlutter: false)
          self.channel?.invokeMethod("onAirPlayStateChanged", arguments: [
            "active": false,
            "position": pos,
            "routeName": ""
          ])
        }
      }
    }

    timeControlObs = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.emitStatus()
      }
    }

    observeItemStatusAndEnd(avPlayer, item: item)
  }

  private func observeItemStatusAndEnd(_ avPlayer: AVPlayer, item: AVPlayerItem) {
    itemStatusObs?.invalidate()
    itemStatusObs = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
      DispatchQueue.main.async {
        guard let self else { return }
        if observed.status == .readyToPlay {
          self.emitStatus()
        } else if observed.status == .failed {
          self.channel?.invokeMethod("onAirPlayError", arguments: [
            "message": observed.error?.localizedDescription ?? "AirPlay 视频加载失败"
          ])
        }
      }
    }

    if let oldEnd = endObserver {
      NotificationCenter.default.removeObserver(oldEnd)
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self, self.hasActivatedExternal else { return }
      self.channel?.invokeMethod("onAirPlayEnded", arguments: [
        "episodeIndex": self.currentEpisodeIndex
      ])
    }
  }

  private func activateExternalPlayback(_ avPlayer: AVPlayer) {
    cancelCheckTimer?.invalidate()
    cancelCheckTimer = nil
    hasActivatedExternal = true
    avPlayer.isMuted = false
    avPlayer.playImmediately(atRate: currentRate)
    startStatusTimer()
    channel?.invokeMethod("onAirPlayStateChanged", arguments: [
      "active": true,
      "routeName": currentAirPlayRouteName(),
      "position": safeSeconds(avPlayer.currentTime().seconds)
    ])
    emitStatus()
  }

  private func currentAirPlayRouteName() -> String {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    for out in outputs where out.portType == .airPlay {
      if !out.portName.isEmpty {
        return out.portName
      }
    }
    return "AirPlay 设备"
  }

  private func handleControl(action: String, args: [String: Any], result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let avPlayer = self.player else {
        result(false)
        return
      }
      switch action {
      case "play":
        avPlayer.playImmediately(atRate: self.currentRate)
      case "pause":
        avPlayer.pause()
      case "seek":
        let pos = (args["position"] as? NSNumber)?.doubleValue ?? 0.0
        let target = CMTime(seconds: max(0, pos), preferredTimescale: 600)
        avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
          DispatchQueue.main.async {
            self.emitStatus()
          }
        }
      case "rate":
        let rate = (args["rate"] as? NSNumber)?.floatValue ?? 1.0
        self.currentRate = rate > 0 ? rate : 1.0
        if avPlayer.timeControlStatus != .paused {
          avPlayer.rate = self.currentRate
        }
      case "volume":
        let vol = (args["volume"] as? NSNumber)?.floatValue ?? 1.0
        avPlayer.volume = min(1.0, max(0.0, vol))
      case "stop":
        self.stop(notifyFlutter: false)
      default:
        result(false)
        return
      }
      self.emitStatus()
      result(true)
    }
  }

  private func startStatusTimer() {
    statusTimer?.invalidate()
    statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.emitStatus()
    }
  }

  private func emitStatus() {
    guard hasActivatedExternal, let avPlayer = player else { return }
    let pos = safeSeconds(avPlayer.currentTime().seconds)
    let durRaw = avPlayer.currentItem?.duration.seconds ?? 0
    let dur = (durRaw.isFinite && durRaw > 0) ? durRaw : 0.0
    let stateCode: Int
    switch avPlayer.timeControlStatus {
    case .waitingToPlayAtSpecifiedRate:
      stateCode = 1
    case .playing:
      stateCode = 2
    case .paused:
      stateCode = 3
    @unknown default:
      stateCode = 0
    }
    channel?.invokeMethod("airPlayStatus", arguments: [
      "state": stateCode,
      "position": pos,
      "duration": dur,
      "volume": Double(avPlayer.volume),
      "rate": Double(avPlayer.rate > 0 ? avPlayer.rate : currentRate)
    ])
  }

  private func safeSeconds(_ value: Double) -> Double {
    (value.isFinite && value >= 0) ? value : 0.0
  }

  func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
    cancelCheckTimer?.invalidate()
    cancelCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
      guard let self else { return }
      if !(self.player?.isExternalPlaybackActive ?? false) && !self.hasActivatedExternal {
        self.stop(notifyFlutter: false)
        self.channel?.invokeMethod("onAirPlayCancelled", arguments: nil)
      }
    }
  }

  func stop(notifyFlutter: Bool = false) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.stop(notifyFlutter: notifyFlutter)
      }
      return
    }
    let lastPos = safeSeconds(player?.currentTime().seconds ?? 0)
    statusTimer?.invalidate()
    statusTimer = nil
    cancelCheckTimer?.invalidate()
    cancelCheckTimer = nil
    externalPlaybackObs?.invalidate()
    externalPlaybackObs = nil
    timeControlObs?.invalidate()
    timeControlObs = nil
    itemStatusObs?.invalidate()
    itemStatusObs = nil
    if let observer = endObserver {
      NotificationCenter.default.removeObserver(observer)
      endObserver = nil
    }
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    containerView?.removeFromSuperview()
    containerView = nil
    routePickerView?.removeFromSuperview()
    routePickerView = nil
    hasActivatedExternal = false
    if notifyFlutter {
      channel?.invokeMethod("onAirPlayStateChanged", arguments: [
        "active": false,
        "position": lastPos,
        "routeName": ""
      ])
    }
  }
}
