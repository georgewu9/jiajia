// v0.1.38 模型导入导出体系：单件模型 JSON + 用户模型全量 JSON。
//
// 与旧 LibModelsCodec（jiajia_models.json，type=modelLib）的关系：
//   · 旧信封仍保留（家具 sheet 的「导出/导入模型库」按钮没动，兼容旧文件）；
//   · 新单件格式带 cat/subCat/颜色/mm 尺寸，用于「长按 tile 导出」；
//   · 新全量格式 type=userModels，只含用户模型，条目主键叫 libId。
//
// 所有解析都宽容：缺字段的条目跳过并计数，不让一条脏数据毁掉整包。
// 几何闸（5000 面/300KB）不在这里判——由 UserModelMerger 在入库前走 ObjParser。
import 'dart:convert';

import '../domain/floor_plan.dart' show FurnitureCatalog;
import '../domain/model_asset_text.dart';
import '../domain/model_items.dart';
import '../domain/model_leaves.dart';
import '../domain/model_silhouettes.dart';
import '../domain/obj_parse.dart';
import 'lib_models_store.dart';

/// 一件可搬运的模型（单件导出 / 全量导出的公共形状，mm 尺寸）。
class ModelTransferItem {
  final String id;
  final String name;
  final String cat;
  final String? subCat;
  final int wmm;
  final int dmm;
  final int hmm;
  final int color;
  final String objText;

  /// 2D 俯视轮廓（P2）：单件 JSON 的 `sil` 字段；导入时原样入库，
  /// 缺省 → 入库/导出链路用 OBJ 现算（见 [LibModel.withSilhouette]）。
  final ModelSilhouette? sil;

  const ModelTransferItem({
    required this.id,
    required this.name,
    required this.cat,
    this.subCat,
    required this.wmm,
    required this.dmm,
    required this.hmm,
    required this.color,
    required this.objText,
    this.sil,
  });

  LibModel toLibModel() => LibModel(
    id: id,
    name: name,
    cat: cat,
    subCat: subCat,
    wM: wmm / 1000,
    dM: dmm / 1000,
    hM: hmm / 1000,
    color: color,
    objText: objText,
    sil: sil,
  );

  /// 导入到某个叶子菜单时，归属以菜单为准（cat/subCat 覆盖文件里的值）。
  ModelTransferItem retarget({required String cat, String? subCat}) =>
      ModelTransferItem(
        id: id,
        name: name,
        cat: cat,
        subCat: subCat,
        wmm: wmm,
        dmm: dmm,
        hmm: hmm,
        color: color,
        objText: objText,
        sil: sil,
      );

  /// 用户库条目 → 可搬运条目：带 sil（条目没算过就现算，导出文件总能带上）。
  static ModelTransferItem fromLibModel(LibModel m) => ModelTransferItem(
    id: m.id,
    name: m.name,
    cat: m.cat,
    subCat: m.subCat,
    wmm: (m.wM * 1000).round(),
    dmm: (m.dM * 1000).round(),
    hmm: (m.hM * 1000).round(),
    color: m.color,
    objText: m.objText,
    sil: m.sil ?? ModelSilhouette.tryFromObjText(m.objText),
  );

  /// 系统 ModelSpec → 可搬运条目。
  /// [asset] 为 models.js/models_ext.js 里按 modelId 查到的真几何；查不到
  /// （柱/楼梯等程序化件）→ 按规格尺寸生成占位盒 OBJ，仍可导入/渲染。
  static ModelTransferItem fromSpec(
    ModelSpec m, {
    required String cat,
    String? subCat,
    AssetModel? asset,
  }) {
    final (w, d, h) = dimsOfSpec(m);
    final obj = asset?.objText ??
        placeholderBox(wmm: w, dmm: d, hmm: h, name: m.label);
    return ModelTransferItem(
      id: m.modelId ?? m.id,
      name: m.label,
      cat: cat,
      subCat: subCat,
      wmm: w,
      dmm: d,
      hmm: h,
      color: asset?.color ?? colorOfSpec(m),
      objText: obj,
      // 优先查 P1 生成表（内置件与生成器逐点一致）；表里没有（程序化件/
      // 占位盒）再用 Dart 算法对同一份 OBJ 现算。
      sil: silhouetteFor(m.modelId) ?? ModelSilhouette.tryFromObjText(obj),
    );
  }

  /// 单件文件格式（扁平 10 键，直接给用户看/手改）：
  /// `{id,name,cat,subCat,wmm,dmm,hmm,color,objText,sil}`；subCat 可空时省略、
  /// sil 算不出时省略（导入端会再算）。
  Map<String, dynamic> toSingleJson() => {
    'id': id,
    'name': name,
    'cat': cat,
    if (subCat != null && subCat!.isNotEmpty) 'subCat': subCat,
    'wmm': wmm,
    'dmm': dmm,
    'hmm': hmm,
    'color': color,
    'objText': objText,
    if (sil != null) 'sil': sil!.toJson(),
  };

  String encodeSingle() => jsonEncode(toSingleJson());

  /// 宽容解析单件：id/objText 必有；name 缺 → id；cat 缺 → 用户素材；
  /// 尺寸支持 wmm/… 或旧式 wM/…（米）；尺寸缺失 → 0（入库时由 LibModel 走 bbox）。
  static ModelTransferItem? fromJsonMap(Map<String, dynamic> j) {
    final id = j['id'];
    final obj = j['objText'];
    if (id is! String || id.trim().isEmpty) return null;
    if (obj is! String || obj.trim().isEmpty) return null;
    final nameRaw = j['name'];
    final name = (nameRaw is String && nameRaw.trim().isNotEmpty)
        ? nameRaw.trim()
        : id.trim();
    final catRaw = j['cat'];
    final cat = (catRaw is String && catRaw.trim().isNotEmpty)
        ? catRaw.trim()
        : ModelLeaves.userAssets;
    final subRaw = j['subCat'];
    final subCat =
        (subRaw is String && subRaw.trim().isNotEmpty) ? subRaw.trim() : null;

    int mm(Object? raw, Object? meters) {
      if (raw is num && raw.isFinite && raw > 0) return raw.round();
      if (meters is num && meters.isFinite && meters > 0) {
        return (meters * 1000).round();
      }
      return 0;
    }

    final colorRaw = j['color'];
    final color = (colorRaw is num && colorRaw.toInt() > 0)
        ? colorRaw.toInt()
        : ModelLeaves.defaultColor(id.trim());

    // sil：宽容解析（有则原样保留，坏形状当没有；入库时 merge 会补算）。
    ModelSilhouette? sil;
    final silRaw = j['sil'];
    if (silRaw is Map) {
      try {
        sil = ModelSilhouette.fromJson(Map<String, dynamic>.from(silRaw));
      } catch (_) {
        sil = null;
      }
    }

    return ModelTransferItem(
      id: id.trim(),
      name: name,
      cat: cat,
      subCat: subCat,
      wmm: mm(j['wmm'], j['wM']),
      dmm: mm(j['dmm'], j['dM']),
      hmm: mm(j['hmm'], j['hM']),
      color: color,
      objText: obj,
      sil: sil,
    );
  }

  /// 全量文件里的一条：主键 libId（兼容 id）。
  static ModelTransferItem? fromAllEntry(Map<String, dynamic> j) {
    final libId = j['libId'] ?? j['id'];
    if (libId is! String || libId.trim().isEmpty) return null;
    final merged = <String, dynamic>{...j, 'id': libId};
    return fromJsonMap(merged);
  }

  /// 系统 ModelSpec 的尺寸（mm）：门窗 = 宽×150×高；floor = 显式规格 >
  /// 家具目录 > 600 占位。
  static (int, int, int) dimsOfSpec(ModelSpec m) {
    if (m.place == ModelPlace.wall) {
      return (m.defaultWmm, 150, m.heightMm);
    }
    final w = m.specWmm, d = m.specDmm, h = m.specHmm;
    if (w != null && d != null && h != null) return (w, d, h);
    final k = m.floorKind;
    final s = k == null ? null : FurnitureCatalog.spec[k];
    if (s != null) {
      return ((s.$1 * 1000).round(), (s.$2 * 1000).round(), (s.$3 * 1000).round());
    }
    return (600, 600, 600);
  }

  /// 系统 ModelSpec 的颜色：模型包 c > 家具目录占位色 > 灰。
  static int colorOfSpec(ModelSpec m) {
    final k = m.floorKind;
    final s = k == null ? null : FurnitureCatalog.spec[k];
    return s?.$4 ?? 0x8B93A5;
  }

  /// 12 面长方体占位 OBJ（米制坐标，xyz 与 bbox 语义一致）。
  static String placeholderBox({
    required int wmm,
    required int dmm,
    required int hmm,
    String name = 'placeholder',
  }) {
    String f(double v) {
      final s = v.toStringAsFixed(4);
      return s.endsWith('.0000') ? s.substring(0, s.length - 5) : s;
    }

    final x = f(wmm / 1000);
    final z = f(dmm / 1000);
    final y = f(hmm / 1000);
    final safeName = name.replaceAll(RegExp(r'\s+'), '_');
    return '# jiajia placeholder box ${wmm}x${dmm}x${hmm}mm\n'
        'o $safeName\n'
        'v 0 0 0\nv $x 0 0\nv $x 0 $z\nv 0 0 $z\n'
        'v 0 $y 0\nv $x $y 0\nv $x $y $z\nv 0 $y $z\n'
        'f 1 2 3\nf 1 3 4\nf 5 6 7\nf 5 7 8\n'
        'f 1 2 6\nf 1 6 5\nf 2 3 7\nf 2 7 6\n'
        'f 3 4 8\nf 3 8 7\nf 4 1 5\nf 4 5 8\n';
  }
}

/// 单件文件解析（顶层必须是一个 JSON 对象）。
class ModelTransferCodec {
  const ModelTransferCodec._();

  static ModelTransferItem decodeSingle(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('不是单模型文件：顶层应为 JSON 对象');
    }
    if (j['models'] is List) {
      throw const FormatException('这是全量模型文件，请用「全量导入」');
    }
    final item = ModelTransferItem.fromJsonMap(j);
    if (item == null) {
      throw const FormatException('单模型文件缺少 id / objText');
    }
    return item;
  }
}

/// 用户模型全量导出信封：`{app, type:'userModels', version:1, exportedAt, models}`。
class UserModelExportCodec {
  const UserModelExportCodec._();

  static const String type = 'userModels';
  static const String fileName = '用户模型_全量.json';

  /// 全量导出：每条带 `sil`（旧条目没算过 → 导出时现算；算不出省略）。
  static String encodeAll(List<LibModel> models) => jsonEncode({
    'app': 'jiajia',
    'type': type,
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'models': [
      for (final m in models.map((x) => x.withSilhouette()))
        {
          'libId': m.id,
          'name': m.name,
          'cat': m.cat,
          if (m.subCat != null && m.subCat!.isNotEmpty) 'subCat': m.subCat,
          'wmm': (m.wM * 1000).round(),
          'dmm': (m.dM * 1000).round(),
          'hmm': (m.hM * 1000).round(),
          'color': m.color,
          'objText': m.objText,
          if (m.sil != null) 'sil': m.sil!.toJson(),
        },
    ],
  });
}

/// 全量文件解析结果：合格条目 + 被跳过的脏条目数。
class UserModelImportPayload {
  final List<LibModel> models;
  final int invalid;

  const UserModelImportPayload({required this.models, required this.invalid});
}

class UserModelImportCodec {
  const UserModelImportCodec._();

  static UserModelImportPayload decode(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('不是用户模型全量文件：顶层应为 JSON 对象');
    }
    if (j['type'] != UserModelExportCodec.type) {
      throw const FormatException('不是用户模型全量文件：type 应为 userModels');
    }
    final raw = j['models'];
    if (raw is! List) {
      throw const FormatException('用户模型全量文件缺少 models 数组');
    }
    final out = <LibModel>[];
    var invalid = 0;
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        invalid++;
        continue;
      }
      final item = ModelTransferItem.fromAllEntry(e);
      if (item == null) {
        invalid++;
        continue;
      }
      out.add(item.toLibModel());
    }
    return UserModelImportPayload(models: out, invalid: invalid);
  }
}

/// 入库结果（供 SnackBar 报「导入 N 件，跳过 M 件」）。
class UserModelMergeResult {
  final List<LibModel> models;
  final int added;

  /// 重复 id + 无效条目（解析失败/缺字段/超闸）。
  final int skipped;
  final int invalid;

  const UserModelMergeResult({
    required this.models,
    required this.added,
    required this.skipped,
    required this.invalid,
  });
}

/// 入库动作：几何闸 + 去重 + 落盘（UI 与单测共用）。
class UserModelMerger {
  const UserModelMerger._();

  /// 批量：逐条走 ObjParser 闸（5000 面/300KB），失败计入 invalid；
  /// id 已存在 → 跳过；同名同分类 → 名字加 (1)（LibModelsStore.merge 规则）。
  static Future<UserModelMergeResult> merge(
    LibModelsStore store,
    List<LibModel> incoming, {
    int invalid = 0,
  }) async {
    final existing = await store.load();
    var bad = invalid;
    final ok = <LibModel>[];
    for (final m in incoming) {
      try {
        ObjParserGate.check(m.objText);
        ok.add(m);
      } catch (_) {
        bad++;
      }
    }
    final r = LibModelsStore.merge(existing, ok);
    await store.save(r.models);
    return UserModelMergeResult(
      models: r.models,
      added: r.added,
      skipped: r.skipped + bad,
      invalid: bad,
    );
  }
}

/// 单件入库结果。
enum SingleImportStatus { added, duplicate, rejected }

class SingleImportResult {
  final SingleImportStatus status;
  final LibModel? model;
  final String? message;

  const SingleImportResult(this.status, {this.model, this.message});
}

/// 单件入库：先过闸，再按 id 去重（撞已有 id 跳过）。
class SingleModelImporter {
  const SingleModelImporter._();

  static Future<SingleImportResult> add(
    LibModelsStore store,
    ModelTransferItem item,
  ) async {
    try {
      ObjParserGate.check(item.objText);
    } on ObjParseException catch (e) {
      return SingleImportResult(
        SingleImportStatus.rejected,
        message: e.message,
      );
    }
    final existing = await store.load();
    if (existing.any((m) => m.id == item.id)) {
      return SingleImportResult(
        SingleImportStatus.duplicate,
        model: existing.firstWhere((m) => m.id == item.id),
      );
    }
    final list = await store.add(item.toLibModel());
    final saved = list.firstWhere(
      (m) => m.id == item.id,
      orElse: () => item.toLibModel(),
    );
    return SingleImportResult(SingleImportStatus.added, model: saved);
  }
}

/// 5000 面 / 300KB 闸的直通口（不放宽）。单独包一层是为了让测试和 UI
/// 都只说「过闸」，不重复拼 ObjParser 调用。
///
/// v0.1.44：闸从 `parse` 拆到 [ObjParser.gate] —— `parse` 现在能吃 10MB 大文件
/// （OBJ 流程要先收进来再减面），只有「直接入库」（单件/全量 JSON）还走这道闸。
class ObjParserGate {
  const ObjParserGate._();

  static void check(String objText) => ObjParser.gate(objText);
}
