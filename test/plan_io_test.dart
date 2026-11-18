import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/main.dart';

/// 户型导出/导入回归：
///  - 文件级 round-trip（写临时 .json → 读回 → 关键字段等价）
///  - PlanStore 重名加后缀不回归
///  - 「导入/另存到外部」入口在 UI 上存在（FilePicker 平台通道不真调）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 4m × 3m 一间房 + 1 门 + 1 件家具，作为往返样本。
  FloorPlan samplePlan() {
    final p = FloorPlan()..name = '往返户型';
    p.addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: true, doorW: 0.9);
    p.items['f1'] = FurnitureItem(
      id: 'f1',
      kind: FurnitureKind.sofa,
      pos: const Vec2(1.2, 1.4),
      rotationDeg: 30,
    );
    return p;
  }

  double areaOf(FloorPlan p) =>
      p.roomLoops().fold<double>(0, (sum, loop) => sum + loop.area);

  test('户型 JSON 经临时文件往返：名称/墙/开洞/家具/面积等价', () async {
    final dir = await Directory.systemTemp.createTemp('jj_plan_roundtrip_');
    addTearDown(() => dir.delete(recursive: true));

    final src = samplePlan();
    final file = File('${dir.path}/往返户型.json');
    await file.writeAsString(src.toJsonString());

    // 模拟「导入外部文件」的实际路径：读磁盘文本 → 解析
    final back = FloorPlan.fromJsonString(await file.readAsString());

    expect(back.name, src.name);
    expect(back.walls.length, src.walls.length);
    expect(back.openings.length, src.openings.length);
    expect(back.items.length, src.items.length);
    expect(areaOf(back), closeTo(areaOf(src), 1e-6));
    // 坐标也要真回来（曾经 roundToFraction 写反导致墙全塌到 0,0）
    for (final w in src.walls.values) {
      final w2 = back.walls[w.id]!;
      expect(w2.a.x, closeTo(w.a.x, 1e-6), reason: 'wall ${w.id} a.x');
      expect(w2.a.y, closeTo(w.a.y, 1e-6), reason: 'wall ${w.id} a.y');
      expect(w2.b.x, closeTo(w.b.x, 1e-6), reason: 'wall ${w.id} b.x');
      expect(w2.b.y, closeTo(w.b.y, 1e-6), reason: 'wall ${w.id} b.y');
    }
  });

  test('PlanStore 重名加后缀：不覆盖别人的同名文件，自己再存复用同一文件', () async {
    final docs = await Directory.systemTemp.createTemp('jj_store_');
    addTearDown(() => docs.delete(recursive: true));

    // 预先占位：plans/x.json 里装的是「别人」的户型
    final plans = Directory('${docs.path}/plans');
    await plans.create(recursive: true);
    await File('${plans.path}/x.json')
        .writeAsString((FloorPlan()..name = '占位户型').toJsonString());

    final store = PlanStore(root: docs);
    final mine = samplePlan()..name = 'x';

    final first = await store.save(mine);
    expect(first, endsWith('x(1).json')); // 别人的 x.json 不动，加后缀

    final again = await store.save(mine);
    expect(again, first); // 自己上次存的那份 → 原地覆盖，不再加 (2)

    final names = (await store.list()).map((e) => e.name).toList();
    expect(names.length, 2);
    expect(names, containsAll(<String>['占位户型', 'x']));
    // 原占位文件仍在，且内容没被改写
    final placeholder = FloorPlan.fromJsonString(
        await File('${plans.path}/x.json').readAsString());
    expect(placeholder.name, '占位户型');
  });

  testWidgets('落地页有「导入」入口', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LandingPage()),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('import_plan_btn')), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('已存户型行有「导出」按钮（save_alt 图标）', (tester) async {
    final docs = await tester.runAsync(
        () => Directory.systemTemp.createTemp('jj_list_export_'));
    final plans = Directory('${docs!.path}/plans');
    plans.createSync(recursive: true);
    File('${plans.path}/列表户型.json')
        .writeAsStringSync((samplePlan()..name = '列表户型').toJsonString());
    addTearDown(() => docs.deleteSync(recursive: true));

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: LandingPage(store: PlanStore(root: docs))),
    ));
    // list() 是真实 IO，等它落地再刷一帧
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();

    expect(find.text('列表户型'), findsOneWidget);
    expect(find.byIcon(Icons.save_alt), findsOneWidget);
  });

  testWidgets('编辑器保存对话框有「另存到外部…」第二入口', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: FloorplanEditorPage()),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.save));
    await tester.pump();
    expect(find.text('保存户型'), findsOneWidget);
    expect(find.text('另存到外部…'), findsOneWidget);
    // 原「保存」按钮还在，两条路径并存
    expect(find.text('保存'), findsOneWidget);
  });
}
