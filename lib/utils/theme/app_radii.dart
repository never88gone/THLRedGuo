import 'package:flutter/material.dart';

/// 全局统一现代圆角系统（拒绝直角和过于僵硬的默认圆角，采用大圆角与连续曲率手感）
abstract final class AppRadii {
  /// 微小组件（标签、角标）：8.0
  static const double badge = 8.0;
  static final BorderRadius badgeBorder = BorderRadius.circular(badge);

  /// 中小卡片（选集按钮、分集方块）：14.0
  static const double episode = 14.0;
  static final BorderRadius episodeBorder = BorderRadius.circular(episode);

  /// 标准卡片与海报（短剧海报卡片、设置项卡片）：18.0
  static const double card = 18.0;
  static final BorderRadius cardBorder = BorderRadius.circular(card);

  /// 大卡片与弹窗浮层（Sheet、Dialog）：24.0
  static const double sheet = 24.0;
  static final BorderRadius sheetBorder = BorderRadius.circular(sheet);

  /// 极致胶囊形状（主播放按钮、分类 Pill、搜索栏）：999.0
  static const double pill = 999.0;
  static final BorderRadius pillBorder = BorderRadius.circular(pill);
}
