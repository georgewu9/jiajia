import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// 命中顺序回归：靠墙摆放的圆柱（roundPillar）必须能选中 / 拖 / 双击改尺寸，
/// 且离物品稍远处点墙仍应选中墙（物品命中只在 footprint ±0.18m 内）。
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

  /// 建 4m×3m 房（无门），在**顶墙内侧**贴墙放圆柱：中心距墙中线 0.30m
  /// —— 远小于墙命中容差（墙厚 0.24/2 + 0.45 ≈ 0.57m），旧实现会被墙抢命中。
  Future<(FloorPlan, String, Vec2)> setupWallHugPillar(
      WidgetTester tester, ProviderContainer container) async {
    await createRoom(tester);
    final plan = container.read(editorDocProvider).plan;
    var minX = 1e9, minY = 1e9, maxX = -1e9;
    for (final w in plan.walls.values) {
      minX = math.min(minX, math.min(w.a.dx, w.b.dx));
      maxX = math.max(maxX, math.max(w.a.dx, w.b.dx));
      minY = math.min(minY, math.min(w.a.dy, w.b.dy));
    }
    final pos = Vec2((minX + maxX) / 2, minY + 0.30);
    final iid = plan.newId('i');
    container.read(editorDocProvider.notifier).mutate((p) {
      p.items[iid] = FurnitureItem(
        id: iid,
        kind: FurnitureKind.roundPillar,
        pos: pos,
      );
    });
    await tester.pump();
    return (plan, iid, pos);
  }

  testWidgets('贴墙圆柱：单击选中物品（未被墙抢命中）', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    final (plan, _, pos) = await setupWallHugPillar(tester, container);
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    final pt = worldToCanvas(cRect, plan, pos) + cRect.topLeft;

    await tester.tapAt(pt);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('已放 圆柱'), findsOneWidget,
        reason: '贴墙圆柱应被选中，出现物品操作条');
    expect(find.text('改尺寸'), findsOneWidget);
    expect(find.text('加开洞'), findsNothing, reason: '不应误选墙');
  });

  testWidgets('贴墙圆柱：双击弹出物品尺寸对话框', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    final (plan, _, pos) = await setupWallHugPillar(tester, container);
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    final pt = worldToCanvas(cRect, plan, pos) + cRect.topLeft;

    await tester.tapAt(pt);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(pt); // 双击 = 两次 down
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final wField = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration as InputDecoration).labelText == '宽 (mm)',
    );
    expect(wField, findsOneWidget, reason: '双击圆柱应弹物品尺寸对话框（宽 (mm)）');
    expect(find.textContaining('改尺寸/旋转'), findsOneWidget);
    expect(find.text('加开洞'), findsNothing, reason: '不应弹出墙对话框');
  });

  testWidgets('贴墙圆柱：选中后可拖动改位置', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    final (plan, iid, pos) = await setupWallHugPillar(tester, container);
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    final pt = worldToCanvas(cRect, plan, pos) + cRect.topLeft;

    await tester.tapAt(pt);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.dragFrom(pt, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final moved = container.read(editorDocProvider).plan.items[iid]!;
    expect(moved.pos.dx, greaterThan(pos.dx + 0.05),
        reason: '选中物品后拖动应移动位置');
  });

  testWidgets('回归：离物品 >0.18m 处点墙仍选墙', (tester) async {
    final (container, _) = await pumpEditorTall(tester);
    final (plan, _, pos) = await setupWallHugPillar(tester, container);
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    // 沿同一面墙（顶墙 y=minY）横移 1.5m：远超物品 footprint±0.18m 命中带
    final wallPt = Vec2(pos.dx + 1.5, pos.dy - 0.25);
    final pt = worldToCanvas(cRect, plan, wallPt) + cRect.topLeft;

    await tester.tapAt(pt);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('加开洞'), findsOneWidget, reason: '应选中墙');
    expect(find.text('改尺寸'), findsNothing, reason: '不应误选物品');
  });
}
