import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.15：保存可改名 + 修复「保存后打开是空的」（roundToFraction 写反）
/// + 选中墙拖动平移 + 整个户型旋转。
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
    await tester.tap(find.byType(Checkbox)); // 取消底墙加门（几何可预期）
    await tester.pump();
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 顶墙中点（fit 公式：ppm=min(cw/6,ch/5)，顶墙 y_local=(ch−5ppm)/2）。
  Offset topWallCenter(WidgetTester tester) {
    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    final cw = cRect.width, ch = cRect.height;
    final ppm = cw / 6 < ch / 5 ? cw / 6 : ch / 5;
    return Offset(cRect.center.dx, cRect.top + (ch - 5 * ppm) / 2);
  }

  group('domain: JSON 持久化回归', () {
    test('round-trip 保留墙坐标/开洞/家具（roundToFraction 修复）', () {
      final p = FloorPlan()
        ..name = '回归户型'
        ..addRoom(at: const Vec2(2, 3), l: 4, w: 3, withDoor: true, doorW: 0.9);
      p.splitRoom(p.roomLoops().single, axis: 'v', frac: 0.5);
      final p2 = FloorPlan.fromJsonString(p.toJsonString());
      expect(p2.walls.length, p.walls.length);
      for (final w in p.walls.values) {
        final w2 = p2.walls[w.id]!;
        expect(w2.a.x, closeTo(w.a.x, 1e-3), reason: 'wall ${w.id} a.x');
        expect(w2.a.y, closeTo(w.a.y, 1e-3), reason: 'wall ${w.id} a.y');
        expect(w2.b.x, closeTo(w.b.x, 1e-3), reason: 'wall ${w.id} b.x');
        expect(w2.b.y, closeTo(w.b.y, 1e-3), reason: 'wall ${w.id} b.y');
      }
      expect(p2.openings.length, p.openings.length);
      expect(p2.openings.values.first.width, closeTo(0.9, 1e-2));
      expect(p2.roomLoops(), hasLength(p.roomLoops().length));
    });

    test('坐标 4.0m 不再被取整成 0（旧 bug 复现断言）', () {
      final p = FloorPlan()..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false);
      final j = p.toJsonString();
      expect(j, isNot(contains('"ax":0.0,"ay":0.0,"bx":0.0,"by":0.0')));
      final p2 = FloorPlan.fromJsonString(j);
      expect(p2.walls.values.firstWhere((w) => w.length > 2).length, closeTo(4, 0.01));
    });
  });

  group('editor: 拖选中墙 / 旋转 / 保存改名', () {
    testWidgets('选中墙后按住该墙拖动 → 墙平移（相机不动）', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await createRoom(tester);
      // 选墙工具 + 点顶墙中点（400ms 双击窗口后 onTapUp 才触发）
      await tester.tap(find.text('选择'));
      await tester.pump();
      final wallPt = topWallCenter(tester);
      await tester.tapAt(wallPt);
      await tester.pump(const Duration(milliseconds: 400));
      final before =
          container.read(editorDocProvider).plan.walls.values.toList();
      // 从「选中墙」上起拖 → 平移墙 0.5m（向下 67px@133ppm）
      await tester.dragFrom(wallPt, const Offset(0, 67));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final after =
          container.read(editorDocProvider).plan.walls.values.toList();
      final topB = before.firstWhere((w) => w.b.dy == w.a.dy && w.a.dx < 2);
      final topA = after.firstWhere((w) => w.b.dy == w.a.dy && w.a.dx < 2);
      expect(topA.a.dy, greaterThan(topB.a.dy),
          reason: '顶墙应向下平移');
      expect(topA.b.dy, closeTo(topA.a.dy, 0.01), reason: '墙仍水平');
      expect(after.length, before.length, reason: '墙数量不变');
    });

    testWidgets('旋转 90°：4m 水平墙变竖直，中心不变', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await createRoom(tester);
      final plan0 = container.read(editorDocProvider).plan;
      final cx =
          (plan0.walls.values.map((w) => w.a.dx).fold(0.0, (s, v) => s + v) /
                  plan0.walls.length +
              plan0.walls.values.map((w) => w.b.dx).fold(0.0, (s, v) => s + v) /
                  plan0.walls.length) /
          2;
      // 旋转图标（AppBar，常驻可见）→ 90° → 应用
      final rotateIcon = find.byIcon(Icons.rotate_90_degrees_cw);
      await tester.tap(rotateIcon);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('旋转户型'), findsOneWidget);
      await tester.tap(find.text('90°'));
      await tester.pump();
      await tester.tap(find.text('应用旋转'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final p = container.read(editorDocProvider).plan;
      expect(p.walls.length, plan0.walls.length);
      // 原 2 面 4m 水平墙（上/下）→ 现在都应为 4m 竖直墙
      final vertical4m = p.walls.values.where(
          (w) => (w.b.dx - w.a.dx).abs() < 0.01 && (w.b.dy - w.a.dy).abs() > 3.9);
      expect(vertical4m, hasLength(2));
      // bbox 中心不变（刚性旋转绕中心）
      double minX = 1e9, maxX = -1e9;
      for (final w in p.walls.values) {
        minX = minX < w.a.dx ? minX : w.a.dx;
        maxX = maxX > w.a.dx ? maxX : w.a.dx;
      }
      expect((minX + maxX) / 2, closeTo(cx, 0.05));
      // 房间仍可识别
      expect(p.roomLoops(), hasLength(1));
    });

    testWidgets('保存 → 文件名可改（改后 App 标题同步）', (tester) async {
      final (_, _) = await pumpEditorTall(tester);
      // 保存图标（AppBar）→ 弹对话框，输入框预填当前名
      await tester.tap(find.byIcon(Icons.save));
      await tester.pump();
      expect(find.text('保存户型'), findsOneWidget);
      final field = find.byType(TextField);
      expect((tester.widget(field) as TextField).controller!.text, '新建户型');
      await tester.enterText(field, '我的客厅');
      await tester.tap(find.text('保存'));
      await tester.pump();
      // 名称已写入文档（App 标题）；测试环境无文件目录 → 提示保存失败，泵掉
      expect(find.text('我的客厅'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
