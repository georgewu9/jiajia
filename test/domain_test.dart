import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';

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
      expect(o.label, '单开门 900×2000');
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
}
