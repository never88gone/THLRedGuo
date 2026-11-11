import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidDisconnect(_ scene: UIScene) {
    let hasRemainingScenes = UIApplication.shared.connectedScenes.contains { $0 !== scene }
    if !hasRemainingScenes {
      THLAppLifecycleGuard.markEngineStopping()
      (UIApplication.shared.delegate as? AppDelegate)?.handleSceneTeardown()
    }
    super.sceneDidDisconnect(scene)
  }
}
