import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// 用户报告的 Bug：选中【画墙】后单指在画布上拖拽没反应。
/// 根因：画布 GestureDetector 的子节点 CustomPaint 没有 child，区域不可命中，
/// 单指 scale/pan 事件到不了识别器。修复：CustomPaint 加 SizedBox.expand()
/// + behavior:opaque。以下用例回归整条手势链路。
void main() {
  Future<(ProviderContainer, WidgetTester)> pumpEditor(WidgetTester tester) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fut = tester
        .pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FloorplanEditorPage()),
    ))
        .then((_) => tester.pump());
    return fut.then((_) => (container, tester));
  }

  testWidgets('画墙：单指拖拽生成墙', (tester) async {
    final (container, _) = await pumpEditor(tester);
    // 默认即「画墙」工具，画布中心单指拖 ~300px
    final cv = find.byKey(const ValueKey('cv'));
    await tester.drag(cv, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // 双击定时器

    final plan = container.read(editorDocProvider).plan;
    expect(plan.walls.length, 1);
  });

  testWidgets('模块 → 梁柱 → 方柱：点画布摆放（v0.1.17 二级菜单）',
      (tester) async {
    final (container, _) = await pumpEditor(tester);
    // 一级：模块
    await tester.tap(find.text('模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
    expect(find.text('门'), findsOneWidget);
    expect(find.text('拆改'), findsOneWidget);
    // 二级：梁柱（柱 + 台面/五金）
    await tester.tap(find.text('梁柱'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('方柱'), findsOneWidget);
    await tester.tap(find.text('方柱'));
    await tester.pump();
    // 轻点画布中心（单 tap 需等 ~300ms 双击窗口后才触发 onTapUp）
    final c = tester.getCenter(find.byKey(const ValueKey('cv')));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
    await tester.pump();

    final plan = container.read(editorDocProvider).plan;
    // ignore: avoid_print
    print('FURN: items=${plan.items.length}');
    expect(plan.items.isNotEmpty, true, reason: '点画布应放入一件方柱');
    expect(plan.items.values.first.kind, FurnitureKind.pillar);
  });

  testWidgets('双击墙 → 弹出台底尺寸面板', (tester) async {
    final (container, _) = await pumpEditor(tester);
    // 先画一段墙（默认画墙工具）
    final cv = find.byKey(const ValueKey('cv'));
    await tester.drag(cv, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(editorDocProvider).plan.walls.length, 1);

    // 双击点 = 墙世界坐标中点 → toScreen 得到 detector-local，再加画布
    // topLeft(global) 转 global 给 tapAt。不能用"画布中心+150px"。
    final plan = container.read(editorDocProvider).plan;
    final wall = plan.walls.values.first;
    final mid = wall.a + (wall.b - wall.a) * 0.5; // 世界坐标中点
    const ppm = 90.0, panX = 80.0, panY = 80.0; // 相机初始值（画墙不改相机）
    final localMid = Offset(mid.dx * ppm + panX, mid.dy * ppm + panY);
    final tapGlobal = tester.getRect(cv).topLeft + localMid;
    // ignore: avoid_print
    print('DBL-TAP-AT: global=$tapGlobal local=$localMid world=(${mid.dx},${mid.dy})');

    // 双击需两次 tap 间隔 ~100ms（< 300ms 窗口），再 pump 越过窗口。
    await tester.tapAt(tapGlobal);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tapGlobal);
    await tester.pump(const Duration(milliseconds: 400));

    // 台底面板应已弹出（_WallDialog 内含 mm 输入）
    expect(find.text('墙尺寸'), findsOneWidget,
        reason: '双击墙应弹出尺寸台底面板');
  });

  testWidgets('v0.1.18 选择工具：偏墙 0.3m 的点也能选中墙（容差回归）',
      (tester) async {
    final (container, _) = await pumpEditor(tester);
    final cv = find.byKey(const ValueKey('cv'));
    await tester.drag(cv, const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(editorDocProvider).plan.walls.length, 1);

    final wall = container.read(editorDocProvider).plan.walls.values.first;
    const ppm = 90.0, panX = 80.0, panY = 80.0; // 相机初始值（画墙不改相机）
    // 取墙中点偏法向 0.3m 的世界坐标——旧容差（0.25~0.3m 封顶）点不中，
    // v0.1.18 起（墙厚/2+0.45）必须选中。
    final mid = wall.a + (wall.b - wall.a) * 0.5;
    final off = mid + Vec2(0, 0.3);
    final local = Offset(off.dx * ppm + panX, off.dy * ppm + panY);
    final tapGlobal = tester.getRect(cv).topLeft + local;

    await tester.tap(find.text('选择'));
    await tester.pump();
    await tester.tapAt(tapGlobal);
    await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
    await tester.pump();

    expect(find.text('加开洞'), findsOneWidget,
        reason: '偏 0.3m 的点应命中墙并弹出墙面板');
  });
}
