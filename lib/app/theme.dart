import 'package:flutter/material.dart';

/// 配色·薄荷翡翠：浅薄荷底 + 翡翠绿强调（#00A88F）。
/// 强调色占比 <10%，只用于可交互/当前态。
class JiajiaColors {
  const JiajiaColors._();

  static const Color bgBase = Color(0xFFF0F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color raised = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE0E6E6);
  static const Color text1 = Color(0xFF2F3B47);
  static const Color text2 = Color(0xFF8A95A3);
  static const Color text3 = Color(0xFFB5BDC5);
  static const Color accent = Color(0xFF00A88F);
  static const Color accentSoft = Color(0x1F00A88F);
  static const Color ok = Color(0xFF22C55E);
  static const Color err = Color(0xFFE74C3C);

  // 编辑器画布专用（亮色兜底色；2D 画布实际用 [PlanPalette]）
  static const Color gridMinor = Color(0xFFEAF1F0);
  static const Color gridMajor = Color(0xFFDCE8E5);
  static const Color wall = Color(0xFF2F3B47);

  /// 选中高亮：深翡翠 #00857A——比强调色深一档，与 accent 区分。
  static const Color sel = Color(0xFF00857A);
  static const Color selSoft = Color(0x3300857A);
  static const Color wallSelected = sel;
  static const Color opening = Color(0xFF3B82F6);
  static const Color furniture = Color(0xFF8FD3A8);
}

class JiajiaTheme {
  const JiajiaTheme._();

  static ThemeData get light {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: JiajiaColors.bgBase,
      colorScheme: ColorScheme.fromSeed(
        seedColor: JiajiaColors.accent,
        brightness: Brightness.light,
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
