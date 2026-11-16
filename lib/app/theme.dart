import 'package:flutter/material.dart';

/// 配色「辉光」：深蓝黑底 + 暖琥珀强调（与 LUM 同一套，#FFB85C）。
/// 强调色占比 <10%，只用于可交互/当前态。
class JiajiaColors {
  const JiajiaColors._();

  static const Color bgBase = Color(0xFF0E1117);
  static const Color surface = Color(0xFF171B24);
  static const Color raised = Color(0xFF1F2530);
  static const Color line = Color(0xFF2A3140);
  static const Color text1 = Color(0xFFF2F4F8);
  static const Color text2 = Color(0xFF9AA3B5);
  static const Color text3 = Color(0xFF5F6B7A);
  static const Color accent = Color(0xFFFFB85C);
  static const Color accentSoft = Color(0x1FFFB85C);
  static const Color ok = Color(0xFF4ADE80);
  static const Color err = Color(0xFFF87171);

  // 编辑器画布专用
  static const Color gridMinor = Color(0xFF1A202B);
  static const Color gridMajor = Color(0xFF232B38);
  static const Color wall = Color(0xFFE8E2D5);
  static const Color wallSelected = accent;
  static const Color opening = Color(0xFF4A90D9);
  static const Color furniture = Color(0xFF8FD3A8);
}

class JiajiaTheme {
  const JiajiaTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: JiajiaColors.bgBase,
      colorScheme: ColorScheme.fromSeed(
        seedColor: JiajiaColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: JiajiaColors.accent,
        surface: JiajiaColors.surface,
        onSurface: JiajiaColors.text1,
      ),
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: JiajiaColors.bgBase,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: JiajiaColors.text1,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        backgroundColor: JiajiaColors.surface,
        indicatorColor: JiajiaColors.accentSoft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, color: JiajiaColors.text2),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? JiajiaColors.accent
                : JiajiaColors.text2,
          ),
        ),
      ),
    );
  }
}
