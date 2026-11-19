import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.33 T4：选中物品后拖动不应变成「平移整图」。
/// 旧实现只有「精确命中被选物品」才拖物品，手指偏出 footprint ±0.18m 的
/// 命中带就落进相机平移（用户报：选中茶几一拖整个户型图在动）。
void main() {
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
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FloorplanEditorPage()),
    ));
    await tester.pump();
    return (container, tester);
  }

  Future<void> createRoom(WidgetTester tester) async {
    await tester.tap(find.text('建房'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Checkbox)); // 取消底墙加门
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 复刻 CameraCtrl.fit / toScreen：世界坐标 → 画布本地坐标（再 + rect.topLeft）。
  Offset worldToCanvas(Rect cRect, FloorPlan plan, Vec2 p) {
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final w in plan.walls.values) {
      minX = math.min(minX, math.min(w.a.dx, w.b.dx));
      maxX = math.max(maxX, math.max(w.a.dx, w.b.dx));
      minY = math.min(minY, math.min(w.a.dy, w.b.dy));
      maxY = math.max(maxY, math.max(w.a.dy, w.b.dy));
    }
    final mW = maxX - minX + 2, mH = maxY - minY + 2;
    final ppm = math.min(cRect.width / mW, cRect.height / mH);
    return Offset(
      (cRect.width - mW * ppm) / 2 - minX * ppm + p.dx * ppm,
      (cRect.height - mH * ppm) / 2 - minY * ppm + p.dy * ppm,
    );
  }

  /// 相机平移量（编辑器 State 上的公开 getter，测试/调试用）。
  Offset cameraPan(WidgetTester tester) {
    final st = tester.state(find.byType(FloorplanEditorPage));
    return (st as dynamic).cameraPan as Offset;
  }

  /// 建 4m×3m 房（无门）后往 plan 里放一件物品，返回 (plan, id, 位置)。
  /// 位置按墙 bbox 中心 + [offset] 算（建房落点跟着相机，不能写死世界坐标）。
  Future<(FloorPlan, String, Vec2)> setupItem(
    WidgetTester tester,
    ProviderContainer container, {
    required FurnitureKind kind,
    required Vec2 offset,
    required String id,
  }) async {
    final plan = container.read(editorDocProvider).plan;
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final w in plan.walls.values) {
      minX = math.min(minX, math.min(w.a.dx, w.b.dx));
      maxX = math.max(maxX, math.max(w.a.dx, w.b.dx));
      minY = math.min(minY, math.min(w.a.dy, w.b.dy));
      maxY = math.max(maxY, math.max(w.a.dy, w.b.dy));
    }
    final pos = Vec2((minX + maxX) / 2 + offset.dx, (minY + maxY) / 2 + offset.dy);
    container.read(editorDocProvider.notifier).mutate((p) {
      p.items[id] = FurnitureItem(id: id, kind: kind, pos: pos);
    });
    await tester.pump();
    return (plan, id, pos);
  }

  testWidgets('选中物品后从 footprint 外 0.2m 处拖 → 物品移动，相机不动', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    await createRoom(tester);

    // 沙发 1.8×0.85：中心在房间中央
    final (_, iid, center) =
        await setupItem(tester, container, kind: FurnitureKind.sofa,
            offset: const Vec2(0, 0), id: 'i1');
    final plan = container.read(editorDocProvider).plan;
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));

    // 先选中
    await tester.tapAt(worldToCanvas(cRect, plan, center) + cRect.topLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('已放 沙发'), findsOneWidget);

    // 起点：中心下方 0.85/2+0.2 = 0.625m —— 在命中带（±0.605m）外、但在
    // 「半对角线 + 0.35m」范围内 → 应拖物品，不是平移相机
    final grabWorld = Vec2(center.dx, center.dy + 0.625);
    final grab = worldToCanvas(cRect, plan, grabWorld) + cRect.topLeft;
    final panBefore = cameraPan(tester);

    await tester.dragFrom(grab, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final moved = container.read(editorDocProvider).plan.items[iid]!;
    expect(moved.pos.dx, greaterThan(center.dx + 0.2),
        reason: '从物品外侧起拖应移动物品');
    expect(moved.pos.dy, closeTo(center.dy, 1e-6), reason: '只横向拖，纵向不动');
    expect(cameraPan(tester), panBefore, reason: '相机不应被平移');
  });

  testWidgets('按未选中的物品 → 按下即选中且可拖动（相机不动）', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    await createRoom(tester);

    final (_, sofaId, sofaPos) = await setupItem(tester, container,
        kind: FurnitureKind.sofa, offset: const Vec2(-1.0, 0), id: 's1');
    final (_, tableId, tablePos) = await setupItem(tester, container,
        kind: FurnitureKind.table, offset: const Vec2(1.0, 0), id: 't1');
    final plan = container.read(editorDocProvider).plan;
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));

    // 只选中沙发（餐桌此时未选中）
    await tester.tapAt(worldToCanvas(cRect, plan, sofaPos) + cRect.topLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('已放 沙发'), findsOneWidget);

    final panBefore = cameraPan(tester);
    final grab =
        worldToCanvas(cRect, plan, tablePos) + cRect.topLeft; // 精确按住餐桌

    await tester.dragFrom(grab, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final p2 = container.read(editorDocProvider).plan;
    expect(p2.items[tableId]!.pos.dx, greaterThan(tablePos.dx + 0.2),
        reason: '按住未选中物品拖 → 应移动该物品');
    expect(p2.items[sofaId]!.pos.dx, closeTo(sofaPos.dx, 1e-6),
        reason: '原先选中的沙发不应被拖走');
    expect(find.textContaining('已放 餐桌'), findsOneWidget,
        reason: '按下即选中被拖的物品');
    expect(cameraPan(tester), panBefore, reason: '相机不应被平移');
  });

  testWidgets('选中物品后从远处空白拖 → 仍是相机平移（物品不动）', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    await createRoom(tester);

    final (_, iid, center) = await setupItem(tester, container,
        kind: FurnitureKind.sofa, offset: const Vec2(0, 0), id: 'i1');
    final plan = container.read(editorDocProvider).plan;
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));

    await tester.tapAt(worldToCanvas(cRect, plan, center) + cRect.topLeft);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('已放 沙发'), findsOneWidget);

    // 距中心 ~1.39m > 半对角线(0.996)+0.35=1.346 → 超出「贴着拖」范围，
    // 且离四面墙都 >0.57m（不命中墙）→ 应平移相机
    final grabWorld = Vec2(center.dx + 1.3, center.dy + 0.5);
    final grab = worldToCanvas(cRect, plan, grabWorld) + cRect.topLeft;
    final panBefore = cameraPan(tester);

    await tester.dragFrom(grab, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(container.read(editorDocProvider).plan.items[iid]!.pos.dx,
        closeTo(center.dx, 1e-6), reason: '远处空白拖不应移动物品');
    expect((cameraPan(tester) - panBefore).dx, greaterThan(20),
        reason: '远处空白拖应平移相机（touch slop 后 ≤ 60px）');
  });
}
