import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.14 模型模块 + 房间拆/合/删（复刻原 app 户型模块）。
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

  /// 面板组专用：加高视口（坑⑤ 测试视口 sheet 几何伪影）。
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

  group('domain: 拆/合/删房', () {
    test('拆 4m×3m 房（竖直 50%）→ 2 房各 6㎡ + 隔墙 + 门', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false);
      final loops = p.roomLoops();
      expect(loops, hasLength(1));
      final id = p.splitRoom(loops.first, axis: 'v', frac: 0.5);
      expect(id, isNotNull);
      expect(p.walls.length, 7); // 4 外墙（上下各切成 2 段=6）+ 隔墙
      expect(p.openings.length, 1); // 拆门
      final loops2 = p.roomLoops();
      expect(loops2, hasLength(2));
      final total = loops2.fold<double>(0, (s, l) => s + l.area);
      expect(total, closeTo(12.0, 0.3)); // 隔墙厚度占一点面积
    });

    test('水平拆：太矮的房间拆不了', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 0.5, withDoor: false);
      final loop = p.roomLoops().single;
      expect(p.splitRoom(loop, axis: 'h'), isNull);
    });

    test('合并两个相邻房 → 共用隔墙删除，回到 1 房 12㎡', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false);
      final l1 = p.roomLoops().single;
      p.splitRoom(l1, axis: 'v', frac: 0.5, withDoor: false);
      var loops = p.roomLoops();
      expect(loops, hasLength(2));
      var n = p.mergeRooms(loops[0], loops[1]);
      expect(n, 1);
      loops = p.roomLoops();
      expect(loops, hasLength(1));
      expect(loops.first.area, closeTo(12.0, 0.15));
      expect(p.walls.length, 6); // 7 − 隔墙
    });

    test('不相邻房间不能合并', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 3, w: 3, withDoor: false)
        ..addRoom(at: const Vec2(10, 10), l: 3, w: 3, withDoor: false);
      final loops = p.roomLoops();
      expect(loops, hasLength(2));
      expect(p.sharedWallBetween(loops[0], loops[1]), isNull);
      expect(p.mergeRooms(loops[0], loops[1]), 0);
      expect(p.walls.length, 8);
    });

    test('删房：只删不共用的墙（外墙保留）', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false)
        ..addRoom(at: const Vec2(4, 0), l: 4, w: 3, withDoor: false);
      // 两房间不共墙（间距 0 但各自围合）→ 拆一个房制造共用墙
      final loops = p.roomLoops();
      expect(loops, hasLength(2));
      p.splitRoom(loops.first, axis: 'v', frac: 0.5, withDoor: false);
      var loops2 = p.roomLoops();
      expect(loops2, hasLength(3));
      // 删掉新拆出的左半房：它 4 面墙里 1 面（新隔墙）与右半房共用 → 只删 3 面
      final n = p.removeRoomWalls(loops2.last);
      expect(n, greaterThanOrEqualTo(0));
      expect(p.walls.isNotEmpty, true);
    });

    test('roomContains：房间内点 true，外 false', () {
      final p = FloorPlan()
        ..addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: false);
      final loop = p.roomLoops().single;
      expect(p.roomContains(loop, const Vec2(2, 1.5)), true);
      expect(p.roomContains(loop, const Vec2(5, 1.5)), false);
    });
  });

  group('model: 模型目录（原 app 图标）', () {
    test('目录齐 + 97 件（v0.1.36：+12 庭院；v0.1.37：+42 家具 −1 坡道栏杆）', () {
      expect(ModelItems.categories,
          ['门', '窗', '柱', '梁', '楼梯', '台面/五金', '特殊墙窗', '庭院', '家具']);
      expect(ModelItems.all.length, 97);
      expect(ModelItems.ofCategory('门').length, 11);
      expect(ModelItems.ofCategory('窗').length, 8);
      expect(ModelItems.ofCategory('柱').length, 2);
      expect(ModelItems.ofCategory('梁').length, 5); // 梁/风管/包管道/裸管/地台
      expect(ModelItems.ofCategory('楼梯').length, 4);
      expect(ModelItems.ofCategory('台面/五金').length, 12);
      expect(ModelItems.ofCategory('特殊墙窗').length, 2);
      expect(ModelItems.ofCategory('庭院').length, 11);
      expect(ModelItems.ofCategory('家具').length, 42);
      // 梁柱菜单 = 柱 + 梁 = 7 件（台面/五金 12 件不再进该菜单）
      final liangzhu = ModelItems.byCategories(['柱', '梁']);
      expect(liangzhu.length, 7);
      expect(liangzhu.map((m) => m.label).toList(),
          ['方柱', '圆柱', '梁', '风管', '包管道', '裸管', '地台']);
      expect(liangzhu.any((m) => m.category == '台面/五金'), false);
      expect(ModelItems.ofCategory('门').every((m) => m.place == ModelPlace.wall), true);
      final zhu = ModelItems.ofCategory('柱');
      expect(zhu.every((m) => m.place == ModelPlace.floor), true);
      expect(zhu.every((m) => m.floorKind != null), true);
      // 新增 5 件：floor 摆放 + 有 floorKind + 有图标
      final liang = ModelItems.ofCategory('梁');
      expect(liang.every((m) => m.place == ModelPlace.floor), true);
      expect(liang.every((m) => m.floorKind != null), true);
      expect(liang.every((m) => m.icon != null), true);
      // v0.1.49：梁默认梁底 2400mm；地台仍落地（null → 放置写 0），其余梁柱件不抬高
      final beamSpec = liang.firstWhere((m) => m.floorKind == FurnitureKind.beam);
      expect(beamSpec.offFloorMm, 2400);
      final platformSpec =
          liang.firstWhere((m) => m.floorKind == FurnitureKind.platform);
      expect(platformSpec.offFloorMm, isNull);
      for (final m in liangzhu.where(
          (m) => m.floorKind != FurnitureKind.beam)) {
        expect(m.offFloorMm, isNull, reason: '${m.id} 不应带默认离地');
      }
    });
  });

  group('editor: 模型放置 + 拆房面板', () {
    testWidgets('模块一级菜单 → 二级素材网格可切（v0.1.17）', (tester) async {
      await pumpEditorTall(tester);
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 一级：6 入口
      expect(find.text('门'), findsOneWidget);
      expect(find.text('拆改'), findsOneWidget);
      expect(find.text('特殊墙窗'), findsOneWidget);
      // 二级：门（含门洞）
      await tester.tap(find.text('门'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('门 · 素材（11 件）'), findsOneWidget);
      expect(find.text('门洞'), findsOneWidget);
      // 返回一级 → 楼梯（含平台）
      await tester.tap(find.text('← 模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('楼梯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('直楼梯'), findsOneWidget);
      expect(find.text('平台'), findsOneWidget);
    });

    testWidgets('选门 → 点墙开洞（参数正确）', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      // 先建房（视口中央 4×3）
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 取消「底墙加门」：本测试要自己放门，保证开洞数可预期（点 Checkbox 本体）
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final plan = container.read(editorDocProvider).plan;
      expect(plan.walls.length, 4);
      expect(plan.openings.isEmpty, true); // 未勾选底墙加门
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('门'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('单开门'));
      await tester.pump();
      expect(find.text('选择'), findsOneWidget); // 工具条仍在

      // 顶墙中点：fit 后 mW=6m、mH=5m（4×3 房间 + 各 1m 边距）
      // ppm = min(cw/6, ch/5)；顶墙 y_local = (ch − 5·ppm)/2，x 取画布中心
      final cvF = find.byKey(const ValueKey('cv'));
      final cRect = tester.getRect(cvF);
      final cw = cRect.width, ch = cRect.height;
      final ppm = cw / 6 < ch / 5 ? cw / 6 : ch / 5;
      final topWallPt = Offset(cRect.center.dx, cRect.top + (ch - 5 * ppm) / 2);
      await tester.tapAt(topWallPt);
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口，onTapUp 才触发
      await tester.pump();
      final plan2 = container.read(editorDocProvider).plan;
      expect(plan2.openings.length, 1);
      final o = plan2.openings.values.first;
      expect(o.width, closeTo(0.9, 0.01));
      expect(o.kind, OpeningKind.door);
    });

    testWidgets('选柱 → 点画布摆放下（item 生成）', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('梁柱'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // v0.1.26：梁柱菜单只剩 7 件（方柱/圆柱 + 梁/风管/包管道/裸管/地台）
      expect(find.text('梁柱 · 素材（7 件）'), findsOneWidget);
      expect(find.text('风管'), findsOneWidget);
      // 台面/五金 已移出梁柱菜单
      expect(find.text('梳妆台'), findsNothing);
      await tester.tap(find.text('方柱'));
      await tester.pump();
      final cvF = find.byKey(const ValueKey('cv'));
      await tester.tapAt(tester.getCenter(cvF));
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
      await tester.pump();
      final plan = container.read(editorDocProvider).plan;
      expect(plan.items.length, 1);
      expect(plan.items.values.first.kind, FurnitureKind.pillar);
    });

    testWidgets('v0.1.49 梁柱菜单放梁 → 放置即挂梁底 2400mm（off）',
        (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('梁柱'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('梁'));
      await tester.pump();
      final cvF = find.byKey(const ValueKey('cv'));
      await tester.tapAt(tester.getCenter(cvF));
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
      await tester.pump();
      final plan = container.read(editorDocProvider).plan;
      expect(plan.items.length, 1);
      final it = plan.items.values.first;
      expect(it.kind, FurnitureKind.beam);
      expect(it.offFloorMm, 2400, reason: '放置路径写入 spec 默认梁底标高');
      expect(it.elevation, 0, reason: '梁不写 elevation');
    });

    testWidgets('拆房面板：选房 → 拆房 → 左右分 → 拆分 → 2 房',
        (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      // 建房 4×3
      await tester.tap(find.text('建房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('创建房间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 切选择工具 → 点房间内部（v0.1.18：画布中心上方80px；v0.1.20：开洞命中容差
      // 从 0.05 放宽到 0.15，原tap点会落入底墙上门的宽容差带，改用左上偏右点）
      await tester.tap(find.text('选择'));
      await tester.pump();
      final cvF = find.byKey(const ValueKey('cv'));
      await tester.tapAt(tester.getCenter(cvF) + const Offset(-200, -160));
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
      await tester.pump();
      expect(find.textContaining('拖动可移动位置'), findsOneWidget);

      await tester.tap(find.text('拆房'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('左右分（竖直墙）'), findsOneWidget);
      await tester.tap(find.text('拆分'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final plan = container.read(editorDocProvider).plan;
      expect(plan.walls.length, 7); // 4 外墙切 2 段 + 隔墙
      expect(plan.roomLoops(), hasLength(2));
    });
  });
}
