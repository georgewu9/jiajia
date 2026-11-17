import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.20：物品改尺寸/旋转（双击/操作条）+ 开洞沿墙拖动改位置 + JSON 尺寸往返。
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

  /// 复刻 CameraCtrl.fit：世界坐标 → 画布(本地)坐标。
  /// 返回值直接是画布 Widget 本地坐标系下的点（与 CameraCtrl.toScreen 同公式）。
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

  group('domain: 物品自定义尺寸', () {
    test('JSON 往返保留 sw/sd/sh，footprint/height 覆盖生效', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false);
      final iid = p.newId('i');
      p.items[iid] = FurnitureItem(
        id: iid,
        kind: FurnitureKind.stairR,
        pos: const Vec2(1.5, 1.5),
        rotationDeg: 90,
        sizeW: 1.5,
        sizeD: 3.0,
        sizeH: 2.5,
      );
      final p2 = FloorPlan.fromJsonString(p.toJsonString());
      final it = p2.items[iid]!;
      expect(it.footprint.$1, closeTo(1.5, 1e-3), reason: '宽自定义');
      expect(it.footprint.$2, closeTo(3.0, 1e-3), reason: '深自定义');
      expect(it.heightM, closeTo(2.5, 1e-3), reason: '高自定义');
      expect(it.rotationDeg, closeTo(90, 1e-3));
    });

    test('旧 JSON（无 sw/sd/sh）→ 用目录默认值', () {
      final raw = jsonEncode({
        'name': 't',
        'walls': <Map<String, dynamic>>[],
        'openings': <Map<String, dynamic>>[],
        'items': [
          {
            'id': 'i1',
            'kind': 'stairR',
            'x': 1.0,
            'y': 1.0,
            'rot': 0,
          }
        ],
      });
      final it = FloorPlan.fromJsonString(raw).items['i1']!;
      expect(it.footprint.$1, closeTo(1.2, 1e-6));
      expect(it.footprint.$2, closeTo(2.6, 1e-6));
    });
  });

  group('editor: 物品改尺寸/旋转 + 开洞沿墙拖动', () {
    testWidgets('双击物品 → 应用按钮：占地变 1500mm、旋转 90°', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await createRoom(tester);
      final plan0 = container.read(editorDocProvider).plan;
      var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
      for (final w in plan0.walls.values) {
        minX = math.min(minX, math.min(w.a.dx, w.b.dx));
        maxX = math.max(maxX, math.max(w.a.dx, w.b.dx));
        minY = math.min(minY, math.min(w.a.dy, w.b.dy));
        maxY = math.max(maxY, w.b.dy);
      }
      final roomC = Vec2((minX + maxX) / 2, (minY + maxY) / 2);
      final iid = plan0.newId('i');
      container.read(editorDocProvider.notifier).mutate((p) {
        p.items[iid] = FurnitureItem(
          id: iid,
          kind: FurnitureKind.stairR,
          pos: roomC,
          rotationDeg: 0,
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, roomC) + cRect.topLeft;

      // 选「选择」工具 → 点物品 → 操作条「改尺寸」
      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('改尺寸'), findsOneWidget,
          reason: '物品选中时操作条应出现「改尺寸」');
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 宽改成 1500mm，旋转 +90°
      final wField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            ((w.decoration?.labelText ?? '').startsWith('宽')),
      );
      expect(wField, findsOneWidget, reason: '应找到「宽」输入框');
      await tester.enterText(wField, '1500');
      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pump();
      // 应用
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final it = container.read(editorDocProvider).plan.items[iid]!;
      expect(it.footprint.$1, closeTo(1.5, 1e-3), reason: '宽应覆盖为 1.5m');
      expect(it.rotationDeg, closeTo(90, 1e-3), reason: '旋转应 +90°');
    });

    testWidgets('单击选开洞 → 操作条出现；沿墙拖动改 offset', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await createRoom(tester);
      final plan0 = container.read(editorDocProvider).plan;
      final yOff = plan0.walls.values
          .map((w) => math.max(w.a.dy, w.b.dy))
          .reduce(math.max);
      final wall = plan0.walls.values.firstWhere(
          (w) => (w.a.dy - yOff).abs() < 1e-6 && (w.b.dy - yOff).abs() < 1e-6);
      final oid = plan0.newId('o');
      container.read(editorDocProvider.notifier).mutate((p) {
        p.openings[oid] = Opening(
          id: oid,
          wallId: wall.id,
          kind: OpeningKind.door,
          offset: 1.0,
          width: 0.9,
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      // openC：开洞正中（x方向），y方向在墙线下方 0.7m 外（超出墙命中带 0.57m，避免被墙先命中）
      final openCx = wall.a.dx - 1.0 - 0.9 / 2;
      final openC = Vec2(openCx, yOff + 0.7);
      final pt = worldToCanvas(cRect, plan0, openC);

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('改尺寸'), findsOneWidget,
          reason: '开洞选中时操作条应出现「改尺寸」');
      expect(find.text('删开洞'), findsOneWidget);
      // 沿墙右拖 40px：开洞沿墙移动（方向取决于墙走向，offset 应变化）
      await tester.dragFrom(pt, const Offset(40, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final o = container.read(editorDocProvider).plan.openings[oid]!;
      expect(o.offset, isNot(equals(1.0)), reason: '拖动后 offset 应发生变化');
    });
  });
}
