import 'package:flutter/material.dart';

/// 2D 平面画布配色（v0.1.26 亮色建筑风；v0.1.46 底改薄荷 #F0F5F5）。
///
/// 只作用于 [_PlanPainter] 的绘制层。画布色单独成表（与 app 外壳的
/// [JiajiaColors] 解耦），以免画布色渗进主题 token。
class PlanPalette {
  const PlanPalette._();

  /// 画布背景 #F0F5F5（薄荷，与 JiajiaColors.bgBase 对齐）
  static const Color bg = Color(0xFFF0F5F5);

  /// 墙体线 #000000（原 JiajiaColors.wall #E8E2D5）
  static const Color wall = Color(0xFF000000);

  /// 门窗线 #3B82F6（原 JiajiaColors.opening #4A90D9）
  static const Color opening = Color(0xFF3B82F6);

  /// 面积 / 尺寸 / 标签文字 #333333（原 JiajiaColors.text2 #9AA3B5）
  static const Color text = Color(0xFF333333);

  /// 次网格（亮底需浅灰，原 JiajiaColors.gridMinor 是深色）
  static const Color gridMinor = Color(0xFFE3EBE9);

  /// 主网格（原 JiajiaColors.gridMajor）
  static const Color gridMajor = Color(0xFFD9E4E1);

  /// 网格刻度文字
  static const Color gridText = Color(0xFFAAAAAA);

  /// 选中高亮：深翡翠 #00857A——比 accent #00A88F 深一档，薄荷底上对比清晰，
  /// 且与 UI 强调色区分（原亮橙 #F97316 已撤）。
  static const Color sel = Color(0xFF00857A);
}
