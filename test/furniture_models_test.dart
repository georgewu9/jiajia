import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/furniture_tabs.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.37：42 件清洗后家具 OBJ（models_ext.js cat=家具）挂进「模块 → 家具」二级菜单。
/// 规格以 manifest.json bbox_m（x,z,y）取整毫米；Dart / JS 两边必须一致。
void main() {
  // id → (中文名, 所属 tab, w×d×h mm, 颜色)
  const specs = <String, (String, String, int, int, int, int)>{
    'm_furn_armoire': ('衣柜', '书房', 1795, 675, 2214, 0x8B6F4E),
    'm_furn_office_chair': ('办公椅', '书房', 480, 495, 870, 0x5C6B7A),
    'm_furn_desk': ('书桌', '书房', 1400, 591, 758, 0x8B6F4E),
    'm_furn_stool': ('坐凳', '书房', 458, 448, 790, 0x8B6F4E),
    'm_furn_cappa': ('烟罩（cappa，待认）', '其他', 811, 610, 750, 0xC8C8C8),
    'm_furn_flowers': ('插花', '其他', 392, 297, 938, 0x4E7B3A),
    'm_furn_fridge_2': ('冰箱', '其他', 611, 738, 2221, 0xC8C8C8),
    'm_furn_piano': ('立式钢琴', '其他', 2880, 1140, 2220, 0x3A2A1A),
    'm_furn_potplant': ('盆栽', '其他', 967, 962, 854, 0x4E7B3A),
    'm_furn_refrigerator': ('冰箱', '其他', 675, 574, 1476, 0xC8C8C8),
    'm_furn_piano_stool': ('钢琴凳', '其他', 720, 760, 970, 0x8B6F4E),
    'm_furn_frame_vatican': ('画框', '其他', 612, 16, 479, 0x8A5A2B),
    'm_furn_frame_yosemite': ('画框', '其他', 735, 16, 479, 0x8A5A2B),
    'm_furn_washer_dryer': ('洗烘一体', '其他', 595, 550, 850, 0xC8C8C8),
    'm_furn_upper_cab_2d': ('双门吊柜', '卧室', 675, 393, 600, 0x8B6F4E),
    'm_furn_dresser': ('斗柜', '卧室', 1436, 485, 642, 0x8B6F4E),
    'm_furn_bed': ('双人床', '卧室', 1840, 1970, 650, 0x5C6B7A),
    'm_furn_pantry': ('食品柜', '卧室', 835, 542, 1569, 0x8B6F4E),
    'm_furn_lower_cab_1d': ('单门地柜', '厨卫', 394, 564, 654, 0x8B6F4E),
    'm_furn_upper_cab_1d': ('单门吊柜', '厨卫', 339, 393, 600, 0x8B6F4E),
    'm_furn_lower_cab_2d': ('双门地柜', '厨卫', 729, 564, 654, 0x8B6F4E),
    'm_furn_cab_3draw': ('三抽柜', '厨卫', 393, 643, 641, 0x8B6F4E),
    'm_furn_shower_tray': ('淋浴底盘', '厨卫', 900, 900, 65, 0xE8E8E0),
    'm_furn_vanity': ('浴室柜', '厨卫', 1220, 550, 780, 0x8B6F4E),
    'm_furn_jacuzzi': ('按摩浴缸', '厨卫', 1600, 700, 580, 0xE8E8E0),
    'm_furn_corner_cab': ('转角柜', '厨卫', 330, 437, 340, 0x8B6F4E),
    'm_furn_shower_room': ('淋浴房', '厨卫', 700, 700, 2000, 0xE8E8E0),
    'm_furn_hob': ('燃气灶', '厨卫', 600, 400, 31, 0x444444),
    'm_furn_island': ('中岛', '厨卫', 1318, 587, 567, 0x8B6F4E),
    'm_furn_marble_sink': ('大理石水槽柜', '厨卫', 1118, 852, 1611, 0x8B6F4E),
    'm_furn_mirror': ('镜子', '厨卫', 501, 10, 701, 0x9FB4C7),
    'm_furn_shower_cabin': ('淋浴间', '厨卫', 900, 900, 1990, 0xE8E8E0),
    'm_furn_toilet': ('壁挂马桶', '厨卫', 380, 565, 820, 0xE8E8E0),
    'm_furn_basin': ('water（卫浴小件）', '厨卫', 360, 557, 453, 0xE8E8E0),
    'm_furn_sofa_cherry': ('樱桃沙发', '客餐厅', 600, 1600, 700, 0x5C6B7A),
    'm_furn_sofa_cushion': ('抱枕沙发', '客餐厅', 1597, 722, 767, 0x5C6B7A),
    'm_furn_coffee_table': ('茶几', '客餐厅', 1001, 701, 440, 0x8B6F4E),
    'm_furn_sofa_large': ('大沙发', '客餐厅', 2364, 766, 751, 0x5C6B7A),
    'm_furn_chest_tall': ('高柜', '客餐厅', 1000, 500, 2400, 0x8B6F4E),
    'm_furn_table_round': ('圆桌', '客餐厅', 959, 950, 751, 0x8B6F4E),
    'm_furn_armchair': ('单人沙发椅', '客餐厅', 1011, 771, 750, 0x5C6B7A),
    'm_furn_table_low': ('矮桌', '客餐厅', 896, 515, 379, 0x8B6F4E),
  };

  group('furniture: 家具实模目录（42 件）', () {
    test('id 集合精确 + 全部地面摆放 + 显式规格（mm）', () {
      final items = ModelItems.ofCategory('家具');
      expect(items.length, 42);
      expect(items.map((m) => m.id).toSet(), specs.keys.toSet());
      for (final m in items) {
        final s = specs[m.id]!;
        expect(m.label, s.$1, reason: '${m.id} 名称');
        expect(m.place, ModelPlace.floor, reason: '${m.id} 必须点画布摆放');
        expect(m.floorKind, FurnitureKind.asset, reason: '${m.id} 走素材 kind');
        expect(m.modelId, m.id, reason: '${m.id} 模型 id 必须与 models_ext.js 键一致');
        expect(m.specWmm, s.$3, reason: '${m.id} 宽');
        expect(m.specDmm, s.$4, reason: '${m.id} 深');
        expect(m.specHmm, s.$5, reason: '${m.id} 高');
        expect(m.specText, '${s.$3}×${s.$4}×${s.$5}');
        expect(m.category, '家具');
        expect(m.credit, isNull);
        expect(m.offFloorMm, isNull, reason: '${m.id} 家具落地（只有庭院 awning 吊装）');
      }
      // 42 件 id 无重复（同名 OBJ 只落一条 spec）
      expect(ModelItems.all.where((m) => m.category == '家具').length, 42);
    });

    test('每件都在 furniture_tabs 里出现≥1 次，且出现的 tab 与清单一致', () {
      for (final e in specs.entries) {
        final id = e.key;
        final wantTab = e.value.$2;
        final tabs = [
          for (final c in FurnitureTabs.cats)
            if (FurnitureTabs.items[c]!.contains('model:$id')) c,
        ];
        expect(tabs.contains(wantTab), true, reason: '$id 应出现在 $wantTab');
        expect(tabs.isNotEmpty, true, reason: '$id 未进任何 tab');
      }
    });

    test('models_ext.js 含全部 42 个 key，w/d/h（米）与 Dart 规格同步', () {
      final f = File('assets/web/models_ext.js');
      expect(f.existsSync(), true);
      final js = f.readAsStringSync();
      final re = RegExp(r'"w":([0-9.]+),"d":([0-9.]+),"h":([0-9.]+),"c":(\d+)');
      for (final e in specs.entries) {
        final id = e.key;
        final key = '"$id":';
        final i = js.indexOf(key);
        expect(i >= 0, true, reason: 'models_ext.js 缺 $id');
        final head = js.substring(i, i + 200);
        expect(head.contains('"cat":"家具"'), true, reason: '$id cat');
        final m = re.firstMatch(head);
        expect(m, isNotNull, reason: '$id 缺 w/d/h/c');
        expect(double.parse(m!.group(1)!), closeTo(e.value.$3 / 1000, 1e-9),
            reason: '$id 宽');
        expect(double.parse(m.group(2)!), closeTo(e.value.$4 / 1000, 1e-9),
            reason: '$id 深');
        expect(double.parse(m.group(3)!), closeTo(e.value.$5 / 1000, 1e-9),
            reason: '$id 高');
        expect(int.parse(m.group(4)!), e.value.$6, reason: '$id 颜色');
      }
      // 既有 19 条门窗/庭院条目仍在（不能被追加覆盖）
      expect(js.contains('"m_door1":'), true);
      expect(js.contains('"m_courtyard_fountain":'), true);
    });

    test('JSON 往返保留 modelId / 规格', () {
      final m = ModelItems.byId('m_furn_bed')!;
      final back = ModelSpec.fromJson(
          Map<String, dynamic>.from(m.toJson()));
      expect(back.category, '家具');
      expect(back.modelId, 'm_furn_bed');
      expect(back.specWmm, 1840);
      expect(back.specDmm, 1970);
      expect(back.specHmm, 650);
    });
  });

  group('furniture UI: 42 件都能在抽屉里找到并落到画布', () {
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

    testWidgets('5 个 tab 的 tile 数与清单一致（含重复出现的 2 件）', (tester) async {
      await pumpEditorTall(tester);
      await tester.tap(find.widgetWithText(ActionChip, '模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (final c in FurnitureTabs.cats) {
        await tester.tap(find.widgetWithText(ChoiceChip, c));
        await tester.pump();
        final wanted = FurnitureTabs.items[c]!.length;
        expect(find.textContaining('家具 · $c（$wanted 件）'), findsOneWidget,
            reason: '$c 标题件数');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('厨卫 19 件 tile 全部可见；点「单门地柜」落地尺寸 0.394×0.564×0.654',
        (tester) async {
      final container = await pumpEditorTall(tester);
      await tester.tap(find.widgetWithText(ActionChip, '模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(ChoiceChip, '厨卫'));
      await tester.pump();
      for (final label in [
        '单门地柜', '单门吊柜', '双门地柜', '双门吊柜', '三抽柜', '淋浴底盘',
        '浴室柜', '按摩浴缸', '转角柜', '淋浴房', '燃气灶', '中岛',
        '大理石水槽柜', '镜子', '淋浴间', '壁挂马桶', 'water（卫浴小件）',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '厨卫缺 $label');
      }
      expect(find.text('冰箱'), findsOneWidget);
      expect(find.text('洗衣机'), findsOneWidget);

      await tester.tap(find.text('单门地柜'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final cvF = find.byKey(const ValueKey('cv'));
      await tester.tapAt(tester.getRect(cvF).center);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final it = container.read(editorDocProvider).plan.items.values.single;
      expect(it.modelId, 'm_furn_lower_cab_1d');
      expect(it.offFloorMm, 0, reason: '落地件放置时显式写 0');
      expect(it.sizeW, closeTo(0.394, 0.0001));
      expect(it.sizeD, closeTo(0.564, 0.0001));
      expect(it.sizeH, closeTo(0.654, 0.0001));
    });

    testWidgets('其他 10 件 tile 全部可见（含待认名字两条）', (tester) async {
      await pumpEditorTall(tester);
      await tester.tap(find.widgetWithText(ActionChip, '模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ChoiceChip, '其他'));
      await tester.pump();
      for (final label in [
        '烟罩（cappa，待认）', '插花', '冰箱', '立式钢琴', '盆栽',
        '钢琴凳', '画框', '洗烘一体',
      ]) {
        expect(find.text(label), findsWidgets, reason: '其他缺 $label');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
