import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.13 画房间体验优化（对齐原 app「家易量」设计）：
///  ① 墙起点 = 手指按下位置（避开 scale 识别器 touchSlop 漂移）
///  ② 端点磁吸（~14px 内精确吸附已有墙端点 → 墙与墙自动衔接）
///  ③ 45° 角锁定（接近横/竖/45° 时锁死 → 房间四壁更直）
///  ④ 一键建房间（输入长宽高 mm → 视口中央生成围合矩形 + 门）
///  ⑤ 房间面积标注（roomLoops DFS 找闭合环 + 面积）
void main() {
  Future<(ProviderContainer, WidgetTester)> pumpEditor(WidgetTester tester) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fut = tester
        .pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: FloorplanEditorPage()),
          ),
        )
        .then((_) => tester.pump());
    return fut.then((_) => (container, tester));
  }

  group('domain: 一键建房间 addRoom', () {
    test('4m×3m 房间 → 4 面墙围合 + 底墙中央一扇门', () {
      final p = FloorPlan();
      final ids = p.addRoom(at: const Vec2(0, 0), l: 4, w: 3);
      expect(ids, hasLength(4));
      expect(p.walls, hasLength(4));
      expect(p.openings, hasLength(1));
      final door = p.openings.values.first;
      expect(door.kind, OpeningKind.door);
      // 门在底墙（p3→p4）中央：off = (4-0.9)/2 = 1.55
      expect(door.offset, closeTo(1.55, 0.001));
      expect(door.width, closeTo(0.9, 0.001));
    });

    test('不加门 → 仅 4 面墙；墙高按输入', () {
      final p = FloorPlan();
      p.addRoom(at: const Vec2(1, 1), l: 2, w: 2, h: 3.0, withDoor: false);
      expect(p.walls, hasLength(4));
      expect(p.openings, isEmpty);
      expect(p.walls.values.first.height, closeTo(3.0, 0.001));
    });

    test('围合矩形能被 roomLoops 识别，面积 4×3=12', () {
      final p = FloorPlan();
      p.addRoom(at: const Vec2(0, 0), l: 4, w: 3);
      final loops = p.roomLoops();
      expect(loops, hasLength(1));
      expect(loops.first.area, closeTo(12.0, 0.01));
    });

    test('示例户型 5m×4m → 房间面积 20', () {
      final loops = samplePlan().roomLoops();
      expect(loops, hasLength(1));
      expect(loops.first.area, closeTo(20.0, 0.01));
    });

    test('不围合的散墙 → 无房间环', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0));
      p.walls['w2'] = Wall(id: 'w2', a: const Vec2(3, 0), b: const Vec2(3, 2));
      expect(p.roomLoops(), isEmpty);
    });
  });

  group('editor: 吸附与角锁定', () {
    testWidgets('端点磁吸：第二面墙起点精确落在第一面墙端点上', (tester) async {
      final (container, _) = await pumpEditor(tester);
      final cv = find.byKey(const ValueKey('cv'));
      // 第一面墙：画布中心向右拖 270px（3m）
      await tester.drag(cv, const Offset(270, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(editorDocProvider).plan.walls.length, 1);

      // 第二面墙：同一中心（= 第一面墙起点附近 <14px）向下拖 270px
      await tester.drag(cv, const Offset(0, 270));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final plan = container.read(editorDocProvider).plan;
      expect(plan.walls.length, 2);
      final w1 = plan.walls.values.elementAt(0);
      final w2 = plan.walls.values.elementAt(1);
      // 磁吸：第二面墙起点 == 第一面墙起点（逐坐标相等，非近似）
      expect(w2.a.x, w1.a.x);
      expect(w2.a.y, w1.a.y);
      // 45° 锁定：向下拖 → 竖直墙
      expect(w2.b.x, w2.a.x);
    });

    testWidgets('45° 角锁定：斜 4px 拖拽 → 墙横平竖直', (tester) async {
      final (container, _) = await pumpEditor(tester);
      final cv = find.byKey(const ValueKey('cv'));
      // 向右 100px、向下 4px（~2° 斜）：应锁定为水平
      await tester.drag(cv, const Offset(100, 4));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final plan = container.read(editorDocProvider).plan;
      final w = plan.walls.values.first;
      expect(w.a.dy, w.b.dy, reason: '接近水平应锁定为严格水平');
    });

    testWidgets('画墙起点 = 手指按下处（grid 精度 0.05m 内）', (tester) async {
      final (container, _) = await pumpEditor(tester);
      final cv = find.byKey(const ValueKey('cv'));
      await tester.drag(cv, const Offset(200, 150));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final w = container.read(editorDocProvider).plan.walls.values.first;
      final rect = tester.getRect(cv);
      // 画布局部中心 → 世界（相机初值 ppm=90, pan=(80,80)）
      final worldStart = Vec2(
        (rect.width / 2 - 80) / 90,
        (rect.height / 2 - 80) / 90,
      );
      // 起点与按下点偏差 ≤ 0.05m（细网格吸附容差）
      expect(
        (Vec2(w.a.dx, w.a.dy) - worldStart).length,
        lessThanOrEqualTo(0.06),
      );
    });
  });

  /// 面板组专用：加大视口高度（800×1200）——3.47.9 测试视口里 bottom
  /// sheet 内容会落到屏幕下沿之外（y>600 点不到，overlay 布局伪影；真机
  /// 无此问题）。加高视口让面板内容进屏，tap 才可达。
  Future<(ProviderContainer, WidgetTester)> pumpEditorTall(
      WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    return pumpEditor(tester);
  }

  group('editor: 一键建房间面板', () {
    testWidgets('建房 chip → 面板 → 创建 → 4 墙 + 1 门 + 面积 12',
        (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
      // 面板出现（默认 4000×3000，含门）
      expect(find.text('创建房间'), findsOneWidget);
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final plan = container.read(editorDocProvider).plan;
      expect(plan.walls.length, 4);
      expect(plan.openings.length, 1);
      final loops = plan.roomLoops();
      expect(loops, hasLength(1));
      expect(loops.first.area, closeTo(12.0, 0.01));
    });

    testWidgets('预置房型一键预填尺寸', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
      await tester.tap(find.text('卫生间 2500×3000'));
      await tester.pump();
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final plan = container.read(editorDocProvider).plan;
      expect(plan.roomLoops().single.area, closeTo(7.5, 0.01));
    });

    testWidgets('面积标注常显：建房后画布重绘无异常（v0.1.17 无开关）',
        (tester) async {
      await pumpEditorTall(tester);
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // 面积标注默认常显，画布重绘无异常
      expect(find.byKey(const ValueKey('cv')), findsOneWidget);
      // 底栏四个主入口按序存在，旧按钮已并入模块
      expect(find.text('选择'), findsOneWidget);
      expect(find.text('画墙'), findsOneWidget);
      expect(find.text('建房'), findsOneWidget);
      expect(find.text('模块'), findsOneWidget);
      expect(find.text('开洞'), findsNothing);
      expect(find.text('删除'), findsNothing);
    });
  });
}
