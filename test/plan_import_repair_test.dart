import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/features/floorplan/state/plan_io.dart';

/// v0.1.51 止血：SAF「同名文件不截断覆盖」事故的回归。
///
/// 现场文件（test/testdata/plan_tail_corrupt.json，原封不动从用户机器复制）：
///   · 0..8291 字节 = 完整户型 JSON（name=户型1118，walls 32，items 35）
///   · 8291..8666 = 上一版长文档的尾巴（i134/i136/i137 + `]}`）
///   jsonDecode 在 8291 处抛 Extra data → 旧版整份户型导不进来。
void main() {
  final corruptFile = File('test/testdata/plan_tail_corrupt.json');

  /// 用户机器上那份原始字节（含旧尾巴）。
  String corruptText() => corruptFile.readAsStringSync();

  group('尾部旧数据修复（真实事故文件）', () {
    test('a) 回归证明：直接 jsonDecode 全文必抛 FormatException（Extra data）', () {
      expect(corruptFile.existsSync(), isTrue,
          reason: 'testdata 缺失：test/testdata/plan_tail_corrupt.json');
      final text = corruptText();
      FormatException? err;
      try {
        jsonDecode(text);
      } on FormatException catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: '全文应当解析失败（新头 + 旧尾）');
      // 现场偏移量：8291（0 基）。修复后 offset 不再出现在用户提示里。
      expect(err!.offset, 8291);
      // Dart 的措辞是 'Unexpected character'（Python 是 Extra data），
      // 这里只钉「确实是尾部多出来的内容」这一事实 + 偏移量。
      expect(err.message, isNotEmpty);
    });

    test('b) fromJsonString 走修复：名称/墙/家具正确，且修复被标记', () {
      final text = corruptText();
      var repairedDropped = -1;
      final plan = FloorPlan.fromJsonString(
        text,
        onRepaired: (n) => repairedDropped = n,
      );

      expect(repairedDropped, greaterThan(0), reason: '必须报告发生过截断修复');
      expect(text.length - repairedDropped, 8291,
          reason: '截断点应正好是第一个顶层对象闭合处');

      expect(plan.name, '户型1118');
      expect(plan.walls, hasLength(32));
      expect(plan.openings, hasLength(15));
      expect(plan.items, hasLength(35));
      // 事故文件里 items 的最后一项是 i132（不是 i133：那条属于旧尾巴，
      // 已被截掉，不该出现在结果里）
      expect(plan.items.keys.last, 'i132');
      expect(plan.items.containsKey('i133'), isFalse);
      expect(plan.items.containsKey('i134'), isFalse,
          reason: '旧尾巴里的 i134/i136/i137 不能被带进来');
      // 抽查几何真回来了（不是空壳）
      expect(plan.walls['w1']!.a.x, closeTo(2.707, 1e-9));
      expect(plan.items['i132']!.modelId, 'm_furn_refrigerator');
    });

    test('c) 正常文件：零行为变化，解析器不被扫描器接管', () {
      final src = FloorPlan()..name = '正常户型';
      src.addRoom(at: const Vec2(0, 0), l: 4, w: 3, withDoor: true);
      final text = src.toJsonString();

      var called = false;
      final back = FloorPlan.fromJsonString(text, onRepaired: (_) => called = true);

      expect(called, isFalse, reason: '合法文件不能走修复分支');
      expect(back.name, '正常户型');
      expect(back.walls, hasLength(src.walls.length));
      expect(back.openings, hasLength(src.openings.length));
      expect(jsonEncode(back.toJson()), text, reason: '解析后再序列化应逐字节一致');
    });

    test('字符串里含 } / ] / 引号时，扫描器不被骗（转义状态跟踪）', () {
      final src = FloorPlan()..name = r'怪名"]} 带引号"';
      src.addRoom(at: const Vec2(0, 0), l: 2, w: 2, withDoor: false);
      final clean = src.toJsonString();
      final dirty = '$clean{"id":"i999","kind":"sofa","x":0,"y":0}';

      var dropped = -1;
      final back = FloorPlan.fromJsonString(dirty, onRepaired: (n) => dropped = n);
      expect(back.name, r'怪名"]} 带引号"');
      expect(back.walls, hasLength(4));
      expect(back.items, isEmpty);
      expect(dropped, dirty.length - clean.length);
    });

    test('真损坏（括号不配对 / 内容坏）不静默吞：仍抛 FormatException', () {
      // 前半截被覆盖成「只有开头」：没有闭合的顶层对象 → 无从截断
      expect(
        () => FloorPlan.fromJsonString('{"name":"半截", "walls":[{"id":"w1"'),
        throwsFormatException,
      );
      // 完整对象但内容不是户型（缺 walls）→ 结构异常（TypeError）照旧抛
      expect(() => FloorPlan.fromJsonString('{"name":"没有墙"}'), throwsA(anything));
      // 顶层不是对象
      expect(() => FloorPlan.fromJsonString('"just a string"'), throwsA(anything));
    });
  });

  group('原子写：save / writeBack 不留下半截文件', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jj_atomic_');
    });
    tearDown(() => dir.delete(recursive: true));

    test('d) PlanStore.save：目标文件可正常解析、无 .tmp 残留', () async {
      final store = PlanStore(root: dir);
      final p = FloorPlan()
        ..name = '原子户型'
        ..addRoom(at: const Vec2(0, 0), l: 5, w: 4, withDoor: true);
      p.items['i1'] = FurnitureItem(
          id: 'i1', kind: FurnitureKind.sofa, pos: const Vec2(1, 1));

      final path = await store.save(p);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse, reason: '.tmp 必须被 rename 消化');

      final back = FloorPlan.fromJsonString(File(path).readAsStringSync());
      expect(back.name, '原子户型');
      expect(back.walls, hasLength(4));
      expect(back.items, hasLength(1));

      // 再存一次（更短的内容）：不能像 SAF 那样把旧尾巴留在后面
      p.items.clear();
      await store.save(p);
      expect(File('$path.tmp').existsSync(), isFalse);
      final again = File(path).readAsStringSync();
      expect(again, p.toJsonString(), reason: '覆盖后字节应恰好等于本次内容');
      expect(() => jsonDecode(again), returnsNormally);
      expect(FloorPlan.fromJsonString(again).items, isEmpty);
    });

    test('writeBack(file://)：原子覆盖、无 .tmp 残留、字节一致', () async {
      final src = File('${dir.path}/外部.json');
      src.writeAsStringSync((FloorPlan()..name = '很长的旧名字旧名字旧名字').toJsonString());

      final p = FloorPlan()..name = '短';
      final bytes = Uint8List.fromList(utf8.encode(p.toJsonString()));
      expect(PlanIo.writeBack(bytes, src.uri.toString()), WriteBack.synced);

      expect(src.readAsBytesSync(), bytes, reason: '不能有旧尾巴残留');
      expect(File('${src.path}.tmp').existsSync(), isFalse);
      expect(() => jsonDecode(src.readAsStringSync()), returnsNormally);
    });
  });
}
