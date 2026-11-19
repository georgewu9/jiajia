import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';

/// P2/P3：模型库存储（临时目录注入，不依赖 path_provider 通道）+ 导出/导入信封。
void main() {
  const objTri = 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n';
  const objQuad = 'v 0 0 0\nv 2 0 0\nv 2 0 1\nv 0 0 1\nf 1 2 3\nf 1 3 4\n';

  LibModel mk(
    String id,
    String name,
    String cat, {
    String obj = objTri,
    double w = 1.0,
    double d = 0.6,
    double h = 1.0,
  }) {
    return LibModel(
      id: id,
      name: name,
      cat: cat,
      wM: w,
      dM: d,
      hM: h,
      objText: obj,
    );
  }

  Future<Directory> tmp() async {
    final dir = await Directory.systemTemp.createTemp('jj_libmodels_');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  test('store 存读 round-trip：lib_models.json 在根下（与 plans/ 同级）', () async {
    final docs = await tmp();
    final store = LibModelsStore(root: docs);
    final a = mk('aaa111', '椅子', '卧室', obj: objQuad, w: 2, d: 1, h: 0.9);
    final b = mk('bbb222', '冰箱', '厨房');
    await store.save([a, b]);

    final file = File('${docs.path}/lib_models.json');
    expect(file.existsSync(), true);
    expect(File('${docs.path}/plans/lib_models.json').existsSync(), false);

    // 用新实例读（模拟重启 app）
    final back = await LibModelsStore(root: docs).load();
    expect(back.length, 2);
    final ra = back.firstWhere((m) => m.id == 'aaa111');
    expect(ra.name, '椅子');
    expect(ra.cat, '卧室');
    expect(ra.wM, closeTo(2, 1e-9));
    expect(ra.dM, closeTo(1, 1e-9));
    expect(ra.hM, closeTo(0.9, 1e-9));
    expect(ra.objText, objQuad);
    // 名字缓存给 2D 标注用
    expect(LibModelsStore.nameOf('aaa111'), '椅子');
    expect(LibModelsStore.nameOf('nope'), isNull);
  });

  test('add：同 id 跳过；同分类同名自动 (1)', () async {
    final docs = await tmp();
    final store = LibModelsStore(root: docs);
    final base = mk('id1', '置物架', '书房');
    final list1 = await store.add(base);
    expect(list1.length, 1);

    // 同一 OBJ 再导一次 → id 相同 → 不新增
    final dup = await store.add(mk('id1', '置物架', '书房'));
    expect(dup.length, 1);

    // 不同 id、同分类同名 → 名字加 (1)
    final list3 = await store.add(mk('id2', '置物架', '书房'));
    expect(list3.length, 2);
    expect(list3.map((m) => m.name), containsAll(['置物架', '置物架(1)']));

    // 第三个同名 → (2)
    final list4 = await store.add(mk('id3', '置物架', '书房'));
    expect(list4.map((m) => m.name), contains('置物架(2)'));
    // 不同分类同名不冲突
    final list5 = await store.add(mk('id4', '置物架', '厨房'));
    expect(list5.map((m) => m.name), contains('置物架'));
    expect(list5.length, 4);
  });

  test('remove 按 id 删除并落盘', () async {
    final docs = await tmp();
    final store = LibModelsStore(root: docs);
    await store.save([mk('a', 'A', '卧室'), mk('b', 'B', '卧室')]);
    final left = await store.remove('a');
    expect(left.map((m) => m.id), ['b']);
    expect((await LibModelsStore(root: docs).load()).length, 1);
  });

  test('文件缺失 / 损坏 → 空列表，不崩', () async {
    final docs = await tmp();
    final store = LibModelsStore(root: docs);
    expect(await store.load(), isEmpty); // 缺失
    File('${docs.path}/lib_models.json').writeAsStringSync('{not json');
    expect(await store.load(), isEmpty); // 损坏
    File('${docs.path}/lib_models.json').writeAsStringSync('[1,2,3]');
    expect(await store.load(), isEmpty); // 结构不对
    File('${docs.path}/lib_models.json')
        .writeAsStringSync('{"models":[{"id":"x"}]}');
    expect(await store.load(), isEmpty); // 条目字段不全 → 跳过（不是崩）
  });

  test('merge：id 重复跳过计数 + 同名 (1)', () {
    final existing = [mk('id1', '椅子', '卧室')];
    final incoming = [
      mk('id1', '椅子', '卧室'), // 重复 id → 跳过
      mk('id2', '椅子', '卧室'), // 同名 → (1)
      mk('id3', '床', '卧室'),
    ];
    final r = LibModelsStore.merge(existing, incoming);
    expect(r.added, 2);
    expect(r.skipped, 1);
    expect(r.models.length, 3);
    expect(r.models.map((m) => m.name), containsAll(['椅子', '椅子(1)', '床']));
  });

  test('导出/导入信封：type 校验 + 逐条 schema + 尺寸 bbox 兜底', () {
    final models = [
      mk('id1', '椅子', '卧室', obj: objQuad, w: 2, d: 1, h: 0.9),
      mk('id2', '冰箱', '厨房'),
    ];
    final text = LibModelsCodec.encodeExport(models);
    final j = jsonDecode(text) as Map<String, dynamic>;
    expect(j['app'], 'jiajia');
    expect(j['type'], 'modelLib');
    expect(j['version'], 1);
    expect(j['exportedAt'], isA<String>());
    expect((j['models'] as List).length, 2);

    final payload = LibModelsCodec.decodeImport(text);
    expect(payload.models.length, 2);
    expect(payload.invalid, 0);
    expect(payload.models.first.objText, objQuad);

    // type 不对 → 明确拒绝
    expect(
      () => LibModelsCodec.decodeImport('{"type":"plan","models":[]}'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('modelLib'),
        ),
      ),
    );
    // models 缺失 → 拒绝
    expect(
      () => LibModelsCodec.decodeImport('{"type":"modelLib"}'),
      throwsA(isA<FormatException>()),
    );

    // 逐条 schema：缺 objText 的条跳过并计数；尺寸缺失 → bbox 兜底（三角 1×1×0 → d 0.6）
    const partial = '''
{"app":"jiajia","type":"modelLib","version":1,"models":[
  {"id":"a1","name":"三角","cat":"其他","objText":"v 0 0 0\\nv 1 0 0\\nv 0 1 0\\nf 1 2 3\\n"},
  {"id":"a2","name":"坏的","cat":"其他"}
]}
''';
    final p2 = LibModelsCodec.decodeImport(partial);
    expect(p2.models.length, 1);
    expect(p2.invalid, 1);
    final m = p2.models.single;
    expect(m.wM, closeTo(1.0, 1e-9));
    expect(m.hM, closeTo(1.0, 1e-9));
    expect(m.dM, closeTo(0.6, 1e-9)); // 0 跨度 → 默认深
  });

  test('payloadForPlan：只含本户型引用的库模型（去重）+ 契约形状', () async {
    final docs = await tmp();
    final store = LibModelsStore(root: docs);
    await store.save([
      mk('libA', '椅子', '卧室', obj: objQuad, w: 2, d: 1, h: 0.9),
      mk('libB', '冰箱', '厨房'),
      mk('libC', '没用到的', '其他'),
    ]);

    final plan = FloorPlan()..name = 'p';
    plan.items['i1'] = FurnitureItem(
      id: 'i1',
      kind: FurnitureKind.lib,
      pos: const Vec2(1, 1),
      lib: 'libA',
      sizeW: 2,
      sizeD: 1,
      sizeH: 0.9,
    );
    plan.items['i2'] = FurnitureItem(
      id: 'i2',
      kind: FurnitureKind.lib,
      pos: const Vec2(2, 1),
      lib: 'libA', // 重复引用 → 只下发一条
    );
    plan.items['i3'] = FurnitureItem(
      id: 'i3',
      kind: FurnitureKind.lib,
      pos: const Vec2(3, 1),
      lib: 'libB',
    );
    plan.items['i4'] = FurnitureItem(
      id: 'i4',
      kind: FurnitureKind.sofa,
      pos: const Vec2(4, 1),
    );

    final payload = await LibModelsStore.payloadForPlan(plan, store: store);
    expect(payload.length, 2);
    expect(payload.map((e) => e['id']), containsAll(['libA', 'libB']));
    expect(payload.any((e) => e['id'] == 'libC'), false);
    for (final e in payload) {
      expect(
        e.keys.toSet(),
        containsAll(<String>['id', 'n', 'obj', 'w', 'd', 'h', 'c']),
      );
      expect(e['obj'], isA<String>());
      expect(e['w'], isA<num>());
      expect(e['c'], isA<int>());
    }

    // 没有 lib 物品 → 空数组（不读库）
    final plain = FloorPlan()
      ..items['x'] = FurnitureItem(
        id: 'x',
        kind: FurnitureKind.bed,
        pos: const Vec2(0, 0),
      );
    expect(await LibModelsStore.payloadForPlan(plain, store: store), isEmpty);
  });

  test('FurnitureItem lib 字段：JSON 写入/读回/旧数据宽容', () {
    final plan = FloorPlan()..name = 'p';
    plan.items['i1'] = FurnitureItem(
      id: 'i1',
      kind: FurnitureKind.lib,
      pos: const Vec2(1.5, 2.5),
      rotationDeg: 90,
      lib: 'abc123',
      sizeW: 1.1,
      sizeD: 0.7,
      sizeH: 0.8,
    );
    final j = jsonDecode(plan.toJsonString()) as Map<String, dynamic>;
    final item = (j['items'] as List).single as Map<String, dynamic>;
    expect(item['lib'], 'abc123');

    final back = FloorPlan.fromJsonString(plan.toJsonString());
    final it = back.items['i1']!;
    expect(it.kind, FurnitureKind.lib);
    expect(it.lib, 'abc123');
    expect(it.sizeW, closeTo(1.1, 1e-9));
    expect(it.rotationDeg, 90);

    // 旧数据无 lib 键 → null，且 toJson 不写空键
    const old =
        '{"name":"old","walls":[],"openings":[],'
        '"items":[{"id":"i1","kind":"sofa","x":1,"y":2,"rot":0}]}';
    final oldPlan = FloorPlan.fromJsonString(old);
    expect(oldPlan.items['i1']!.lib, isNull);
    final oldItem =
        (jsonDecode(oldPlan.toJsonString())['items'] as List).single
            as Map<String, dynamic>;
    expect(oldItem.containsKey('lib'), false);
  });
}
