import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端（macOS / Windows / Linux）置顶迷你画中画控制器
/// 负责管理桌面端小窗模式下的置顶、尺寸自适应吸附与原窗口几何属性恢复
class DesktopPipController extends ChangeNotifier {
  DesktopPipController._();
  static final DesktopPipController instance = DesktopPipController._();

  bool _active = false;
  Rect? _savedBounds;
  bool _savedAlwaysOnTop = false;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool get isActive => _active;

  /// 进入桌面迷你置顶画中画模式
  Future<bool> enterPip({double aspectRatio = 9 / 16}) async {
    if (!isSupported || _active) return false;
    try {
      final isFull = await windowManager.isFullScreen();
      if (isFull) {
        await windowManager.setFullScreen(false);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      _savedBounds = await windowManager.getBounds();
      _savedAlwaysOnTop = await windowManager.isAlwaysOnTop();

      // 计算迷你窗口尺寸：短剧默认竖屏黄金比例，宽度 360，高度根据比例换算
      double width = 360;
      double height = width / (aspectRatio > 0 ? aspectRatio : (9 / 16));
      if (aspectRatio > 1.2) {
        // 横屏视频小窗
        width = 480;
        height = width / aspectRatio;
      } else {
        // 竖屏短剧小窗，高度限制在 640
        if (height > 640) {
          height = 640;
          width = height * (aspectRatio > 0 ? aspectRatio : (9 / 16));
        }
      }

      await windowManager.setSize(
        Size(width.roundToDouble(), height.roundToDouble()),
      );
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.setAlwaysOnTop(true);

      _active = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[DesktopPip] 进入画中画异常: $e');
      return false;
    }
  }

  /// 退出桌面画中画，还原先前的窗口位置与尺寸
  Future<bool> restorePip() async {
    if (!isSupported || !_active) return false;
    try {
      await windowManager.setAlwaysOnTop(_savedAlwaysOnTop);
      if (_savedBounds != null) {
        await windowManager.setBounds(_savedBounds!);
        _savedBounds = null;
      }
      _active = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[DesktopPip] 恢复画中画异常: $e');
      _active = false;
      notifyListeners();
      return false;
    }
  }
}
