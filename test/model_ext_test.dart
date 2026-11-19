import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.34：7 个用户提供的 CC0 门窗 OBJ（models_ext.js）挂进「模块 → 门/窗」。
void main() {
  // id 清单硬编码（与 assets/web/models_ext.js 的 key 一一对应）
  const doorIds = {
    'm_door1',
    'm_frontDoorDark',
    'm_frenchDoors',
    'm_thick_double_2x4',
    'm_doorGlassPanels',
  };
  const windowIds = {'m_window_deep', 'm_window_double_sill'};
  const allIds = {...doorIds, ...windowIds};

  // 规格（米）与颜色，与 models_ext.js 的 w/d/h/c 对齐
  const specs = {
    'm_door1': (0.91, 0.18, 2.14, 0x8A5A2B),
    'm_doorGlassPanels': (0.77, 0.11, 2.06, 0x4A90D9),
    'm_thick_double_2x4': (1.60, 0.23, 2.10, 0x7A5230),
    'm_frontDoorDark': (0.67, 0.24, 1.21, 0x3A3A3A),
    'm_frenchDoors': (1.14, 0.14, 1.00, 0x8A5A2B),
    'm_window_deep': (1.05, 0.60, 1.50, 0x4A90D9),
    'm_window_double_sill': (1.23, 0.25, 1.10, 0x4A90D9),
  };

  group('model_ext: 门窗 CC0 素材目录', () {
    test('门 5 件 / 窗 2 件，modelId 全在 models_ext id 集合内', () {
      final doors = ModelItems.ofCategory('门')
          .where((m) => m.modelId != null)
          .toList();
      final windows = ModelItems.ofCategory('窗')
          .where((m) => m.modelId != null)
          .toList();
      expect(doors.map((m) => m.id).toSet(), doorIds);
      expect(windows.map((m) => m.id).toSet(), windowIds);
      expect(doors.length, 5);
      expect(windows.length, 2);
      for (final m in [...doors, ...windows]) {
        expect(allIds.contains(m.id), true, reason: '${m.id} 不在 id 清单');
        expect(m.modelId, m.id); // id 与模型表 key 完全一致
        expect(m.place, ModelPlace.wall, reason: '${m.id} 必须走点墙开洞');
      }
    });

    test('规格尺寸（mm）与 models_ext w/d/h（米）一致', () {
      for (final m in ModelItems.all.where((m) => m.modelId != null)) {
        final s = specs[m.id]!;
        expect(m.defaultWmm, (s.$1 * 1000).round(), reason: '${m.id} 宽');
        expect(m.heightMm, (s.$3 * 1000).round(), reason: '${m.id} 高');
        expect(m.specText.contains('${m.defaultWmm}×${m.heightMm}'), true);
      }
    });

    test('assets/web/models_ext.js 含全部 7 个 key + 规格字段', () {
      final f = File('assets/web/models_ext.js');
      expect(f.existsSync(), true, reason: 'models_ext.js 必须随 assets/web/ 打包');
      final js = f.readAsStringSync();
      for (final id in allIds) {
        final key = '"$id":';
        expect(js.contains(key), true, reason: 'models_ext.js 缺 $id');
        // key 后紧跟 n/cat/w/d/h/c/o 字段
        final i = js.indexOf(key);
        final chunk = js.substring(i, i + 260);
        expect(chunk.contains('"n":'), true);
        expect(chunk.contains('"cat":'), true);
        expect(chunk.contains('"w":'), true);
        expect(chunk.contains('"h":'), true);
        expect(chunk.contains('"o":"'), true);
      }
      // 颜色按类目：门木色/深色/移门色，窗蓝玻璃
      expect(js.contains('"c":${0x8A5A2B}'), true);
      expect(js.contains('"c":${0x4A90D9}'), true);
      expect(js.contains('"c":${0x3A3A3A}'), true);
      expect(js.contains('"c":${0x7A5230}'), true);
      // OBJ 原文完整（door1 392934 字节，JS parseOBJ 无截断）
      expect(js.contains('m_door1'), true);
      expect(js.length > 700000, true);
    });

    test('Opening.modelId 随 JSON 往返（旧数据无 m → null）', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(4, 0));
      final wid = p.walls.keys.first;
      p.openings['o1'] = Opening(
        id: 'o1',
        wallId: wid,
        kind: OpeningKind.door,
        offset: 1,
        width: 0.91,
        height: 2.14,
        modelId: 'm_door1',
      );
      final back = FloorPlan.fromJsonString(p.toJsonString());
      expect(back.openings['o1']!.modelId, 'm_door1');
      // 旧 JSON（无 m 键）宽容解析
      final legacy = FloorPlan.fromJsonString(p.toJsonString()
          .replaceAll(',"m":"m_door1"', ''));
      expect(legacy.openings['o1']!.modelId, null);
    });
  });

  group('editor: 门菜单选 CC0 实模 → 点墙开洞带 modelId', () {
    Future<(ProviderContainer, WidgetTester)> pumpEditorTall(
        WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: FloorplanEditorPage()),
        ),
      );
      await tester.pump();
      return (container, tester);
    }

    testWidgets('标准单门（m_door1）→ 910×2140 开洞 + modelId', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(Checkbox)); // 取消底墙加门
      await tester.pump();
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('门'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('标准单门'), findsOneWidget);
      await tester.tap(find.text('标准单门'));
      await tester.pump();

      final cvF = find.byKey(const ValueKey('cv'));
      final cRect = tester.getRect(cvF);
      final cw = cRect.width, ch = cRect.height;
      final ppm = cw / 6 < ch / 5 ? cw / 6 : ch / 5;
      final topWallPt = Offset(cRect.center.dx, cRect.top + (ch - 5 * ppm) / 2);
      await tester.tapAt(topWallPt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final plan = container.read(editorDocProvider).plan;
      expect(plan.openings.length, 1);
      final o = plan.openings.values.first;
      expect(o.modelId, 'm_door1');
      expect(o.width, closeTo(0.91, 0.01));
      expect(o.height, closeTo(2.14, 0.01));
      expect(o.kind, OpeningKind.door);
    });
  });
}
