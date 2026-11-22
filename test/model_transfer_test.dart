import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/model_asset_text.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/domain/model_leaves.dart';
import 'package:jiajia/features/floorplan/domain/obj_parse.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';
import 'package:jiajia/features/floorplan/state/model_transfer.dart';
import 'package:jiajia/features/floorplan/state/model_transfer_io.dart';

/// v0.1.38：模型导入导出体系（单件 JSON / 用户模型全量 JSON / 闸 / 无分类）。
void main() {
  const objTri = 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n';
  const objQuad = 'v 0 0 0\nv 2 0 0\nv 2 0 1\nv 0 0 1\nf 1 2 3\nf 1 3 4\n';

  LibModel mk(
    String id,
    String name,
    String cat, {
    String? subCat,
    String obj = objTri,
    double w = 1.0,
    double d = 0.6,
    double h = 1.0,
    int color = 0xD9B28A,
  }) {
    return LibModel(
      id: id,
      name: name,
      cat: cat,
      subCat: subCat,
      wM: w,
      dM: d,
      hM: h,
      color: color,
      objText: obj,
    );
  }

  Future<Directory> tmp() async {
    final dir = await Directory.systemTemp.createTemp('jj_model_transfer_');
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  group('叶子分类 / 无分类语义', () {
    test('已知叶子分类 vs 旧分类（卧室）→ 用户素材', () {
      expect(ModelLeaves.all, [
        '门',
        '窗',
        '梁柱',
        '楼梯',
        '特殊墙窗',
        '家具',
        '庭院',
        '用户素材',
      ]);
      for (final c in ModelLeaves.all) {
        expect(ModelLeaves.contains(c), true, reason: c);
      }
      expect(ModelLeaves.isUserAsset('家具'), false);
      expect(ModelLeaves.isUserAsset('门'), false);
      expect(ModelLeaves.isUserAsset('用户素材'), true);
      expect(ModelLeaves.isUserAsset('卧室'), true); // v0.1.37 旧分类
      expect(ModelLeaves.isUserAsset('厨房'), true);
      expect(ModelLeaves.isUserAsset(''), true);
      expect(ModelLeaves.isUserAsset(null), true);
      // 散列默认色稳定且落在调色板内
      expect(ModelLeaves.defaultColor('u_1'), ModelLeaves.defaultColor('u_1'));
      expect(ModelLeaves.palette.contains(ModelLeaves.defaultColor('x')), true);
    });

    test('旧条目 cat 原样保留（不再被改写「其他」），并进用户素材', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      await store.save([
        mk('old1', '旧书架', '卧室', subCat: null),
        mk('new1', '新书桌', '家具', subCat: '书房'),
      ]);
      final back = await store.load();
      expect(back.firstWhere((m) => m.id == 'old1').cat, '卧室');
      final assets = LibModelsStore.userAssetsOf(back);
      expect(assets.map((m) => m.id), ['old1']);
    });

    test('JSON 缺 cat → 空串（无分类），color 缺失 → 散列默认色', () async {
      final m = LibModel.fromJson(const {
        'id': 'u_1',
        'name': '无分类',
        'objText': objTri,
      });
      expect(m, isNotNull);
      expect(m!.cat, '');
      expect(ModelLeaves.isUserAsset(m.cat), true);
      expect(m.color, ModelLeaves.defaultColor('u_1'));
      expect(m.subCat, isNull);
    });
  });

  group('单件模型 JSON', () {
    test('系统模型导出：OBJ 与 assets 逐字节等 + 尺寸≈spec', () async {
      final jsTexts = [
        File('assets/web/models.js').readAsStringSync(),
        File('assets/web/models_ext.js').readAsStringSync(),
      ];
      await ModelAssetLibrary.loadFromTexts(jsTexts);
      final spec = ModelItems.byId('m_furn_desk')!;
      final asset = ModelAssetLibrary.byId(spec.modelId);
      expect(asset, isNotNull);
      expect(asset!.objText.length > 1000, true);

      final item = await ModelExport.forSpec(
        spec,
        cat: ModelLeaves.furniture,
        subCat: '书房',
      );
      // 逐字节等价（Dart 读出的 o 字段就是 JS parseOBJ 吃的那份）
      expect(item.objText, asset.objText);
      expect(item.id, 'm_furn_desk');
      expect(item.name, '书桌');
      expect(item.cat, '家具');
      expect(item.subCat, '书房');
      expect(item.wmm, spec.specWmm);
      expect(item.dmm, spec.specDmm);
      expect(item.hmm, spec.specHmm);
      // 单件文件只有 9 个约定键（subCat 非空时）
      final j = jsonDecode(item.encodeSingle()) as Map<String, dynamic>;
      expect(
        j.keys.toSet(),
        containsAll(<String>[
          'id',
          'name',
          'cat',
          'subCat',
          'wmm',
          'dmm',
          'hmm',
          'color',
          'objText',
        ]),
      );
      expect(j['objText'], asset.objText);
    });

    test('导出 → 导入新 store：id 保留、顶点/面 >10、尺寸≈spec', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      await ModelAssetLibrary.loadFromTexts([
        File('assets/web/models.js').readAsStringSync(),
        File('assets/web/models_ext.js').readAsStringSync(),
      ]);
      final spec = ModelItems.byId('m_furn_desk')!;
      final item = await ModelExport.forSpec(
        spec,
        cat: ModelLeaves.furniture,
        subCat: '书房',
      );
      final decoded = ModelTransferCodec.decodeSingle(item.encodeSingle());
      final r = await SingleModelImporter.add(
        store,
        decoded.retarget(cat: '家具', subCat: '书房'),
      );
      expect(r.status, SingleImportStatus.added);
      final saved = (await LibModelsStore(root: docs).load()).single;
      expect(saved.id, 'm_furn_desk');
      expect(saved.cat, '家具');
      expect(saved.subCat, '书房');
      expect(saved.color, item.color);
      // JS 渲染同一条 OBJ 管线（viewer.js parseOBJ）：顶点/面数必须够画
      final data = ObjParser.parse(saved.objText);
      expect(data.vertexCount, greaterThan(10));
      expect(data.faceCount, greaterThan(10));
      expect(data.bboxW, closeTo(spec.specWmm! / 1000, 0.02));
      expect(data.bboxD, closeTo(spec.specDmm! / 1000, 0.02));
      expect(data.bboxH, closeTo(spec.specHmm! / 1000, 0.02));
      expect(saved.wM, closeTo(spec.specWmm! / 1000, 0.001));
      // 同 id 再导 → 跳过
      final dup = await SingleModelImporter.add(
        store,
        decoded.retarget(cat: '家具', subCat: '书房'),
      );
      expect(dup.status, SingleImportStatus.duplicate);
      expect((await store.load()).length, 1);
    });

    test('程序化件（无 OBJ）→ 占位盒，仍能过闸并渲染', () async {
      final spec = ModelItems.byId('fangzhu')!; // 方柱：无 modelId
      final item = await ModelExport.forSpec(
        spec,
        cat: ModelLeaves.columnBeam,
      );
      expect(item.objText.contains('placeholder box'), true);
      final data = ObjParser.parse(item.objText);
      expect(data.faceCount, 12);
      expect(data.vertexCount, 8);
      expect(item.wmm, 400);
      expect(item.hmm, 2800);
      expect(item.cat, '梁柱');
      expect(item.subCat, isNull);
    });

    test('全量文件误投单件导入 → 明确提示走全量导入', () {
      final text = UserModelExportCodec.encodeAll([mk('u_1', '椅子', '家具')]);
      expect(
        () => ModelTransferCodec.decodeSingle(text),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('全量导入'),
          ),
        ),
      );
    });
  });

  group('用户模型全量导出/导入', () {
    test('round-trip：id/cat/subCat/尺寸/颜色/obj 全等；重复导入跳过计数', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final original = [
        mk(
          'u_1700000000001_chair',
          '椅子',
          '家具',
          subCat: '书房',
          obj: objQuad,
          w: 1.234,
          d: 0.567,
          h: 0.89,
          color: 0xD9B28A,
        ),
        mk(
          'u_1700000000002_pot',
          '花盆',
          '庭院',
          obj: objTri,
          w: 0.4,
          d: 0.4,
          h: 0.6,
          color: 0x9FD3A8,
        ),
        mk('u_1700000000003_old', '老件', '卧室', color: 0xC7A88F),
      ];
      await store.save(original);

      final json = UserModelExportCodec.encodeAll(await store.load());
      final envelope = jsonDecode(json) as Map<String, dynamic>;
      expect(envelope['app'], 'jiajia');
      expect(envelope['type'], 'userModels');
      expect(envelope['version'], 1);
      expect((envelope['models'] as List).length, 3);
      final first = (envelope['models'] as List).first as Map<String, dynamic>;
      expect(first['libId'], 'u_1700000000001_chair');
      expect(first['cat'], '家具');
      expect(first['subCat'], '书房');
      expect(first['wmm'], 1234);
      expect(first.containsKey('objText'), true);

      // 清空后导入
      await store.save([]);
      final payload = UserModelImportCodec.decode(json);
      expect(payload.invalid, 0);
      final r = await UserModelMerger.merge(store, payload.models);
      expect(r.added, 3);
      expect(r.skipped, 0);

      final back = await store.load();
      expect(back.length, 3);
      for (final o in original) {
        final b = back.firstWhere((m) => m.id == o.id);
        expect(b.name, o.name);
        expect(b.cat, o.cat);
        expect(b.subCat, o.subCat);
        expect(b.wM, closeTo(o.wM, 1e-9));
        expect(b.dM, closeTo(o.dM, 1e-9));
        expect(b.hM, closeTo(o.hM, 1e-9));
        expect(b.color, o.color);
        expect(b.objText, o.objText);
      }

      // 重复导入同一份 → 全跳过
      final r2 = await UserModelMerger.merge(store, payload.models);
      expect(r2.added, 0);
      expect(r2.skipped, 3);
      expect((await store.load()).length, 3);
    });

    test('解析宽容：缺 libId/objText 的条目跳过并计数，其余照常入库', () {
      final text = jsonEncode({
        'app': 'jiajia',
        'type': 'userModels',
        'version': 1,
        'models': [
          {'libId': 'ok1', 'name': '好件', 'cat': '门', 'objText': objTri},
          {'name': '缺 libId', 'cat': '门', 'objText': objTri},
          {'libId': 'bad', 'name': '缺 obj', 'cat': '门'},
          {'libId': 'ok2', 'objText': objTri}, // 缺 name → 用 libId
          'not-a-map',
        ],
      });
      final p = UserModelImportCodec.decode(text);
      expect(p.models.map((m) => m.id), ['ok1', 'ok2']);
      expect(p.models.last.name, 'ok2');
      expect(p.invalid, 3);
    });

    test('type 不对 → FormatException', () {
      expect(
        () => UserModelImportCodec.decode(
          jsonEncode({'type': 'modelLib', 'models': []}),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('几何闸（5000 面 / 300KB，不放宽）', () {
    String bigObj(int faces) {
      final b = StringBuffer('v 0 0 0\nv 1 0 0\nv 0 1 0\n');
      for (var i = 0; i < faces; i++) {
        b.writeln('f 1 2 3');
      }
      return b.toString();
    }

    test('>5000 面 OBJ 拒绝：整条不入库、不写 cat', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final bad = mk('u_big', '超大件', '家具', obj: bigObj(5001));
      final ok = mk('u_ok', '正常件', '家具', subCat: '卧室');
      final r = await UserModelMerger.merge(store, [bad, ok]);
      expect(r.added, 1);
      expect(r.invalid, 1);
      expect(r.skipped, 1);
      final back = await store.load();
      expect(back.map((m) => m.id), ['u_ok']);
      expect(back.any((m) => m.id == 'u_big'), false);
      // cat 字段断言：只有合格条目落盘，且分类保留
      expect(back.single.cat, '家具');
      expect(back.single.subCat, '卧室');
    });

    test('300KB 上限不放宽（300001 字符直接拒）', () {
      final big = 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n'
          '${'#' * (ObjParser.maxChars)}';
      expect(big.length > ObjParser.maxChars, true);
      expect(
        () => ObjParserGate.check(big),
        throwsA(
          isA<ObjParseException>().having(
            (e) => e.message,
            'message',
            contains('过大'),
          ),
        ),
      );
    });

    test('单件导入同样走闸：超大模型 rejected，store 不变', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      final item = ModelTransferItem(
        id: 'u_huge',
        name: '超大',
        cat: '家具',
        subCat: '卧室',
        wmm: 1000,
        dmm: 1000,
        hmm: 1000,
        color: 0x8FB7D6,
        objText: bigObj(5001),
      );
      final r = await SingleModelImporter.add(store, item);
      expect(r.status, SingleImportStatus.rejected);
      expect(r.message, contains('面数超限'));
      expect(await store.load(), isEmpty);
    });
  });

  group('id / 颜色 / 3D 载荷', () {
    test('.obj 新 id = u_<时间戳>_<slug>', () {
      final id = LibModel.newImportId('My Table 01.obj', nowMs: 1700000000000);
      expect(id.startsWith('u_1700000000000'), true);
      expect(id.contains(' '), false);
      expect(id.contains('.'), false);
      // 纯中文文件名 → 只剩时间戳（不产出空 slug 尾巴）
      final cn = LibModel.newImportId('桌子', nowMs: 123);
      expect(cn, 'u_123');
    });

    test('payloadForPlan 用条目自身颜色（不再是轮转调色板）', () async {
      final docs = await tmp();
      final store = LibModelsStore(root: docs);
      await store.save([mk('libA', '椅子', '家具', color: 0xFF00A88F)]);
      final plan = FloorPlan()..name = 'p';
      plan.items['i1'] = FurnitureItem(
        id: 'i1',
        kind: FurnitureKind.lib,
        pos: const Vec2(1, 1),
        lib: 'libA',
      );
      final payload = await LibModelsStore.payloadForPlan(plan, store: store);
      expect(payload.single['c'], 0xFF00A88F);
    });
  });
}
