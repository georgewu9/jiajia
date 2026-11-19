// 模型库：用户导入的外部 OBJ（家具/收纳/自定义件），存 app 根目录下
// `lib_models.json`（与 `plans/` 同级），全 app 共用一份。
//
// 与户型 JSON 的关系：
//   · FurnitureItem 只记 `lib: <id>`，不把 OBJ 文本塞进每份户型（几 MB 级）；
//   · 3D 端由 [LibModelsStore.payloadForPlan] 收集「本户型引用到的」库模型，
//     随 setPlan 的 `libs` 数组下发；
//   · 库文件单独导出/导入（jiajia_models.json），跨设备搬运模型库。
//
// 所有读操作都宽容：文件缺失/损坏/字段缺失 → 返回空表或跳过该条，绝不崩。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../domain/floor_plan.dart';
import '../domain/furniture_tabs.dart';
import '../domain/obj_parse.dart';

/// 一个库模型（OBJ 文本 + 展示/摆放尺寸）。
class LibModel {
  final String id;

  /// 展示名（同一分类内可重名，入库时自动加 (1)）。
  final String name;

  /// 5 个家具分类之一（FurnitureTabs.cats）。
  final String cat;

  /// 宽松尺寸（米）；导出/导入缺失时按 bbox 或 1×0.6×1 兜底。
  final double wM;
  final double dM;
  final double hM;

  /// 原始 OBJ 文本（3D 端 parseOBJ 直接吃）。
  final String objText;

  const LibModel({
    required this.id,
    required this.name,
    required this.cat,
    required this.wM,
    required this.dM,
    required this.hM,
    required this.objText,
  });

  /// 由 OBJ 文本生成稳定 id：md5 前 10 位（同文件重复导入 → 同 id → 跳过）。
  static String idForText(String objText) => _md5Hex(objText).substring(0, 10);

  LibModel copyWith({String? name}) => LibModel(
    id: id,
    name: name ?? this.name,
    cat: cat,
    wM: wM,
    dM: dM,
    hM: hM,
    objText: objText,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cat': cat,
    'wM': wM,
    'dM': dM,
    'hM': hM,
    'objText': objText,
  };

  /// 宽容解析单条：id/name/cat/objText 缺失 → null（跳过该条）；
  /// 尺寸缺失/非法 → 用 bbox，再不行用 1×0.6×1（与 FurnitureKind.lib 默认一致）。
  static LibModel? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final cat = j['cat'];
    final obj = j['objText'];
    if (id is! String || id.trim().isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (cat is! String || cat.trim().isEmpty) return null;
    if (obj is! String || obj.trim().isEmpty) return null;

    ObjData? bbox;
    // 只有尺寸缺失/非法时才解析 bbox：正常入库的条目一定带 wM/dM/hM，
    // 避免 3D 每次推数据都把几百 KB 的 OBJ 重扫一遍。
    double? numOf(Object? v) =>
        (v is num && v.isFinite && v > 0) ? v.toDouble() : null;
    final hasDims =
        numOf(j['wM']) != null &&
        numOf(j['dM']) != null &&
        numOf(j['hM']) != null;
    if (!hasDims) {
      try {
        bbox = ObjParser.parse(obj);
      } catch (_) {
        bbox = null;
      }
    }
    // 尺寸优先级：文件里的值 > bbox 跨度 > 默认（bbox 跨度为 0 也一样要兜底，
    // 平面三角/薄片模型的某一轴本来就是 0）。
    double pick(Object? raw, double bboxVal, double fallback) {
      if (raw is num && raw.isFinite && raw > 0) return raw.toDouble();
      if (bboxVal > 0) return bboxVal;
      return fallback;
    }

    return LibModel(
      id: id,
      name: name,
      // 分类只允许 5 类之一：外部文件写了未知分类 → 归「其他」，否则网格里永远看不到
      cat: FurnitureTabs.cats.contains(cat) ? cat : '其他',
      wM: pick(j['wM'], bbox?.bboxW ?? 0, 1.0),
      dM: pick(j['dM'], bbox?.bboxD ?? 0, 0.6),
      hM: pick(j['hM'], bbox?.bboxH ?? 0, 1.0),
      objText: obj,
    );
  }
}

/// 模型库文件读写。`root` 可注入（单测传临时目录，同 PlanStore 套路）。
class LibModelsStore {
  /// 默认 app 文档目录；lib_models.json 直接放根下（与 plans/ 同级）。
  final Directory? root;

  LibModelsStore({this.root});

  static const String fileName = 'lib_models.json';

  /// 2D 平面图/操作条要同步显示库模型名字 → 读过的名字缓存在这里，
  /// 让 CustomPainter（同步绘制）不用等 IO。
  static final Map<String, String> _nameCache = {};

  static String? nameOf(String? id) => id == null ? null : _nameCache[id];

  static void remember(Iterable<LibModel> models) {
    for (final m in models) {
      _nameCache[m.id] = m.name;
    }
  }

  Future<File> _file() async {
    final app = root ?? await getApplicationDocumentsDirectory();
    return File('${app.path}/$fileName');
  }

  /// 读全部库模型：文件缺失/JSON 损坏/结构不对 → 空表。
  Future<List<LibModel>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const <LibModel>[];
      final j = jsonDecode(await f.readAsString());
      if (j is! Map<String, dynamic>) return const <LibModel>[];
      final raw = j['models'];
      if (raw is! List) return const <LibModel>[];
      final out = <LibModel>[];
      for (final e in raw) {
        if (e is! Map<String, dynamic>) continue;
        final m = LibModel.fromJson(e);
        if (m != null) out.add(m);
      }
      remember(out);
      return out;
    } catch (_) {
      return const <LibModel>[];
    }
  }

  /// 覆盖写整库（先建根目录，root 由测试注入时可能还不存在）。
  Future<void> save(List<LibModel> models) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode({
        'version': 1,
        'models': models.map((m) => m.toJson()).toList(),
      }),
    );
    remember(models);
  }

  /// 追加一条：id 已存在 → 原样返回（重复导入同一 OBJ 不产生第二条）；
  /// 同分类同名 → 自动加 (1)(2)…（与 PlanStore 的重名规则一致）。
  Future<List<LibModel>> add(LibModel model) async {
    final list = await load();
    final r = merge(list, [model]);
    await save(r.models);
    return r.models;
  }

  /// 删除一条（按 id），返回删除后的整库。
  Future<List<LibModel>> remove(String id) async {
    final list = (await load()).where((m) => m.id != id).toList();
    await save(list);
    return list;
  }

  /// 同分类内取不重名的名字：base → base(1) → base(2)…
  static String uniqueName(List<LibModel> list, String base, String cat) {
    var name = base;
    var n = 1;
    bool taken(String s) => list.any((m) => m.cat == cat && m.name == s);
    while (taken(name)) {
      name = '$base($n)';
      n++;
    }
    return name;
  }

  /// 合并导入：id 重复 → 跳过计数；同名同分类 → 加 (1)。规则同 PlanIo 重名。
  static LibMergeResult merge(
    List<LibModel> existing,
    List<LibModel> incoming,
  ) {
    final out = <LibModel>[...existing];
    var added = 0;
    var skipped = 0;
    for (final m in incoming) {
      if (out.any((x) => x.id == m.id)) {
        skipped++;
        continue;
      }
      out.add(m.copyWith(name: uniqueName(out, m.name, m.cat)));
      added++;
    }
    return LibMergeResult(models: out, added: added, skipped: skipped);
  }

  /// 给 3D setPlan 用的 `libs` 载荷：只含本户型 items 引用到的库模型（去重）。
  /// 形状：`[{id, n, obj, w, d, h, c}]`（n=名字，占位回退时显示；c=占位色）。
  static Future<List<Map<String, dynamic>>> payloadForPlan(
    FloorPlan plan, {
    LibModelsStore? store,
  }) async {
    final ids = <String>{};
    for (final i in plan.items.values) {
      final id = i.lib;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return const <Map<String, dynamic>>[];
    final all = await (store ?? LibModelsStore()).load();
    const palette = [0x8FB7D6, 0x9FD3A8, 0xD9B28A, 0xC7A88F, 0xB08968];
    final out = <Map<String, dynamic>>[];
    var n = 0;
    for (final m in all) {
      if (!ids.contains(m.id)) continue;
      out.add({
        'id': m.id,
        'n': m.name,
        'obj': m.objText,
        'w': m.wM,
        'd': m.dM,
        'h': m.hM,
        'c': palette[n++ % palette.length],
      });
    }
    return out;
  }
}

/// 合并结果（供 SnackBar 报「导入 X 条，跳过 Y 条重复」）。
class LibMergeResult {
  final List<LibModel> models;
  final int added;
  final int skipped;

  const LibMergeResult({
    required this.models,
    required this.added,
    required this.skipped,
  });
}

/// 模型库文件（jiajia_models.json）的导出/导入信封。
class LibModelsCodec {
  const LibModelsCodec._();

  /// 导出信封：`{app:'jiajia', type:'modelLib', version:1, exportedAt, models:[...]}`。
  static String encodeExport(List<LibModel> models) => jsonEncode({
    'app': 'jiajia',
    'type': 'modelLib',
    'version': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'models': models.map((m) => m.toJson()).toList(),
  });

  /// 导入解析：type 必须为 modelLib；逐条 schema（id/name/cat/objText 必有）
  /// 不合格的行跳过并计入 [LibImportPayload.invalid]，不因单条脏数据整份失败。
  static LibImportPayload decodeImport(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('不是模型库文件：顶层应为 JSON 对象');
    }
    if (j['type'] != 'modelLib') {
      throw const FormatException('不是模型库文件：type 应为 modelLib');
    }
    final raw = j['models'];
    if (raw is! List) {
      throw const FormatException('模型库文件缺少 models 数组');
    }
    final out = <LibModel>[];
    var invalid = 0;
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        invalid++;
        continue;
      }
      final m = LibModel.fromJson(e);
      if (m == null) {
        invalid++;
        continue;
      }
      out.add(m);
    }
    return LibImportPayload(models: out, invalid: invalid);
  }
}

/// 模型库文件解析结果。
class LibImportPayload {
  final List<LibModel> models;

  /// schema 不合格被跳过的条数。
  final int invalid;

  const LibImportPayload({required this.models, required this.invalid});
}

// ---------------- MD5（只在入库 id 用；不新增 pubspec 依赖） ----------------

const List<int> _md5K = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, //
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

const List<int> _md5S = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const int _u32 = 0xFFFFFFFF;

String _md5Hex(String input) {
  final src = utf8.encode(input);
  final bitLen = src.length * 8;
  final zeroPad = (56 - (src.length + 1) % 64 + 64) % 64;
  final msg = Uint8List(src.length + 1 + zeroPad + 8);
  msg.setRange(0, src.length, src);
  msg[src.length] = 0x80;
  var len = bitLen;
  final lenAt = msg.length - 8;
  for (var i = 0; i < 8; i++) {
    msg[lenAt + i] = len & 0xff;
    len >>= 8;
  }

  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  int rotl(int x, int c) => ((x << c) | (x >> (32 - c))) & _u32;

  final words = List<int>.filled(16, 0);
  for (var off = 0; off < msg.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      final p = off + i * 4;
      words[i] =
          msg[p] | (msg[p + 1] << 8) | (msg[p + 2] << 16) | (msg[p + 3] << 24);
    }
    var a = a0, b = b0, c = c0, d = d0;
    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | ((~b & _u32) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d & _u32) & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d & _u32));
        g = (7 * i) % 16;
      }
      f = (f + a + _md5K[i] + words[g]) & _u32;
      a = d;
      d = c;
      c = b;
      b = (b + rotl(f, _md5S[i])) & _u32;
    }
    a0 = (a0 + a) & _u32;
    b0 = (b0 + b) & _u32;
    c0 = (c0 + c) & _u32;
    d0 = (d0 + d) & _u32;
  }

  final out = StringBuffer();
  for (final w in [a0, b0, c0, d0]) {
    for (var i = 0; i < 4; i++) {
      out.write(((w >> (8 * i)) & 0xff).toRadixString(16).padLeft(2, '0'));
    }
  }
  return out.toString();
}
