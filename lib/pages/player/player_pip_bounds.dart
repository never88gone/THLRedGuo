import 'package:flutter/material.dart';

/// 画中画视口与宽高比例计算器
class PlayerPipBoundsCalculator {
  const PlayerPipBoundsCalculator._();

  /// 根据传入的视频宽高比计算原生画中画容器的目标整数宽高尺寸
  static (int, int) aspectDimensions(double aspectRatio) {
    final rawRatio =
        aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9;
    final ratio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final width = ratio >= 1 ? (1000 * ratio).round() : 1000;
    final height = ratio >= 1 ? 1000 : (1000 / ratio).round();
    return (width, height);
  }

  /// 计算在屏幕全局坐标系下的原生画中画动画起始源矩形（left, top, right, bottom）
  static Map<String, int>? calculateSourceRect({
    required GlobalKey videoPaneKey,
    required double aspectRatio,
  }) {
    final paneContext = videoPaneKey.currentContext;
    final renderObject = paneContext?.findRenderObject();
    if (paneContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return null;
    final rawRatio = aspectRatio.isFinite && aspectRatio > 0
        ? aspectRatio
        : size.width / size.height;
    final targetRatio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final containerRatio = size.width / size.height;
    late final double dx;
    late final double dy;
    late final double videoWidth;
    late final double videoHeight;
    if (containerRatio > targetRatio) {
      videoHeight = size.height;
      videoWidth = size.height * targetRatio;
      dx = (size.width - videoWidth) / 2;
      dy = 0;
    } else {
      videoWidth = size.width;
      videoHeight = size.width / targetRatio;
      dx = 0;
      dy = (size.height - videoHeight) / 2;
    }
    final ratio =
        MediaQuery.maybeOf(paneContext)?.devicePixelRatio ??
        View.of(paneContext).devicePixelRatio;
    final left = ((topLeft.dx + dx) * ratio).round().clamp(0, 100000);
    final top = ((topLeft.dy + dy) * ratio).round().clamp(0, 100000);
    final right = ((topLeft.dx + dx + videoWidth) * ratio).round().clamp(
      0,
      100000,
    );
    final bottom = ((topLeft.dy + dy + videoHeight) * ratio).round().clamp(
      0,
      100000,
    );
    if (right <= left || bottom <= top) return null;
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  }

  /// 本地化原生画中画错误消息
  static String localizeError(String? error) {
    if (error == null || error.trim().isEmpty) {
      return '无法启动画中画，请检查系统画中画设置或稍后重试';
    }
    final lower = error.toLowerCase();
    if (lower.contains('cannot be completed') ||
        lower.contains('could not be completed') ||
        lower.contains('couldn’t be completed')) {
      return '系统画中画启动未就绪，请稍后重试';
    }
    return error;
  }
}
