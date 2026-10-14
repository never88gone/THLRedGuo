import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 屏幕常亮与防息屏/锁屏控制器
/// 用于在离线下载、短剧播放或长效运行过程中保持屏幕常亮，防止系统休眠。
class ScreenWakeController extends ChangeNotifier {
  ScreenWakeController._();

  static final ScreenWakeController instance = ScreenWakeController._();

  bool _isWakeLocked = false;
  bool get isWakeLocked => _isWakeLocked;

  /// 根据配置同步屏幕锁状态
  Future<void> sync(bool keepScreenOn) async {
    try {
      if (keepScreenOn) {
        await WakelockPlus.enable();
        _isWakeLocked = true;
      } else {
        await WakelockPlus.disable();
        _isWakeLocked = false;
      }
      notifyListeners();
    } catch (_) {
      // 容错处理：在非真机测试环境或不支持平台忽略异常
      _isWakeLocked = keepScreenOn;
      notifyListeners();
    }
  }

  /// 当应用切回前台时，恢复屏幕常亮状态
  Future<void> handleAppResume(bool keepScreenOn) async {
    if (keepScreenOn) {
      await sync(true);
    }
  }
}
