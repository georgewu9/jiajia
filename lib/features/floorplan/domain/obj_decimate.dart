// 用户模型超闸自动减面（v0.1.44）：纯 Dart 顶点聚类（voxel 网格焊接）。
//
// 背景：真机导入 8.8MB 的 japaneseMaple.obj（十万级面）被 300KB/5000 面闸拒，
// 用户要「太大你可以压缩一下」——不是放宽闸，而是导入时先减面再按同一闸入库。
//
// 算法：顶点聚类（vertex clustering）
//   · 格宽 = bbox 最大边 / n，n 由 128 逐级减半到 8（128→64→32→16→8）；
//   · 顶点吸附到所在格心（坐标保留浮点精度写出，格内差异被抹平）；
//   · 按新索引重建拓扑，删退化面（重复索引 / 零面积）与全重复面；
//   · 取第一个「面数 ≤ targetFaces 且 objText ≤ 300KB」的级别；
//     全都没达标 → 取最粗且非空的一级（再不行就 0 面，交调用方按失败处理）。
//
// 复杂度 O(V + T) 每级，最多 5 级；10 万面输入实测 <100ms（详见测试）。
// 输出只有 `v` + `f`：vt/vn/usemtl 全部丢掉——viewer.js 的 libGeometry 只用
// 单色材质（lib.c），贴图/法线本就不参与；颜色由 LibModel.color 决定。
import 'dart:collection';

import 'obj_parse.dart';

/// 减面结果：新 ObjData（bbox 沿用原始值）+ 可入库的 OBJ 文本。
class DecimatedObj {
  /// 减后摘要：faceCount=新面数，bbox 用**减面前**的原始包围盒
  /// （与 2D/3D 渲染的 wMm/dMm/hMm 一致，减面不会悄悄改尺寸）。
  final ObjData data;

  /// 纯 `v`+`f` 的 OBJ 文本（[changed] 为 false 时就是原始文本）。
  final String objText;

  final int fromFaces;
  final int toFaces;

  /// 是否真的减了面（false = 原样透传，行为与 v0.1.43 完全一致）。
  final bool changed;

  const DecimatedObj({
    required this.data,
    required this.objText,
    required this.fromFaces,
    required this.toFaces,
    required this.changed,
  });
}

class ObjDecimate {
  const ObjDecimate._();

  /// 目标面数（低于入库闸 5000，给四舍五入/追加面留余量）。
  static const int defaultTargetFaces = 4800;

  /// 网格密度序列：细 → 粗。第一个同时满足面数与体积的级别胜出。
  static const List<int> gridSteps = [128, 64, 32, 16, 8];

  /// 入库闸的文本上限（超过则必须继续降级，哪怕面数已经达标）。
  static const int _maxOutChars = ObjParser.maxChars;

  /// 把 [src]（[ObjParser.parse] 的结果）减到 [targetFaces] 面以内。
  ///
  /// 输入本来就小（≤5000 面且 ≤300KB）→ `changed=false`，[objText] 就是
  /// [ObjData.text]（原样透传，不改一个字节）。
  static DecimatedObj tryDecimate(
    ObjData src, {
    int targetFaces = defaultTargetFaces,
  }) {
    final fromFaces = src.faceCount;
    if (fromFaces <= ObjParser.maxFaces && src.text.length <= _maxOutChars) {
      return DecimatedObj(
        data: src,
        objText: src.text,
        fromFaces: fromFaces,
        toFaces: fromFaces,
        changed: false,
      );
    }

    final verts = src.verts;
    final tris = src.tris;
    final vCount = verts.length ~/ 3;

    // 空几何 / 索引全坏：没有可减的东西，返回 0 面（调用方按失败处理）。
    if (vCount == 0 || tris.length < 3) {
      return _degenerate(src, fromFaces);
    }

    final maxEdge = _maxEdge(src);
    if (maxEdge <= 0) return _degenerate(src, fromFaces);

    // 零面积阈值：相对 bbox（避免单位是 mm 的模型阈值失效）。
    final areaEps = 1e-12 * maxEdge * maxEdge;

    DecimatedObj? best;
    final remap = List<int>.filled(vCount, 0);

    for (final n in gridSteps) {
      final cell = maxEdge / n;
      final welded = _weld(verts, vCount, n, cell, remap);
      final kept = _rebuildFaces(
        tris,
        remap,
        welded.verts,
        cell,
        areaEps,
        welded.count,
      );
      if (kept.tris.isEmpty) {
        // 这一级全退化了：继续试更粗的级别（再粗只会更糟，最后统一兜底）。
        continue;
      }
      final text = _writeObj(welded.verts, kept.tris);
      final out = DecimatedObj(
        data: ObjData(
          vertexCount: welded.count,
          faceCount: kept.tris.length ~/ 3,
          bboxW: src.bboxW,
          bboxD: src.bboxD,
          bboxH: src.bboxH,
          text: text,
          verts: welded.verts,
          tris: kept.tris,
        ),
        objText: text,
        fromFaces: fromFaces,
        toFaces: kept.tris.length ~/ 3,
        changed: true,
      );
      best = out; // 更粗的级别覆盖：留作兜底（保证文本最小）
      if (out.toFaces <= targetFaces && text.length <= _maxOutChars) {
        return out;
      }
    }

    // 所有级别都没同时达标：返回最粗非空的那份（体积必然最小）；
    // 一级都救不回来（全退化）→ 0 面，交调用方按失败处理。
    if (best == null || best.toFaces == 0) return _degenerate(src, fromFaces);
    return best;
  }

  static DecimatedObj _degenerate(ObjData src, int fromFaces) {
    final data = ObjData(
      vertexCount: 0,
      faceCount: 0,
      bboxW: src.bboxW,
      bboxD: src.bboxD,
      bboxH: src.bboxH,
      text: '',
      verts: const <double>[],
      tris: const <int>[],
    );
    return DecimatedObj(
      data: data,
      objText: '',
      fromFaces: fromFaces,
      toFaces: 0,
      changed: true,
    );
  }

  static double _maxEdge(ObjData s) {
    var m = s.bboxW;
    if (s.bboxD > m) m = s.bboxD;
    if (s.bboxH > m) m = s.bboxH;
    return m;
  }

  /// 顶点焊接：每个顶点 → 格（ix,iy,iz）→ 格内首个顶点的序号，坐标写格心。
  ///
  /// 格心 = min + (i + 0.5) * cell：模型整体最多向内收半格（≈ bbox/2n），
  /// 渲染侧（viewer.js libGeometry / 2D 轮廓）都按自身 bbox 重新 fit，
  /// 尺寸不受影响；入库 wMm/dMm/hMm 继续用原始 bbox。
  static _Welded _weld(
    List<double> verts,
    int vCount,
    int n,
    double cell,
    List<int> remap,
  ) {
    // bbox 最小值直接用原始数据重算（parse 只给了跨度，没有 min）。
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    for (var i = 0; i < vCount; i++) {
      final x = verts[i * 3], y = verts[i * 3 + 1], z = verts[i * 3 + 2];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
    }

    final map = HashMap<int, int>();
    final out = <double>[];
    var count = 0;
    final inv = 1.0 / cell;
    for (var i = 0; i < vCount; i++) {
      final x = verts[i * 3], y = verts[i * 3 + 1], z = verts[i * 3 + 2];
      var ix = ((x - minX) * inv).floor();
      var iy = ((y - minY) * inv).floor();
      var iz = ((z - minZ) * inv).floor();
      if (ix < 0) ix = 0;
      if (ix >= n) ix = n - 1;
      if (iy < 0) iy = 0;
      if (iy >= n) iy = n - 1;
      if (iz < 0) iz = 0;
      if (iz >= n) iz = n - 1;
      final key = (ix * n + iy) * n + iz;
      final hit = map[key];
      if (hit != null) {
        remap[i] = hit;
        continue;
      }
      map[key] = count;
      remap[i] = count;
      count++;
      out
        ..add(minX + (ix + 0.5) * cell)
        ..add(minY + (iy + 0.5) * cell)
        ..add(minZ + (iz + 0.5) * cell);
    }
    return _Welded(out, count);
  }

  /// 重建拓扑：重映射索引 → 丢重复索引/零面积 → 丢全重复面。
  static _Faces _rebuildFaces(
    List<int> tris,
    List<int> remap,
    List<double> verts,
    double cell,
    double areaEps,
    int vCount,
  ) {
    final out = <int>[];
    final seen = HashSet<int>();
    for (var i = 0; i + 2 < tris.length; i += 3) {
      final a = remap[tris[i]];
      final b = remap[tris[i + 1]];
      final c = remap[tris[i + 2]];
      if (a == b || b == c || a == c) continue; // 重复索引
      // 零面积（三点共线 / 完全重合）：叉积长度就是 2×面积
      final ax = verts[a * 3], ay = verts[a * 3 + 1], az = verts[a * 3 + 2];
      final ux = verts[b * 3] - ax,
          uy = verts[b * 3 + 1] - ay,
          uz = verts[b * 3 + 2] - az;
      final vx = verts[c * 3] - ax,
          vy = verts[c * 3 + 1] - ay,
          vz = verts[c * 3 + 2] - az;
      final cx = uy * vz - uz * vy;
      final cy = uz * vx - ux * vz;
      final cz = ux * vy - uy * vx;
      if (cx * cx + cy * cy + cz * cz <= areaEps * areaEps) continue;
      // 全重复面：三角形三点集合相同（不看绕向）即视为重复
      final s0 = a < b ? (a < c ? a : c) : (b < c ? b : c);
      final s2 = a > b ? (a > c ? a : c) : (b > c ? b : c);
      final s1 = a + b + c - s0 - s2;
      final key = (s0 * vCount + s1) * vCount + s2;
      if (!seen.add(key)) continue;
      out
        ..add(a)
        ..add(b)
        ..add(c);
    }
    // cell 只用于注释说明「格内差异被抹平」，这里不参与判定。
    assert(cell > 0);
    return _Faces(out);
  }

  /// 写纯 `v`+`f` 文本：十进制坐标（6 位小数，去尾零），面索引 1 基。
  static String _writeObj(List<double> verts, List<int> tris) {
    final b = StringBuffer();
    final n = verts.length ~/ 3;
    for (var i = 0; i < n; i++) {
      b
        ..write('v ')
        ..write(_fmt(verts[i * 3]))
        ..write(' ')
        ..write(_fmt(verts[i * 3 + 1]))
        ..write(' ')
        ..write(_fmt(verts[i * 3 + 2]))
        ..write('\n');
    }
    for (var i = 0; i + 2 < tris.length; i += 3) {
      b
        ..write('f ')
        ..write(tris[i] + 1)
        ..write(' ')
        ..write(tris[i + 1] + 1)
        ..write(' ')
        ..write(tris[i + 2] + 1)
        ..write('\n');
    }
    return b.toString();
  }

  /// 6 位小数 + 去尾零：1e-6 米 = 1µm，远细于任何格宽；同时避免
  /// `toString()` 把 0.30000000000000004 这类浮点噪声写成 20 字符。
  static String _fmt(double v) {
    if (v == 0) return '0';
    final s = v.toStringAsFixed(6);
    // 手扫尾部 '0'（每顶点 3 次调用，不能逐次编译 RegExp）
    var end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (end > 0 && s.codeUnitAt(end - 1) == 0x2E) end--; // '.'
    return s.substring(0, end);
  }
}

class _Welded {
  final List<double> verts;
  final int count;
  const _Welded(this.verts, this.count);
}

class _Faces {
  final List<int> tris;
  const _Faces(this.tris);
}
