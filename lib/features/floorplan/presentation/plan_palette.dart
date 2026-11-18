import 'package:flutter/material.dart';

/// 2D 平面画布配色（v0.1.26 亮色建筑风，设计稿「图3」）。
///
/// 只作用于 [_PlanPainter] 的绘制层：app 整体仍是暗色主题
/// （[JiajiaColors] / [JiajiaTheme.dark] 不动），所以这些色不进 JiajiaColors。
class PlanPalette {
  const PlanPalette._();

  /// 画布背景 #FAFAFA（原 JiajiaColors.bgBase #0E1117）
  static const Color bg = Color(0xFFFAFAFA);

  /// 墙体线 #000000（原 JiajiaColors.wall #E8E2D5）
  static const Color wall = Color(0xFF000000);

  /// 门窗线 #3B82F6（原 JiajiaColors.opening #4A90D9）
  static const Color opening = Color(0xFF3B82F6);

  /// 面积 / 尺寸 / 标签文字 #333333（原 JiajiaColors.text2 #9AA3B5）
  static const Color text = Color(0xFF333333);

  /// 次网格（亮底需浅灰，原 JiajiaColors.gridMinor 是深色）
  static const Color gridMinor = Color(0xFFF0F0F0);

  /// 主网格（原 JiajiaColors.gridMajor）
  static const Color gridMajor = Color(0xFFE2E2E2);

  /// 网格刻度文字
  static const Color gridText = Color(0xFFAAAAAA);

  /// 选中高亮：原亮黄 #FFD60A 在 #FAFAFA 上几乎不可见，改亮橙。
  static const Color sel = Color(0xFFF97316);
}
