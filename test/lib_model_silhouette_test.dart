// P2：用户素材 2D 轮廓的落库 / 搬运 / 渲染回落。
//
// 覆盖链路（都是真实代码路径，不 mock 几何）：
//   · .obj 导入后的条目带合法 sil（导入即算，随 lib_models.json 落盘）
//   · 旧 JSON 没带 sil → 导入闸口（LibModelsStore.merge）用 objText 现算补上
//   · 带 sil 的 JSON → 原样保留（不重算覆盖）
//   · 导出（全量/单件）→ 带 sil（旧条目导出时现算）；导出→导入 round-trip 保 sil
//   · 长按单件导出内置件：先查 P1 生成表（silhouetteFor），查不到再用 Dart 算法现算
//   · 2D 渲染源：lib 物品查库条目 sil；拿不到条目 → null（画布回落 RRect，不崩）
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_asset_text.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/domain/model_leaves.dart';
import 'package:jiajia/features/floorplan/domain/model_silhouettes.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';
import 'package:jiajia/features/floorplan/state/model_transfer.dart';
import 'package:jiajia/features/floorplan/state/model_transfer_io.dart';

/// 1.2 × 0.7 × 0.75 米的盒子（真三维，俯视是矩形）。
String _boxObj([double w = 1.2, double d = 0.7, double h = 0.75]) {
  final v = [
    [0.0, 0.0, 0.0], [w, 0.0, 0.0], [w, 0.0, d], [0.0, 0.0, d],
    [0.0, h, 0.0], [w, h, 0.0], [w, h, d], [0.0, h, d],
  ];
  final faces = [
    [1, 4, 3, 2], [5, 6, 7, 8],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 4, 8, 7], [4, 1, 5, 8],
  ];
  final b = StringBuffer();
  for (final p in v) {
    b.writeln('v ${p[0]} ${p[1]} ${p[2]}');
  }
  for (final f in faces) {
    b.writeln('f ${f[0]} ${f[1]} ${f[2]}');
    b.writeln('f ${f[0]} ${f[2]} ${f[3]}');
  }
  return b.toString();
}

LibModel _lib(
  String id, {
  String name = '柜子',
  String obj = '',
  ModelSilhouette? sil,
}) =>
    LibModel(
      id: id,
      name: name,
      cat: ModelLeaves.userAssets,
      wM: 1.2,
      dM: 0.7,
      hM: 0.75,
      color: 0xD9B28A,
      objText: obj.isEmpty ? _boxObj() : obj,
      sil: sil,
    );

/// 合法轮廓断言：非空外轮廓、0..1、点成对、≤80 点、线 4 元组。
void _expectValidSil(ModelSilhouette? s, String what) {
  expect(s, isNotNull, reason: '$what 缺 sil');
  expect(s!.outer, isNotEmpty, reason: '$what 外轮廓空');
  for (final loop in s.outer) {
    expect(loop.length % 2, 0, reason: what);
    expect(loop.length ~/ 2, inInclusiveRange(3, 80), reason: what);
    for (final c in loop) {
      expect(c, inInclusiveRange(0, 1), reason: '$what 越界 $c');
    }
  }
  for (final seg in s.lines) {
    expect(seg.length, 4, reason: '$what 线不是 4 元组');
  }
}

void main() {
  Future<Directory> tmp() async {
    final dir = await Directory.systemTemp.createTemp('jj_sil_');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  group('LibModelsStore：入库即算 sil 并落盘', () {
    test('.obj 导入（导入闸后算好）→ 条目 sil 合法，JSON 文件里带 sil', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      // 与编辑器 _runModelImportFlow 同一条写法：闸已过，条目构造时算 sil
      final obj = _boxObj();
      final model = _lib('u_obj_1', sil: ModelSilhouette.tryFromObjText(obj));
      expect(model.sil, isNotNull);

      await store.add(model);
      final back = (await LibModelsStore(root: docs).load()).single;
      _expectValidSil(back.sil, '.obj 导入条目');
      expect(back.sil!.outer.first.length ~/ 2, 4, reason: '盒子俯视是矩形');

      final raw = jsonDecode(
        File('${docs.path}/lib_models.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final entry = (raw['models'] as List).single as Map<String, dynamic>;
      expect(entry.containsKey('sil'), true);
      expect((entry['sil'] as Map)['o'], isA<List>());
    });

    test('没带 sil 的条目进库 → 合并闸口现算（旧数据/老代码路径都能补上）', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final noSil = _lib('u_old_1');
      expect(noSil.sil, isNull);

      await store.add(noSil); // add → merge → withSilhouette
      final back = (await store.load()).single;
      _expectValidSil(back.sil, '补算条目');
    });

    test('JSON 自带 sil → 原样保留，不被重算覆盖', () async {
      const given = {
        'o': [
          [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0],
        ],
        'h': [],
        'l': [
          [0.1, 0.25, 0.9, 0.25],
        ],
      };
      final m = LibModel.fromJson({
        'id': 'u_keep',
        'name': '带轮廓',
        'cat': ModelLeaves.userAssets,
        'objText': _boxObj(),
        'sil': given,
      });
      expect(m, isNotNull);
      expect(m!.sil!.toJson(), equals(given));
      expect(m.sil!.lines.length, 1, reason: '自定义线必须保留');
    });

    test('坏 sil（形状不对）→ 宽容当没有，不抛、不影响其它字段', () async {
      final m = LibModel.fromJson({
        'id': 'u_bad',
        'name': '坏轮廓',
        'objText': _boxObj(),
        'sil': {'o': 'not-a-list'},
      });
      expect(m, isNotNull);
      expect(m!.sil, isNull);
      expect(m.name, '坏轮廓');
    });
  });

  group('JSON 导入（单件 / 全量）', () {
    test('旧全量 JSON（无 sil）→ 导入后算出 sil 并落盘', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final legacy = jsonEncode({
        'app': 'jiajia',
        'type': 'userModels',
        'version': 1,
        'models': [
          {
            'libId': 'u_1700000000001_chair',
            'name': '椅子',
            'cat': ModelLeaves.userAssets,
            'wmm': 1200,
            'dmm': 700,
            'hmm': 750,
            'color': 0xD9B28A,
            'objText': _boxObj(),
          },
        ],
      });
      final payload = UserModelImportCodec.decode(legacy);
      expect(payload.models.single.sil, isNull, reason: '文件本来没有 sil');

      await UserModelMerger.merge(store, payload.models);
      final back = (await LibModelsStore(root: docs).load()).single;
      _expectValidSil(back.sil, '旧全量 JSON 导入');

      // 落盘也带上（下次 load 不再算）
      final raw = jsonDecode(
        File('${docs.path}/lib_models.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(((raw['models'] as List).single as Map).containsKey('sil'), true);
    });

    test('旧单件 JSON（无 sil）→ 导入入库后算出 sil', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final single = jsonEncode({
        'id': 'u_1700000000002_desk',
        'name': '小桌',
        'cat': ModelLeaves.userAssets,
        'wmm': 1200,
        'dmm': 700,
        'hmm': 750,
        'color': 0xD9B28A,
        'objText': _boxObj(),
      });
      final item = ModelTransferCodec.decodeSingle(single);
      expect(item.sil, isNull);
      final r = await SingleModelImporter.add(store, item);
      expect(r.status, SingleImportStatus.added);
      _expectValidSil(r.model!.sil, '旧单件 JSON 导入');
      _expectValidSil((await store.load()).single.sil, '旧单件 JSON 落盘');
    });

    test('带 sil 的全量 JSON → 导入后原样保留', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final sil = ModelSilhouette.fromObjText(_boxObj()).toJson();
      final text = jsonEncode({
        'app': 'jiajia',
        'type': 'userModels',
        'version': 1,
        'models': [
          {
            'libId': 'u_withsil',
            'name': '带轮廓件',
            'cat': ModelLeaves.userAssets,
            'wmm': 1200,
            'dmm': 700,
            'hmm': 750,
            'objText': _boxObj(),
            'sil': sil,
          },
        ],
      });
      await UserModelMerger.merge(store, UserModelImportCodec.decode(text).models);
      final back = (await store.load()).single;
      expect(back.sil!.toJson(), equals(sil));
    });
  });

  group('导出：带上 sil，round-trip 不丢', () {
    test('全量导出：旧条目（无 sil）导出时现算；导出→导入保 sil', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      await store.save([_lib('u_rt', name: '柜子')]); // 直接 save：故意不带 sil

      final load1 = await store.load();
      expect(load1.single.sil, isNull, reason: 'save 不补算（保护导入性能）');

      final json = UserModelExportCodec.encodeAll(load1);
      final j = jsonDecode(json) as Map<String, dynamic>;
      final entry = (j['models'] as List).single as Map<String, dynamic>;
      expect(entry.containsKey('sil'), true, reason: '导出时必须带 sil');

      // 导入到另一个库 → sil 逐值一致
      final docs2 = await tmp();
      final store2 = LibModelsStore(root: docs2);
      await UserModelMerger.merge(
        store2,
        UserModelImportCodec.decode(json).models,
      );
      final back = (await store2.load()).single;
      expect(back.sil!.toJson(), equals(entry['sil']));
      _expectValidSil(back.sil, 'round-trip');
    });

    test('旧信封（jiajia_models.json / modelLib）导出也带 sil', () async {
      final text = LibModelsCodec.encodeExport([_lib('u_env')]);
      final j = jsonDecode(text) as Map<String, dynamic>;
      final entry = (j['models'] as List).single as Map<String, dynamic>;
      expect(entry.containsKey('sil'), true);
      final payload = LibModelsCodec.decodeImport(text);
      _expectValidSil(payload.models.single.sil, 'modelLib 信封');
    });
  });

  group('长按单件导出（model_transfer）', () {
    test('内置件：优先查 P1 生成表（m_furn_desk），JSON 带 sil', () async {
      final jsTexts = [
        File('assets/web/models.js').readAsStringSync(),
        File('assets/web/models_ext.js').readAsStringSync(),
      ];
      await ModelAssetLibrary.loadFromTexts(jsTexts);
      final spec = ModelItems.byId('m_furn_desk')!;
      final item = await ModelExport.forSpec(
        spec,
        cat: ModelLeaves.furniture,
        subCat: '书房',
      );
      // 查表结果与 silhouetteFor 完全一致（同一条生成数据，不现算）
      expect(item.sil, isNotNull);
      expect(item.sil!.toJson(), equals(silhouetteFor('m_furn_desk')!.toJson()));

      final j = jsonDecode(item.encodeSingle()) as Map<String, dynamic>;
      expect(j.containsKey('sil'), true);
      expect((j['sil'] as Map)['o'], isA<List>());
    });

    test('查不到表的件（占位盒）→ Dart 算法现算 sil', () {
      final spec = ModelItems.all.firstWhere(
        (m) => m.modelId == null && m.place == ModelPlace.floor,
      );
      final item = ModelTransferItem.fromSpec(
        spec,
        cat: ModelLeaves.furniture,
      );
      _expectValidSil(item.sil, '占位盒单件导出');
      expect(item.sil!.outer.first.length ~/ 2, 4, reason: '占位盒俯视是矩形');
      final j = jsonDecode(item.encodeSingle()) as Map<String, dynamic>;
      expect(j.containsKey('sil'), true);
    });

    test('用户素材单件导出：条目没 sil 也要现算带上；入库后保留', () async {
      final item = ModelTransferItem.fromLibModel(_lib('u_user_1'));
      _expectValidSil(item.sil, '用户素材单件导出');
      final j = jsonDecode(item.encodeSingle()) as Map<String, dynamic>;
      expect(j.containsKey('sil'), true);

      // 导入端（JSON）宽容：有 sil 就存
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final decoded = ModelTransferCodec.decodeSingle(item.encodeSingle());
      await SingleModelImporter.add(store, decoded);
      final back = (await store.load()).single;
      expect(back.sil!.toJson(), equals(item.sil!.toJson()));
    });
  });

  group('渲染源与回落', () {
    FurnitureItem libItem(String libId) => FurnitureItem(
      id: 'f1',
      kind: FurnitureKind.lib,
      pos: const Vec2(1, 1),
      lib: libId,
    );

    test('lib 物品 → 查库条目 sil；条目缺失/无 sil → null（回落 RRect）', () {
      final withSil = _lib('u_a', sil: ModelSilhouette.fromObjText(_boxObj()));
      final noSil = _lib('u_b');
      final libs = {'u_a': withSil, 'u_b': noSil};

      expect(planItemSilhouette(libItem('u_a'), libs), isNotNull);
      expect(planItemSilhouette(libItem('u_b'), libs), isNull);
      expect(planItemSilhouette(libItem('u_missing'), libs), isNull);
      expect(planItemSilhouette(libItem('u_a'), const {}), isNull);
    });

    test('内置 modelId 优先走 P1 表（与库条目无关）', () {
      final item = FurnitureItem(
        id: 'f2',
        kind: FurnitureKind.asset,
        pos: const Vec2(1, 1),
        modelId: 'm_furn_desk',
        lib: 'u_a',
      );
      final s = planItemSilhouette(item, const {});
      expect(s, isNotNull);
      expect(s!.toJson(), equals(silhouetteFor('m_furn_desk')!.toJson()));
    });

    Future<ProviderContainer> pumpEditor(
      WidgetTester tester,
      LibModelsStore store,
    ) async {
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
          child: MaterialApp(home: FloorplanEditorPage(libStore: store)),
        ),
      );
      await tester.pump();
      container.read(editorDocProvider.notifier).mutate((p) {
        p.items['f1'] = libItem('u_missing');
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return container;
    }

    testWidgets('lib 物品无库条目 → 画布不崩（回落 RRect）', (tester) async {
      // widget 测试里不要碰真文件 IO（fake async 下 Future 不落地）→ 内存 store
      await pumpEditor(tester, _MemStore(const <LibModel>[]));
      expect(find.byKey(const ValueKey('cv')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lib 物品有条目带 sil → 同样不崩（走轮廓分支）', (tester) async {
      final store = _MemStore([
        _lib('u_missing', sil: ModelSilhouette.fromObjText(_boxObj())),
      ]);
      await pumpEditor(tester, store);
      expect(find.byKey(const ValueKey('cv')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 内存库（widget 测试用；真文件 IO 在 fake async 里不落地）。
class _MemStore extends LibModelsStore {
  List<LibModel> models;

  _MemStore(List<LibModel> seed) : models = List.of(seed);

  @override
  Future<List<LibModel>> load() async => List.of(models);

  @override
  Future<void> save(List<LibModel> m) async {
    models = List.of(m);
  }
}
