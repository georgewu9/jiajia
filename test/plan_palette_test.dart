import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/theme.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/plan_palette.dart';

/// v0.1.26：2D 画布 / 3D 视图层改亮色建筑风——配色与梁柱菜单的回归护栏。
/// v0.1.46：整体翻色「深琥珀辉光」→「浅薄荷翡翠绿」，本文件锁死新 token。
/// 约束：3D 视图层（viewer.js / models.js / models_ext.js）天蓝配色不动。
void main() {
  group('2D 画布配色（亮色建筑风 · 薄荷翡翠）', () {
    test('PlanPalette 色值与 v0.1.46 翻色表一致', () {
      expect(PlanPalette.bg, const Color(0xFFF0F5F5));
      expect(PlanPalette.wall, const Color(0xFF000000));
      expect(PlanPalette.opening, const Color(0xFF3B82F6));
      expect(PlanPalette.text, const Color(0xFF333333));
      expect(PlanPalette.gridMinor, const Color(0xFFE3EBE9));
      expect(PlanPalette.gridMajor, const Color(0xFFD9E4E1));
      expect(PlanPalette.gridText, const Color(0xFFAAAAAA));
      // 选中深翡翠（比 accent 深一档，与 UI 强调色区分）
      expect(PlanPalette.sel, const Color(0xFF00857A));
    });

    test('app 主题 token 翻成薄荷翡翠（关键 5 色锁死）', () {
      expect(JiajiaColors.accent, const Color(0xFF00A88F));
      expect(JiajiaColors.bgBase, const Color(0xFFF0F5F5));
      expect(JiajiaColors.surface, const Color(0xFFFFFFFF));
      expect(JiajiaColors.text1, const Color(0xFF2F3B47));
      expect(JiajiaColors.sel, const Color(0xFF00857A));
      // 辅助色一起锁（换回暗色/琥珀会被逮到）
      expect(JiajiaColors.accentSoft, const Color(0x1F00A88F));
      expect(JiajiaColors.selSoft, const Color(0x3300857A));
      expect(JiajiaColors.opening, const Color(0xFF3B82F6));
      // 琥珀 #FFB85C / 亮黄选中 #FFD60A 已全撤出
      expect(JiajiaColors.accent, isNot(const Color(0xFFFFB85C)));
      expect(JiajiaColors.sel, isNot(const Color(0xFFFFD60A)));
    });

    test('JiajiaTheme 已是亮色主题（scaffold 薄荷底 / 卡片白 / 顶栏白）', () {
      final t = JiajiaTheme.light;
      expect(t.brightness, Brightness.light);
      expect(t.scaffoldBackgroundColor, JiajiaColors.bgBase);
      expect(t.colorScheme.primary, JiajiaColors.accent);
      expect(t.colorScheme.onSurface, JiajiaColors.text1);
      // v0.1.47：顶栏改白底（与薄荷画布分层）——不再与画布同色
      expect(t.appBarTheme.backgroundColor, JiajiaColors.surface);
      expect(t.appBarTheme.backgroundColor, const Color(0xFFFFFFFF));
      expect(
        t.appBarTheme.backgroundColor,
        isNot(JiajiaColors.bgBase),
        reason: 'AppBar 应与薄荷画布底色分层，不能再用 bgBase',
      );
      expect(
        t.navigationBarTheme.indicatorColor,
        JiajiaColors.accentSoft,
      );
    });
  });

  group('3D 视图层配色（viewer 资源）', () {
    String src(String rel) => File(rel).readAsStringSync();

    test('viewer.js 用新配色 hex（背景/地/墙/线/栏杆/框/玻璃）', () {
      final js = src('assets/web/viewer.js');
      // scene.background #88C9F2、地 #FFF、墙 #CFCFCF
      expect(js.contains('0x88c9f2'), true, reason: '3D 背景应为天蓝 #88C9F2');
      expect(js.contains('floor: 0xffffff'), true, reason: '地面应为纯白');
      expect(js.contains('wall: 0xcfcfcf'), true, reason: '墙体应为淡灰');
      // 墙轮廓/顶部线 #1A1A1A、栏杆 #2B2B2B、门窗框 #333、玻璃 #99CDE6
      expect(js.contains('edge: 0x1a1a1a'), true);
      expect(js.contains('railing: 0x2b2b2b'), true);
      expect(js.contains('frame: 0x333333'), true);
      expect(js.contains('glass: 0x99cde6'), true);
      // 旧暗色常量不再出现
      expect(js.contains('0x0e1117'), false, reason: '旧深色背景应已移除');
      expect(js.contains('0x44506a'), false, reason: '旧深蓝墙体应已移除');
    });

    test('viewer.html 页面底色同步天蓝', () {
      expect(src('assets/web/viewer.html').contains('#88c9f2'), true);
    });

    test('新增 5 件 kind 在 3D CATALOG 里都有条目', () {
      final js = src('assets/web/viewer.js');
      for (final k in ['beam', 'duct', 'pipeCase', 'barePipe', 'platform']) {
        expect(js.contains('$k: ['), true, reason: 'viewer.js CATALOG 缺 $k');
      }
    });
  });

  group('梁柱菜单 7 件（任务一）', () {
    test('柱 + 梁 = 7 件，台面/五金 不进菜单', () {
      expect(ModelItems.byCategories(['柱', '梁']).length, 7);
      expect(
        ModelItems.byCategories(['柱', '梁']).any((m) => m.category == '台面/五金'),
        false,
        reason: '台面/五金 已移出梁柱菜单',
      );
      // 新增 5 件的 kind 都进了 3D 目录（Dart 侧）与图标表
      final liang = ModelItems.ofCategory('梁');
      expect(liang.map((m) => m.floorKind).toSet(), {
        FurnitureKind.beam,
        FurnitureKind.duct,
        FurnitureKind.pipeCase,
        FurnitureKind.barePipe,
        FurnitureKind.platform,
      });
      for (final m in liang) {
        expect(File(m.icon!).existsSync(), true, reason: '缺图标 ${m.icon}');
      }
    });
  });
}
