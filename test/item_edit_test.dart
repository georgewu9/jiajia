import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/theme.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
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

    test('v0.1.37 offFloorMm：JSON 往返 off（mm 整数）+ 旧 JSON 宽容 null', () {
      final p = FloorPlan();
      p.items['a1'] = FurnitureItem(
        id: 'a1',
        kind: FurnitureKind.asset,
        pos: const Vec2(1, 1),
        modelId: 'm_courtyard_awning',
        sizeW: 3.1,
        sizeD: 1.69,
        sizeH: 0.62,
        offFloorMm: 1500,
      );
      final raw = p.toJsonString();
      expect(raw.contains('"off":1500'), true, reason: 'JSON 键 off 应为 mm 整数');
      expect(FloorPlan.fromJsonString(raw).items['a1']!.offFloorMm, 1500);
      // 落地件：off=0 照写（放置路径显式写 0）；null 也可（旧数据）
      final g = FurnitureItem(
          id: 'g1', kind: FurnitureKind.asset, pos: const Vec2(0, 0));
      expect(g.toJson().containsKey('off'), false);
      final legacy = FloorPlan.fromJsonString(jsonEncode({
        'name': 't',
        'walls': <dynamic>[],
        'openings': <dynamic>[],
        'items': [
          {'id': 'g1', 'kind': 'asset', 'model': 'm_furn_desk', 'x': 0, 'y': 0}
        ],
      }));
      expect(legacy.items['g1']!.offFloorMm, isNull);

      // v0.1.49：非实模 kind（梁，无 modelId）也走 off 往返，且 el 不混写
      final b = FurnitureItem(
        id: 'b1',
        kind: FurnitureKind.beam,
        pos: const Vec2(0, 0),
        offFloorMm: 2400,
      );
      final braw = FloorPlan()
        ..items['b1'] = b;
      final bjson = braw.toJsonString();
      expect(bjson.contains('"off":2400'), true, reason: '梁 off 应为 mm 整数');
      expect(bjson.contains('"el"'), false, reason: '梁不写 elevation');
      final bit = FloorPlan.fromJsonString(bjson).items['b1']!;
      expect(bit.kind, FurnitureKind.beam);
      expect(bit.offFloorMm, 2400);
      expect(bit.elevation, 0);
    });

    test('v0.1.24 elevation：JSON 往返 el + 旧 JSON 默认 0', () {
      final p = FloorPlan();
      p.items['i1'] = FurnitureItem(
        id: 'i1',
        kind: FurnitureKind.stair,
        pos: const Vec2(1, 1),
        elevation: 0.3,
      );
      final raw = p.toJsonString();
      expect(raw.contains('"el":0.3'), true, reason: 'JSON 键 el 应存在');
      final it = FloorPlan.fromJsonString(raw).items['i1']!;
      expect(it.elevation, closeTo(0.3, 1e-9));

      // elevation=0 不写键（旧数据同形）；旧 JSON 解析默认 0
      final zero = FurnitureItem(
          id: 'i2', kind: FurnitureKind.stair, pos: const Vec2(0, 0));
      expect(zero.toJson().containsKey('el'), false);
      final legacy = FloorPlan.fromJsonString(jsonEncode({
        'name': 't',
        'walls': <dynamic>[],
        'openings': <dynamic>[],
        'items': [
          {'id': 'i2', 'kind': 'stair', 'x': 0, 'y': 0, 'rot': 0}
        ],
      }));
      expect(legacy.items['i2']!.elevation, 0);
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
      // v0.1.48：accent 实心底按钮统一白字前景（物品对话框「应用」）
      final apply = tester.widget<FilledButton>(find
          .ancestor(
            of: find.text('应用'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          )
          .first);
      expect(
        apply.style?.foregroundColor?.resolve(const <WidgetState>{}),
        Colors.white,
      );
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

    testWidgets('楼梯「离地高度」：仅楼梯显示，应用写回 elevation', (tester) async {
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
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, roomC) + cRect.topLeft;

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final elField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration as InputDecoration).labelText == '离地高度 (mm)',
      );
      expect(elField, findsOneWidget, reason: '楼梯应显示离地高度输入框');
      await tester.enterText(elField, '300');
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(editorDocProvider).plan.items[iid]!.elevation,
        closeTo(0.3, 1e-3),
        reason: '离地高度应写回 0.3m',
      );

      // 非楼梯（餐桌）不显示离地高度
      final tid = plan0.newId('i');
      container.read(editorDocProvider.notifier).mutate((p) {
        p.items[tid] = FurnitureItem(
          id: tid,
          kind: FurnitureKind.table,
          pos: Vec2(minX + 0.8, minY + 0.8),
        );
      });
      await tester.pump();
      final tp = worldToCanvas(cRect, plan0, Vec2(minX + 0.8, minY + 0.8)) +
          cRect.topLeft;
      await tester.tapAt(tp);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(elField, findsNothing, reason: '非楼梯物品不应显示离地高度');
    });

    testWidgets('实模「离地高度」：±50 步进 + 应用写回 offFloorMm（2D 占地不变）',
        (tester) async {
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
          kind: FurnitureKind.asset,
          pos: roomC,
          modelId: 'm_courtyard_awning',
          sizeW: 3.1,
          sizeD: 1.69,
          sizeH: 0.62,
          offFloorMm: 1500,
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, roomC) + cRect.topLeft;

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final elField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration as InputDecoration).labelText == '离地高度 (mm)',
      );
      expect(elField, findsOneWidget, reason: '实模应显示离地高度输入框');
      // 初值取 item.offFloorMm（1500）
      expect(tester.widget<TextField>(elField).controller!.text, '1500');
      // ±50 步进：+50 → 1550，−50 → 1500，再 −50 → 1450
      await tester.tap(find.byKey(const ValueKey('lift_plus')));
      await tester.pump();
      expect(tester.widget<TextField>(elField).controller!.text, '1550');
      await tester.tap(find.byKey(const ValueKey('lift_minus')));
      await tester.pump();
      expect(tester.widget<TextField>(elField).controller!.text, '1500');
      await tester.tap(find.byKey(const ValueKey('lift_minus')));
      await tester.pump();
      expect(tester.widget<TextField>(elField).controller!.text, '1450');
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final it = container.read(editorDocProvider).plan.items[iid]!;
      expect(it.offFloorMm, 1450, reason: '离地高度写回 mm 整数');
      expect(it.footprint.$1, closeTo(3.1, 1e-3), reason: '2D 占地不受影响');
      expect(it.elevation, 0, reason: 'offFloorMm 不写 elevation');
    });

    testWidgets('v0.1.49 梁「离地高度」：初值 = spec 默认 2400，+50 应用写 offFloorMm',
        (tester) async {
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
      final beamSpec =
          ModelItems.all.firstWhere((m) => m.floorKind == FurnitureKind.beam);
      expect(beamSpec.offFloorMm, 2400, reason: '梁 spec 默认梁底 2400mm');
      final iid = plan0.newId('i');
      container.read(editorDocProvider.notifier).mutate((p) {
        p.items[iid] = FurnitureItem(
          id: iid,
          kind: FurnitureKind.beam,
          pos: roomC,
          offFloorMm: beamSpec.offFloorMm,
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, roomC) + cRect.topLeft;

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final elField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration as InputDecoration).labelText == '离地高度 (mm)',
      );
      expect(elField, findsOneWidget, reason: '梁应显示离地高度输入框');
      expect(tester.widget<TextField>(elField).controller!.text, '2400',
          reason: '初值取 spec 默认 2400');
      // 上限 6000（梁专用）：6500 应被拒绝且不写回
      await tester.enterText(elField, '6500');
      await tester.pump();
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // SnackBar 入场
      expect(find.text('离地高度需在 0..6000 mm 之间'), findsOneWidget,
          reason: '梁上限 6000mm');
      expect(container.read(editorDocProvider).plan.items[iid]!.offFloorMm,
          2400, reason: '超上限不写回');
      // 恢复 2400 → +50 → 2450
      await tester.enterText(elField, '2400');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('lift_plus')));
      await tester.pump();
      expect(tester.widget<TextField>(elField).controller!.text, '2450');
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final it = container.read(editorDocProvider).plan.items[iid]!;
      expect(it.offFloorMm, 2450, reason: '梁离地写回 offFloorMm');
      expect(it.elevation, 0, reason: '梁不写 elevation（防双重抬高）');
      expect(it.baseDims.$3, closeTo(0.35, 1e-6),
          reason: '梁高（「高」字段）不被离地高度影响');
    });

    testWidgets('v0.1.49 地台「离地高度」：初值 0 → 改 150 应用（2D 占地不变）',
        (tester) async {
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
          kind: FurnitureKind.platform,
          pos: roomC,
          offFloorMm: 0, // 放置路径写 0（落地）
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, roomC) + cRect.topLeft;

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final elField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration as InputDecoration).labelText == '离地高度 (mm)',
      );
      expect(elField, findsOneWidget, reason: '地台应显示离地高度输入框');
      expect(tester.widget<TextField>(elField).controller!.text, '0',
          reason: '地台默认落地 0');
      await tester.enterText(elField, '150');
      await tester.pump();
      await tester.tap(find.text('应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final it = container.read(editorDocProvider).plan.items[iid]!;
      expect(it.offFloorMm, 150, reason: '地台离地写回 offFloorMm');
      expect(it.elevation, 0, reason: '地台不写 elevation');
      expect(it.footprint.$1, closeTo(1.5, 1e-6), reason: '2D 占地不变');
      expect(it.footprint.$2, closeTo(1.2, 1e-6), reason: '2D 占地不变');
    });

    testWidgets('v0.1.49 风管不显示「离地高度」（范围未扩散）', (tester) async {
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
      final p = Vec2((minX + maxX) / 2, (minY + maxY) / 2);
      final iid = plan0.newId('i');
      container.read(editorDocProvider.notifier).mutate((pp) {
        pp.items[iid] = FurnitureItem(
          id: iid,
          kind: FurnitureKind.duct,
          pos: p,
        );
      });
      await tester.pump();
      final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
      final pt = worldToCanvas(cRect, plan0, p) + cRect.topLeft;

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final elField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration as InputDecoration).labelText == '离地高度 (mm)',
      );
      expect(elField, findsNothing, reason: '风管本轮不给离地入口');
      expect(find.byKey(const ValueKey('lift_plus')), findsNothing);
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

    testWidgets('v0.1.47：改尺寸面板「删除该件」图标/文字用翡翠强调色', (tester) async {
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

      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tapAt(pt);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('改尺寸'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final label = find.text('删除该件');
      expect(label, findsOneWidget, reason: '改尺寸面板应有「删除该件」');
      final labelColor = tester.widget<Text>(label).style?.color;
      expect(labelColor, JiajiaColors.accent,
          reason: '「删除该件」文字应为翡翠强调色');
      expect(labelColor, isNot(JiajiaColors.text3),
          reason: 'v0.1.47 起不再用 text3 灰');

      // 同一行里的垃圾桶图标同色（页面别处的 delete_outline 不受影响）
      final row = find
          .ancestor(of: label, matching: find.byType(Row))
          .first;
      final iconFinder = find.descendant(
        of: row,
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(iconFinder, findsOneWidget);
      expect(tester.widget<Icon>(iconFinder).color, JiajiaColors.accent,
          reason: '「删除该件」图标应为翡翠强调色');
    });
  });
}
