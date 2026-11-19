import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/main.dart';

/// v0.1.33 T2：新建户型（默认名）也能在列表里改名。
void main() {
  late Directory dir;
  late PlanStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jj_rename_');
    store = PlanStore(root: dir);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<PlanEntry> saveAs(String name) async {
    final p = FloorPlan()..name = name;
    p.addRoom(at: const Vec2(0, 0), l: 3, w: 2, withDoor: false);
    await store.save(p);
    final list = await store.list();
    return list.firstWhere((e) => e.name == name);
  }

  test('改名 round-trip：JSON 内 name 同步 + 旧文件删除 + meta 键迁移', () async {
    final e = await saveAs('新建户型');
    await store.saveMeta({
      '新建户型': {'sourcePath': '/tmp/导入.json', 'label': '导入.json'},
    });

    await store.rename(e, '客厅');

    final plans = Directory('${dir.path}/plans');
    expect(File('${plans.path}/客厅.json').existsSync(), isTrue);
    expect(File('${plans.path}/新建户型.json').existsSync(), isFalse,
        reason: '旧文件应删除');

    // JSON 里的 name 字段同步（列表靠它显示）
    final back = FloorPlan.fromJsonString(
        File('${plans.path}/客厅.json').readAsStringSync());
    expect(back.name, '客厅');
    expect(back.walls, hasLength(4), reason: '内容不能丢');

    // meta 跟着改名
    final meta = await store.loadMeta();
    expect(meta.containsKey('新建户型'), isFalse);
    expect(meta['客厅']?['sourcePath'], '/tmp/导入.json');
    expect(meta['客厅']?['label'], '导入.json');

    final names = (await store.list()).map((x) => x.name).toList();
    expect(names, ['客厅']);
  });

  test('同名冲突 → 抛 PlanRenameException（不覆盖别人的户型）', () async {
    final a = await saveAs('A');
    await saveAs('B');

    await expectLater(
      store.rename(a, 'B'),
      throwsA(isA<PlanRenameException>()
          .having((e) => e.message, 'message', '已有同名户型')),
    );
    // B 的内容没被 A 覆盖
    final plans = Directory('${dir.path}/plans');
    final b = FloorPlan.fromJsonString(
        File('${plans.path}/B.json').readAsStringSync());
    expect(b.name, 'B');
    expect(File('${plans.path}/A.json').existsSync(), isTrue);
  });

  test('非法字符清洗：a/b → a_b（文件名与 JSON name 都清洗）', () async {
    final e = await saveAs('A');
    await store.rename(e, 'a/b');

    final plans = Directory('${dir.path}/plans');
    expect(File('${plans.path}/a_b.json').existsSync(), isTrue);
    final back = FloorPlan.fromJsonString(
        File('${plans.path}/a_b.json').readAsStringSync());
    expect(back.name, 'a_b');
    expect((await store.list()).single.name, 'a_b');
  });

  test('空名 → 抛错（不静默变成「户型」）', () async {
    final e = await saveAs('A');
    await expectLater(store.rename(e, '   '), throwsA(isA<PlanRenameException>()));
  });

  testWidgets('列表行有「重命名」按钮 → 对话框预填现名', (tester) async {
    // 真实文件 IO 必须在 runAsync 里跑（testWidgets 的 fake async 不推进 IO）
    final entry = await tester.runAsync(() => saveAs('新建户型'));
    expect(entry!.name, '新建户型');

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: LandingPage(store: store)),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    expect(find.text('新建户型'), findsOneWidget);

    // 户型行上的改名入口（导出按钮旁）
    await tester.tap(find.byKey(ValueKey('rename_${entry.path}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('重命名户型'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '新建户型', reason: '对话框应预填现名');
    // 取消不改名
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(File('${dir.path}/plans/新建户型.json').existsSync(), isTrue);
  });
}
