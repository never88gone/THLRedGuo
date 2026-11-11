import Flutter
import UIKit
import XCTest
@testable import Runner

private final class MockBinaryMessenger: NSObject, FlutterBinaryMessenger {
  var sentMessages: [(channel: String, message: Data?, isMainThread: Bool)] = []
  var replyDataToReturn: Data?
  var exceptionToRaise: NSException?

  func send(onChannel channel: String, message: Data?) {
    if let exception = exceptionToRaise {
      exception.raise()
    }
    sentMessages.append((channel, message, Thread.isMainThread))
  }

  func send(
    onChannel channel: String,
    message: Data?,
    binaryReply callback: FlutterBinaryReply? = nil
  ) {
    if let exception = exceptionToRaise {
      exception.raise()
    }
    sentMessages.append((channel, message, Thread.isMainThread))
    callback?(replyDataToReturn)
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection {
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

private final class MockTextureRegistry: NSObject, FlutterTextureRegistry {
  func register(_ texture: any FlutterTexture) -> Int64 { 1 }
  func textureFrameAvailable(_ textureId: Int64) {}
  func unregisterTexture(_ textureId: Int64) {}
}

private final class MockPluginRegistrar: NSObject, FlutterPluginRegistrar {
  let mockMessenger: MockBinaryMessenger
  let mockTextures = MockTextureRegistry()
  var appDelegateAddedCount = 0
  var sceneDelegateAddedCount = 0
  var methodDelegateAddedCount = 0

  init(messenger: MockBinaryMessenger) {
    self.mockMessenger = messenger
    super.init()
  }

  var viewController: UIViewController? { nil }

  func messenger() -> any FlutterBinaryMessenger & NSObjectProtocol {
    mockMessenger
  }

  func textures() -> any FlutterTextureRegistry & NSObjectProtocol {
    mockTextures
  }

  func register(_ factory: any FlutterPlatformViewFactory, withId factoryId: String) {}

  func register(
    _ factory: any FlutterPlatformViewFactory,
    withId factoryId: String,
    gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy
  ) {}

  func publish(_ value: NSObject) {}

  func addMethodCallDelegate(_ delegate: any FlutterPlugin, channel: FlutterMethodChannel) {
    methodDelegateAddedCount += 1
  }

  func addApplicationDelegate(_ delegate: any FlutterPlugin) {
    appDelegateAddedCount += 1
  }

  func addSceneDelegate(_ delegate: any FlutterSceneLifeCycleDelegate) {
    sceneDelegateAddedCount += 1
  }

  func lookupKey(forAsset asset: String) -> String { asset }

  func lookupKey(forAsset asset: String, fromPackage package: String) -> String {
    "\(package)/\(asset)"
  }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? { nil }
}

private final class MockPluginRegistry: NSObject, FlutterPluginRegistry {
  var registrars: [String: MockPluginRegistrar] = [:]

  func registrar(forPlugin pluginKey: String) -> (any FlutterPluginRegistrar)? {
    if let existing = registrars[pluginKey] {
      return existing
    }
    let created = MockPluginRegistrar(messenger: MockBinaryMessenger())
    registrars[pluginKey] = created
    return created
  }

  func hasPlugin(_ pluginKey: String) -> Bool {
    registrars[pluginKey] != nil
  }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? { nil }
}

private final class DummyPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static func register(with registrar: any FlutterPluginRegistrar) {}
}

final class RunnerTests: XCTestCase {
  override func setUp() {
    super.setUp()
    THLAppLifecycleGuard.markEngineActive()
  }

  override func tearDown() {
    THLAppLifecycleGuard.markEngineActive()
    super.tearDown()
  }

  func testLifecycleGuardTogglesStoppingAndActive() {
    XCTAssertFalse(THLAppLifecycleGuard.isEngineStopping())
    THLAppLifecycleGuard.markEngineStopping()
    XCTAssertTrue(THLAppLifecycleGuard.isEngineStopping())
    THLAppLifecycleGuard.markEngineActive()
    XCTAssertFalse(THLAppLifecycleGuard.isEngineStopping())
  }

  func testSafePluginRegistryBlocksDisabledPluginLifecycleDelegates() {
    let mockRegistry = MockPluginRegistry()
    let safeRegistry = SafePluginRegistry(
      target: mockRegistry,
      disabledLifecyclePlugins: ["FlutterForegroundTaskPlugin"]
    )
    let plugin = DummyPlugin()

    let fgRegistrar = safeRegistry.registrar(forPlugin: "FlutterForegroundTaskPlugin")
    XCTAssertNotNil(fgRegistrar)
    let fgChannel = FlutterMethodChannel(name: "test/fg", binaryMessenger: fgRegistrar!.messenger())
    fgRegistrar?.addApplicationDelegate(plugin)
    fgRegistrar?.addSceneDelegate(plugin)
    fgRegistrar?.addMethodCallDelegate(plugin, channel: fgChannel)

    let fgUnderlying = mockRegistry.registrars["FlutterForegroundTaskPlugin"]
    XCTAssertEqual(fgUnderlying?.appDelegateAddedCount, 0)
    XCTAssertEqual(fgUnderlying?.sceneDelegateAddedCount, 0)
    XCTAssertEqual(fgUnderlying?.methodDelegateAddedCount, 1)

    let videoRegistrar = safeRegistry.registrar(forPlugin: "VideoPlayerPlugin")
    XCTAssertNotNil(videoRegistrar)
    let videoChannel = FlutterMethodChannel(name: "test/video", binaryMessenger: videoRegistrar!.messenger())
    videoRegistrar?.addApplicationDelegate(plugin)
    videoRegistrar?.addSceneDelegate(plugin)
    videoRegistrar?.addMethodCallDelegate(plugin, channel: videoChannel)

    let videoUnderlying = mockRegistry.registrars["VideoPlayerPlugin"]
    XCTAssertEqual(videoUnderlying?.appDelegateAddedCount, 1)
    XCTAssertEqual(videoUnderlying?.sceneDelegateAddedCount, 1)
    XCTAssertEqual(videoUnderlying?.methodDelegateAddedCount, 1)
    XCTAssertTrue(videoRegistrar?.messenger() is SafeBinaryMessengerProxy)
  }

  func testSafeBinaryMessengerDispatchesBackgroundSendToMainThread() {
    let target = MockBinaryMessenger()
    let expectedReply = Data([1, 2, 3])
    target.replyDataToReturn = expectedReply
    let proxy = SafeBinaryMessengerProxy(target: target)

    let sendExpectation = expectation(description: "background send forwarded on main thread")
    let replyExpectation = expectation(description: "background sendWithReply forwarded on main thread")

    DispatchQueue.global().async {
      proxy.send(onChannel: "test/bg", message: Data([42]))
      proxy.send(onChannel: "test/bg_reply", message: Data([99])) { reply in
        XCTAssertEqual(reply, expectedReply)
        replyExpectation.fulfill()
      }
      DispatchQueue.main.async {
        sendExpectation.fulfill()
      }
    }

    wait(for: [sendExpectation, replyExpectation], timeout: 5.0)
    XCTAssertEqual(target.sentMessages.count, 2)
    XCTAssertTrue(target.sentMessages.allSatisfy { $0.isMainThread })
  }

  func testSafeBinaryMessengerBlocksMessagesWhenEngineStopping() {
    let target = MockBinaryMessenger()
    target.replyDataToReturn = Data([7, 8, 9])
    let proxy = SafeBinaryMessengerProxy(target: target)

    THLAppLifecycleGuard.markEngineStopping()

    proxy.send(onChannel: "test/stopped", message: Data([1]))
    let replyExpectation = expectation(description: "reply receives nil when stopping")
    proxy.send(onChannel: "test/stopped_reply", message: Data([2])) { reply in
      XCTAssertNil(reply)
      replyExpectation.fulfill()
    }

    wait(for: [replyExpectation], timeout: 2.0)
    XCTAssertTrue(target.sentMessages.isEmpty)
  }

  func testSafeBinaryMessengerCatchesEngineNotRunningException() {
    let target = MockBinaryMessenger()
    target.exceptionToRaise = NSException(
      name: .internalInconsistencyException,
      reason: "Sending a message before the FlutterEngine has been run.",
      userInfo: nil
    )
    let proxy = SafeBinaryMessengerProxy(target: target)

    proxy.send(onChannel: "test/exception", message: Data([1]))

    let replyExpectation = expectation(description: "exception falls back cleanly to nil reply")
    proxy.send(onChannel: "test/exception_reply", message: Data([2])) { reply in
      XCTAssertNil(reply)
      replyExpectation.fulfill()
    }

    wait(for: [replyExpectation], timeout: 2.0)
    XCTAssertTrue(target.sentMessages.isEmpty)
  }
}
