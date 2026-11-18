import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_assets.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

void main() {
  group('Opening 门型/高度（v0.1.8）', () {
    test('JSON 往返保留 doorType/height（新字段）', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0));
      p.openings['o1'] = Opening(
        id: 'o1',
        wallId: 'w1',
        kind: OpeningKind.door,
        doorType: DoorType.sliding,
        offset: 0.45,
        width: 1.0,
        height: 2.0,
      );
      final restored = FloorPlan.fromJsonString(p.toJsonString());
      final o = restored.openings['o1']!;
      expect(o.doorType, DoorType.sliding);
      expect(o.height, 2.0);
      expect(o.kind, OpeningKind.door);
    });

    test('旧 JSON（无 dt/ht）宽容解析：默认 单开门/门高 2.0', () {
      const legacy = '''
{
  "name": "old",
  "walls": [{"id":"w1","ax":0,"ay":0,"bx":3,"by":0,"t":0.24,"h":2.8}],
  "openings": [{"id":"o1","wall":"w1","kind":"door","off":1.0,"w":0.9,"sill":0}],
  "items": []
}''';
      final p = FloorPlan.fromJsonString(legacy);
      final o = p.openings['o1']!;
      expect(o.doorType, DoorType.single);
      expect(o.height, 2.0);
      expect(o.label, '单开门 900×2000内开·左开');
    });

    test('v0.1.18 JSON 往返保留 outSwing（外开）；旧 JSON 默认内开', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0));
      p.openings['o1'] = Opening(
        id: 'o1',
        wallId: 'w1',
        kind: OpeningKind.door,
        doorType: DoorType.double,
        offset: 1.0,
        width: 1.8,
        height: 2.1,
        outSwing: true,
      );
      final restored = FloorPlan.fromJsonString(p.toJsonString());
      final o = restored.openings['o1']!;
      expect(o.outSwing, true);
      expect(o.label, '双开门 1800×2100外开·左开');

      // 无 out 字段的旧 JSON → 内开
      final legacy = FloorPlan.fromJsonString(p.toJsonString()
          .replaceAll('"out":true', '"out":false'));
      expect(legacy.openings['o1']!.outSwing, false);
    });

    test('v0.1.24 铰链侧 hingeLeft：JSON 往返 + 旧 JSON 默认左开', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0));
      p.openings['o1'] = Opening(
        id: 'o1',
        wallId: 'w1',
        kind: OpeningKind.door,
        doorType: DoorType.single,
        offset: 0.5,
        width: 0.9,
        hingeLeft: false,
      );
      final raw = p.toJsonString();
      expect(raw.contains('"hl":false'), true, reason: 'JSON 键 hl 应存在');
      final o = FloorPlan.fromJsonString(raw).openings['o1']!;
      expect(o.hingeLeft, false);
      expect(o.label, '单开门 900×2000内开·右开');

      // 旧 JSON（无 hl）→ 左开
      final legacy = FloorPlan.fromJsonString(
          raw.replaceAll(',"hl":false', ''));
      expect(legacy.openings['o1']!.hingeLeft, true);
      expect(legacy.openings['o1']!.label, '单开门 900×2000内开·左开');
    });

    test('门型默认值符合家易量习惯（mm）', () {
      expect(DoorType.doorway.defaultWidthMm, 900);
      expect(DoorType.single.defaultWidthMm, 900);
      expect(DoorType.double.defaultWidthMm, 1500);
      expect(DoorType.sliding.defaultWidthMm, 1000);
      expect(DoorType.double.defaultHeightMm, 2100);
      expect(DoorType.single.label, '单开门');
    });

    test('窗口默认：窗高 1.5m，标签含窗台', () {
      final o = Opening(
        id: 'o2',
        wallId: 'w1',
        kind: OpeningKind.window,
        offset: 0.5,
        width: 1.5,
        sill: 0.9,
      );
      expect(o.height, 1.5);
      expect(o.label, '窗 1500×1500(台900)');
    });

    test('mm 换算取整', () {
      expect(toMm(2.8), 2800);
      expect(toMm(0.24), 240);
      expect(fromMm(1500), 1.5);
    });

    test('importPlan 同步 id 序列（不撞号）', () {
      final a = FloorPlan()..importPlan(samplePlan());
      // 示例用到 w1-w4/o1-o2/i1-i3。newId 用共享计数器，
      // 导入后 _seq 已同步到最大值 → 新 id 不会与任何已导入 id 撞号。
      final importedW = {'w1', 'w2', 'w3', 'w4'};
      final importedO = {'o1', 'o2'};
      final importedI = {'i1', 'i2', 'i3'};
      for (int i = 0; i < 6; i++) {
        expect(importedW.contains(a.newId('w')), false, reason: 'w 撞号');
      }
      expect(importedO.contains(a.newId('o')), false, reason: 'o 撞号');
      expect(importedI.contains(a.newId('i')), false, reason: 'i 撞号');
    });
  });

  group('素材模型（原 app 26 件，v0.1.10）', () {
    test('目录有 26 件且分类齐全', () {
      expect(ModelAssets.all.length, 26);
      expect(ModelAssets.categories,
          ['门', '五金', '柜', '栏杆', '柱', '墙体', '基础体']);
      for (final m in ModelAssets.all) {
        expect(m.w > 0 && m.d > 0 && m.h > 0, true, reason: '尺寸须为正');
      }
    });

    test('FurnitureItem 带 modelId：JSON 往返 + 占地取素材', () {
      final p = FloorPlan();
      p.walls['w1'] = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0));
      p.items['i1'] = FurnitureItem(
          id: 'i1',
          kind: FurnitureKind.asset,
          pos: const Vec2(1, 1),
          modelId: '1007');
      final restored = FloorPlan.fromJsonString(p.toJsonString());
      final i = restored.items['i1']!;
      expect(i.modelId, '1007');
      expect(i.kind, FurnitureKind.asset);
      // 占地 = 大衣柜（1.84×0.62），不是 asset 默认占位盒（0.6×0.6）
      final (fw, fd) = i.footprint;
      expect(fw, closeTo(1.84, 1e-9));
      expect(fd, closeTo(0.62, 1e-9));
      // 3D 契约：items[].model 字段存在
      expect(p.toJson()['items'][0]['model'], '1007');
    });

    test('旧 JSON 无 model 字段 → modelId 为 null（向后兼容）', () {
      final raw = jsonEncode({
        'name': 't',
        'walls': [
          Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(3, 0)).toJson()
        ],
        'openings': <dynamic>[],
        'items': [
          {'id': 'i1', 'kind': 'sofa', 'x': 1.0, 'y': 1.0, 'rot': 0}
        ],
      });
      final restored = FloorPlan.fromJsonString(raw);
      expect(restored.items['i1']!.modelId, isNull);
      expect(restored.items['i1']!.kind, FurnitureKind.sofa);
    });
  });

  group('PlanStore 名称清洗（v0.1.11 保存/打开）', () {
    test('非法字符替换 / 去空白 / 限长 / 空给默认', () {
      expect(
          PlanStore.sanitizeName(r'a/b\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
      expect(PlanStore.sanitizeName('   '), '户型');
      expect(PlanStore.sanitizeName('x' * 60).length, 40);
      expect(PlanStore.sanitizeName('  我的户型  '), '我的户型');
    });
  });
}
