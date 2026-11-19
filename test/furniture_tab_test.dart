import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/theme.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/furniture_tabs.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.31：模块 → 家具 一级入口 + 5 个二级分类（卧室/客餐厅/书房/厨房/其他）。
void main() {
  group('domain: 家具分类表', () {
    test('5 分类 + 数量 6/6/4/8/3', () {
      expect(FurnitureTabs.cats, ['卧室', '客餐厅', '书房', '厨房', '其他']);
      expect(FurnitureTabs.items.length, 5);
      expect(FurnitureTabs.items['卧室']!.length, 6);
      expect(FurnitureTabs.items['客餐厅']!.length, 6);
      expect(FurnitureTabs.items['书房']!.length, 4);
      expect(FurnitureTabs.items['厨房']!.length, 8);
      expect(FurnitureTabs.items['其他']!.length, 3);
      // 每个分类下解析出的项数与引用数一致（没有解析失败被过滤掉）
      for (final c in FurnitureTabs.cats) {
        expect(
          FurnitureTabs.ofCat(c).length,
          FurnitureTabs.items[c]!.length,
          reason: '$c 有引用解析失败',
        );
      }
    });

    test('resolve 全可解析（kind 或 model 来源明确）', () {
      for (final refs in FurnitureTabs.items.values) {
        for (final r in refs) {
          final it = FurnitureTabs.resolve(r);
          expect(it, isNotNull, reason: '解析失败：$r');
          expect(it!.label.isNotEmpty, true);
          // 二选一：家具 kind 或 ModelItems 模型素材，不能都空/都填
          expect((it.kind != null) ^ (it.model != null), true, reason: r);
          expect(it.specText.isNotEmpty, true);
        }
      }
      // 未知引用 → null（不抛异常）
      expect(FurnitureTabs.resolve('kind:nope'), isNull);
      expect(FurnitureTabs.resolve('model:nope'), isNull);
      expect(FurnitureTabs.resolve('bogus'), isNull);
    });

    test('跨分类复用：书桌出现 2 次（卧室 + 书房）', () {
      final refs = [
        for (final c in FurnitureTabs.cats) ...FurnitureTabs.items[c]!,
      ];
      expect(refs.where((r) => r == 'kind:desk').length, 2);
      // 卧室/书房都能解析出「书桌」
      for (final c in ['卧室', '书房']) {
        expect(
          FurnitureTabs.ofCat(c).any((it) => it.label == '书桌'),
          true,
          reason: '$c 缺书桌',
        );
      }
    });

    test('批准映射的落地结果（以代码标签为准）', () {
      // 梳妆台 = ModelItems 的 shuzhuangtai（台面/五金），不是 FurnitureKind
      final vanity = FurnitureTabs.resolve('model:shuzhuangtai')!;
      expect(vanity.label, '梳妆台');
      expect(vanity.model!.floorKind, FurnitureKind.vanity);
      expect(vanity.model!.icon, isNotNull);
      // 暖气片 = nuanqipian / radiator（FurnitureKind.heater 实为「热水器」，不用它）
      final rad = FurnitureTabs.resolve('model:nuanqipian')!;
      expect(rad.label, '暖气片');
      expect(rad.model!.floorKind, FurnitureKind.radiator);
      // 5 个分类里的中文名（测试 ② 依赖这几个）
      expect(FurnitureTabs.resolve('kind:fridge')!.label, '冰箱');
      expect(FurnitureTabs.resolve('kind:hood')!.label, '烟机');
      expect(FurnitureTabs.resolve('kind:bed')!.label, '床');
    });
  });

  Future<ProviderContainer> pumpEditorTall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FloorplanEditorPage()),
      ),
    );
    await tester.pump();
    return container;
  }

  Future<void> openFurnitureSheet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ActionChip, '模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
    expect(find.text('家具'), findsOneWidget);
    await tester.tap(
      find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('editor: 模块 → 家具 抽屉', () {
    testWidgets('切「厨房」→ 冰箱/烟机；切「卧室」→ 床', (tester) async {
      await pumpEditorTall(tester);
      await openFurnitureSheet(tester);

      // 默认「卧室」
      expect(find.text('床'), findsOneWidget);
      expect(find.text('梳妆台'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '厨房'));
      await tester.pump();
      expect(find.text('冰箱'), findsOneWidget);
      expect(find.text('烟机'), findsOneWidget);
      expect(find.text('暖气片'), findsOneWidget);
      expect(find.text('床'), findsNothing); // 换列表了

      await tester.tap(find.widgetWithText(ChoiceChip, '卧室'));
      await tester.pump();
      expect(find.text('床'), findsOneWidget);
      expect(find.text('冰箱'), findsNothing);
    });

    testWidgets('「← 模块」返回一级菜单', (tester) async {
      await pumpEditorTall(tester);
      await openFurnitureSheet(tester);
      await tester.tap(find.text('← 模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('拆改'), findsOneWidget);
      expect(find.text('特殊墙窗'), findsOneWidget);
    });

    testWidgets('选「床」→ 点画布放下 → 自动回「选择」+ kind=bed', (tester) async {
      final container = await pumpEditorTall(tester);
      await openFurnitureSheet(tester);
      await tester.tap(find.text('床'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // sheet 关闭

      // 工具条提示进入放置态
      expect(find.textContaining('放：床'), findsOneWidget);

      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('cv'))));
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
      await tester.pump();

      final plan = container.read(editorDocProvider).plan;
      expect(plan.items.length, 1);
      expect(plan.items.values.first.kind, FurnitureKind.bed);

      // 铁律：放完自动回「选择」
      final chip = tester.widget<ActionChip>(
        find
            .ancestor(of: find.text('选择'), matching: find.byType(ActionChip))
            .first,
      );
      expect(chip.backgroundColor, JiajiaColors.accentSoft);
    });

    testWidgets('选「梳妆台」（model 素材）→ 走 model 放置路径', (tester) async {
      final container = await pumpEditorTall(tester);
      await openFurnitureSheet(tester);
      await tester.tap(find.text('梳妆台'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('cv'))));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final plan = container.read(editorDocProvider).plan;
      expect(plan.items.length, 1);
      expect(plan.items.values.first.kind, FurnitureKind.vanity);
      expect(
        plan.items.values.first.modelId,
        isNull,
      ); // ModelSpec 路径：kind=vanity
    });
  });

  group('kind=lib 四处铁律（enum/spec/labelOf/viewer CATALOG）', () {
    test('新增 FurnitureKind.lib 后四处同步，缺 labelOf 会运行时崩', () {
      expect(FurnitureKind.values, contains(FurnitureKind.lib));
      expect(FurnitureCatalog.spec.containsKey(FurnitureKind.lib), true);
      final s = FurnitureCatalog.spec[FurnitureKind.lib]!;
      expect([s.$1, s.$2, s.$3], [1.0, 0.6, 1.0]); // 灰占位默认 1×0.6×1
      expect(FurnitureCatalog.labelOf(FurnitureKind.lib), '库模型');
      // 第四处：viewer.js CATALOG 必须同 key/同尺寸/同色，否则 3D 找不到占位规格
      final js = File('assets/web/viewer.js').readAsStringSync();
      expect(js.contains('lib: [1.0, 0.6, 1.0, 0x8f8f8f]'), true);
    });
  });

  group('editor: 模型库入口（P2/P3）', () {
    testWidgets('网格有「导入模型…」固定 tile + 顶部导入/导出按钮；点按不崩', (tester) async {
      await pumpEditorTall(tester);
      await openFurnitureSheet(tester);

      expect(find.byKey(const ValueKey('import_obj_tile')), findsOneWidget);
      expect(find.text('导入模型…'), findsOneWidget);
      expect(find.text('导出模型库'), findsOneWidget);
      expect(find.text('导入模型库'), findsOneWidget);

      // widget 测试环境没有 file_picker 平台实现：点按应只弹 SnackBar，不崩
      await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 固定 tile 不随分类消失
      await tester.tap(find.widgetWithText(ChoiceChip, '厨房'));
      await tester.pump();
      expect(find.byKey(const ValueKey('import_obj_tile')), findsOneWidget);
      expect(find.text('导入模型…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('画布绘制 kind=lib 物品（RRect 占地 + 名字缺库回退）不崩',
        (tester) async {
      final container = await pumpEditorTall(tester);
      container.read(editorDocProvider.notifier).mutate((p) {
        p.items['i1'] = FurnitureItem(
          id: 'i1',
          kind: FurnitureKind.lib,
          pos: const Vec2(1.2, 1.4),
          rotationDeg: 30,
          lib: 'not-imported', // 库不存在 → 名字回退「库模型」
          sizeW: 1.1,
          sizeD: 0.7,
          sizeH: 0.9,
        );
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(container.read(editorDocProvider).plan.items['i1']!.kind,
          FurnitureKind.lib);
    });
  });
}
