import Cocoa
import FlutterMacOS
import Security

@main
class AppDelegate: FlutterAppDelegate {
  private var icloudChannel: FlutterMethodChannel?

  private func hasICloudEntitlement() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else {
      return false
    }
    let value = SecTaskCopyValueForEntitlement(
      task,
      "com.apple.developer.ubiquity-kvstore-identifier" as CFString,
      nil
    )
    return value != nil
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "duanju/icloud", binaryMessenger: controller.engine.binaryMessenger)
      self.icloudChannel = channel
      let icloudEntitled = hasICloudEntitlement()
      channel.setMethodCallHandler { call, result in
        guard icloudEntitled else {
          switch call.method {
          case "isAvailable", "synchronize":
            result(false)
          case "getString":
            result(nil)
          case "setString", "remove":
            result(false)
          default:
            result(FlutterMethodNotImplemented)
          }
          return
        }
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

      if icloudEntitled {
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
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

