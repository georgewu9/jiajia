import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// v0.1.36：庭院 12 件 CC0/CC-BY 素材（models_ext.js）挂进「模块 → 庭院」。
/// v0.1.37：删「坡道栏杆」（m_courtyard_ramp）→ 11 件；awning 增离地高度 1500mm。
void main() {
  // id → (中文名, w×d×h mm)，与 models_ext.js 的 w/d/h（米）一一对应
  const specs = <String, (String, int, int, int)>{
    'm_courtyard_awning': ('遮阳棚支架', 3100, 1690, 620),
    'm_courtyard_birch': ('白桦', 4160, 3860, 7920),
    'm_courtyard_chair': ('黑色露台椅', 290, 370, 620),
    'm_courtyard_table': ('黑色露台桌', 910, 920, 420),
    'm_courtyard_palm': ('扇叶棕榈', 5060, 5680, 6340),
    'm_courtyard_fountain': ('庭院喷泉', 1850, 1850, 1500),
    'm_courtyard_greenhouse': ('温室', 3100, 3100, 2900),
    'm_courtyard_pine': ('松树', 3400, 3760, 6130),
    'm_courtyard_railing': ('栏杆', 4750, 330, 1810),
    'm_courtyard_sassafras': ('马桑树', 1770, 1520, 2070),
    'm_courtyard_tree': ('庭院树', 7500, 8000, 10000),
  };

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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FloorplanEditorPage()),
      ),
    );
    await tester.pump();
    return (container, tester);
  }

  group('庭院目录', () {
    test('11 件存在、id 集合精确、全部地面摆放 + 显式规格（mm）', () {
      final items = ModelItems.ofCategory('庭院');
      expect(items.length, 11);
      expect(items.map((m) => m.id).toSet(), specs.keys.toSet());
      for (final m in items) {
        final s = specs[m.id]!;
        expect(m.label, s.$1, reason: '${m.id} 名称');
        expect(m.place, ModelPlace.floor, reason: '${m.id} 必须点画布摆放');
        expect(m.floorKind, FurnitureKind.asset, reason: '${m.id} 走素材 kind');
        expect(m.modelId, m.id, reason: '${m.id} 模型 id 必须与 models_ext.js 键一致');
        expect(m.specWmm, s.$2, reason: '${m.id} 宽');
        expect(m.specDmm, s.$3, reason: '${m.id} 深');
        expect(m.specHmm, s.$4, reason: '${m.id} 高');
        expect(m.specText, '${s.$2}×${s.$3}×${s.$4}');
      }
      // v0.1.37：坡道栏杆已删（素材/菜单/JS 三处同步移除）
      expect(ModelItems.byId('m_courtyard_ramp'), isNull);
      expect(items.any((m) => m.id == 'm_courtyard_ramp'), false);
      // byId 可反查（物品显示名用）
      expect(ModelItems.byId('m_courtyard_tree')?.label, '庭院树');
      expect(ModelItems.byId('m_courtyard_nope'), isNull);
    });

    test('离地高度：awning = 1500mm，其余庭院件 null（落地）', () {
      final a = ModelItems.byId('m_courtyard_awning')!;
      expect(a.offFloorMm, 1500);
      for (final m in ModelItems.ofCategory('庭院')) {
        if (m.id == 'm_courtyard_awning') continue;
        expect(m.offFloorMm, isNull, reason: '${m.id} 应落地');
      }
      // specText 不带离地高度（面板/规格文案仍 宽×深×高）
      expect(a.specText, '3100×1690×620');
    });

    test('credit：仅 fountain 非空（CC-BY 3.0 署名完整），其余为 null', () {
      final f = ModelItems.byId('m_courtyard_fountain')!;
      expect(f.credit, isNotNull);
      expect(f.credit, contains('pndrdm'));
      expect(f.credit, contains('blendswap.com/blends/view/78775'));
      expect(f.credit, contains('CC-BY 3.0'));
      expect(f.credit, contains('Emmanuel Puybaret / eTeks'));
      for (final m in ModelItems.ofCategory('庭院')) {
        if (m.id == 'm_courtyard_fountain') continue;
        expect(m.credit, isNull, reason: '${m.id} 不该带署名');
      }
    });

    test('JSON 往返保留 credit / 规格；旧数据缺 credit 宽容为 null', () {
      for (final m in ModelItems.ofCategory('庭院')) {
        final j = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
        final back = ModelSpec.fromJson(j);
        expect(back.id, m.id);
        expect(back.category, '庭院');
        expect(back.label, m.label);
        expect(back.place, ModelPlace.floor);
        expect(back.modelId, m.id);
        expect(back.specWmm, m.specWmm);
        expect(back.specDmm, m.specDmm);
        expect(back.specHmm, m.specHmm);
        expect(back.credit, m.credit);
      }
      // 旧版数据（无 credit / swmm / model / floor 键）不抛、回落默认
      final old = ModelSpec.fromJson(const {
        'id': 'legacy_item',
        'cat': '庭院',
        'label': '旧件',
        'place': 'floor',
      });
      expect(old.id, 'legacy_item');
      expect(old.credit, isNull);
      expect(old.specWmm, isNull);
      expect(old.modelId, isNull);
      expect(old.floorKind, isNull);
      expect(old.defaultWmm, 900);
      // 未知枚举名也不崩（宽容回落）
      final weird = ModelSpec.fromJson(const {
        'id': 'weird',
        'place': 'nowhere',
        'kind': 'nope',
        'floor': 'nope',
      });
      expect(weird.place, ModelPlace.floor);
      expect(weird.kind, OpeningKind.door);
      expect(weird.floorKind, isNull);
    });
  });

  group('庭院 UI', () {
    testWidgets('模块一级有「庭院」入口 → 二级 11 件网格 + CC-BY 角标/署名', (tester) async {
      await pumpEditorTall(tester);
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('庭院'), findsOneWidget);

      await tester.tap(find.text('庭院'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('庭院 · 素材（11 件）'), findsOneWidget);
      // 网格首末件都在（GridView shrinkWrap 全量构建）
      expect(find.text('遮阳棚支架'), findsOneWidget);
      expect(find.text('庭院树'), findsOneWidget);
      expect(find.text('庭院喷泉'), findsOneWidget);
      // fountain 的 CC-BY 角标
      expect(find.text('CC-BY'), findsOneWidget);
      // 署名落在 sheet 底部（app 无关于/设置页）→ 滚到底可见
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('3D 素材署名'), findsOneWidget);
      expect(find.textContaining('pndrdm'), findsOneWidget);
      // 返回一级
      await tester.tap(find.text('← 模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('门'), findsOneWidget);
    });

    testWidgets('选庭院件 → 点画布落地：item 带 modelId + spec 尺寸（米）', (tester) async {
      final (container, _) = await pumpEditorTall(tester);
      await tester.tap(find.text('模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('庭院'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('遮阳棚支架'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final cvF = find.byKey(const ValueKey('cv'));
      await tester.tapAt(tester.getRect(cvF).center);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final plan = container.read(editorDocProvider).plan;
      expect(plan.items.length, 1);
      final it = plan.items.values.first;
      expect(it.modelId, 'm_courtyard_awning');
      expect(it.kind, FurnitureKind.asset);
      expect(it.sizeW, closeTo(3.10, 0.001));
      expect(it.sizeD, closeTo(1.69, 0.001));
      expect(it.sizeH, closeTo(0.62, 0.001));
      expect(it.offFloorMm, 1500); // v0.1.37：吊装件默认离地 1.5m
      // 显示名走 ModelSpec（不是「素材」兜底）
      expect(find.textContaining('已放 遮阳棚支架'), findsOneWidget);
      // 保存/加载后 modelId + 尺寸不丢
      final rt = FloorPlan.fromJsonString(plan.toJsonString());
      final back = rt.items.values.first;
      expect(back.modelId, 'm_courtyard_awning');
      expect(back.sizeW, closeTo(3.10, 0.001));
    });
  });
}
