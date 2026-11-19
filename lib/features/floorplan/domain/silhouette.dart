// 2D 平面图「俯视轮廓」：数据结构 + 纯几何构建 + 参考算法。
//
// 数据来自 tool/silhouette_gen.py 预生成的 model_silhouettes.dart（内置模型，
// 免得每帧解析几百 KB 的 OBJ）；用户素材（P2）走本文件里的
// [buildSilhouetteFromObj] / [buildSilhouetteFromTriangles] —— 与生成器同一套参数。
//
// 坐标系：u = 宽向 X，v = 深向 Z，均归一化到 0..1（模型自身 bbox）。
// 与 3D 俯视的对应关系由 viewer.js 决定：
//   · 俯视相机 camera.up = (0,0,-1) → 屏幕上方 = -Z、屏幕下方 = +Z
//     （assets/web/viewer.js applyPlan 的 top 分支，约 L1053-1056）
//   · 3D 绕 Y 旋转用 rotation.y = -rotDeg（buildItems，约 L892/L914），
//     与 2D canvas.rotate(+rotDeg)（屏幕 y 向下）等价
// 所以 2D 直接 (x, y) = ((u-0.5)*fw, (v-0.5)*fd) 即可，不需要翻转 v。
//
// 参数常量与 tool/silhouette_gen.py 顶部一致，改动必须两边同步。
import 'dart:math' as math;
import 'dart:ui';

// ---------------- 算法参数（与 tool/silhouette_gen.py 一一对应） ----------------
const int kSilGrid = 128; // 栅格边长
const double kSilRasterTolPx = 0.5; // 像素中心距三角形 ≤0.5px 即算覆盖（细条不丢）
const double kSilDpEpsPx = 0.5; // Douglas-Peucker ε（像素）
const int kSilMaxOuterPts = 80; // 单条外轮廓点数上限
const int kSilMaxHolePts = 40; // 单个孔洞点数上限
const double kSilMinHoleArea = 0.01; // 孔洞面积占比下限（低于丢弃）
const double kSilMinOuterArea = 0.002; // 碎件外形面积占比下限
const int kSilMaxOuterLoops = 12; // 多块外形最多保留环数
const double kSilLineMinLen = 0.05; // 内部线投影长下限（归一化）
const double kSilLineMaxLen = 0.9; // 内部线投影长上限
const double kSilLineEdgeDist = 0.02; // 距外轮廓 < 此值丢弃
const double kSilLineMergeDist = 0.015; // 近平行重合合并：中点距
const double kSilLineMergeDot = 0.99; // 近平行重合合并：方向点积
const int kSilLineMax = 16; // 内部线条数上限
const double kSilUpFaceNy = 0.2; // 「上向面」法线 y 分量阈值
const int kSilOrganicCand = 60; // 候选分隔边 > 此数 → 顶面杂乱，lines=[]

/// 一件模型的俯视轮廓。
///
/// 所有坐标都是 0..1 的归一化值，扁平存放：[u,v,u,v,...]。
/// · [outer] 外轮廓环（可多条：模型由多块互不相连的碎件组成时每块一条），CCW；
/// · [holes] 孔洞环，CW（与 outer 反向，nonZero 填充才能挖空）；
/// · [lines] 内部主分隔线 [u1,v1,u2,v2]（顶面台阶/拼缝），不是闭环。
class ModelSilhouette {
  final List<List<double>> outer;
  final List<List<double>> holes;
  final List<List<double>> lines;

  const ModelSilhouette({
    required this.outer,
    required this.holes,
    required this.lines,
  });

  bool get isEmpty => outer.isEmpty;

  /// 序列化（键 'o'/'h'/'l'；u/v 取 4 位小数）。
  Map<String, dynamic> toJson() => {
    'o': [for (final l in outer) _round4(l)],
    'h': [for (final l in holes) _round4(l)],
    'l': [for (final s in lines) _round4(s)],
  };

  /// 从 OBJ 文本现算俯视轮廓（P2 用户素材 / 单件导出时补算）。
  ///
  /// 与 [buildSilhouetteFromObj] 同一套算法与参数（见文件顶常量与
  /// tool/silhouette_gen.py）；几何为空/退化/栅格空 → [FormatException]。
  factory ModelSilhouette.fromObjText(String objText) =>
      buildSilhouetteFromObj(objText);

  /// [fromObjText] 的宽容版：任何异常（含格式错误/索引越界）→ null。
  /// 入库/导出/渲染链路用它，坏模型只是没有轮廓，不让整条导入失败。
  static ModelSilhouette? tryFromObjText(String? objText) {
    if (objText == null || objText.trim().isEmpty) return null;
    try {
      return buildSilhouetteFromObj(objText);
    } catch (_) {
      return null;
    }
  }

  /// 宽容解析：形状不对抛 [FormatException]，由调用方（silhouetteFor）兜住。
  factory ModelSilhouette.fromJson(Map<String, dynamic> j) {
    List<List<double>> loops(String key) {
      final raw = j[key];
      if (raw == null) return const [];
      if (raw is! List) throw FormatException('$key 不是数组');
      final out = <List<double>>[];
      for (final l in raw) {
        if (l is! List) throw FormatException('$key 内含非数组');
        final flat = <double>[];
        for (final c in l) {
          if (c is! num) throw FormatException('$key 内含非数字');
          flat.add(c.toDouble());
        }
        out.add(flat);
      }
      return out;
    }

    final outer = loops('o');
    for (final l in outer) {
      if (l.length < 6 || l.length % 2 != 0) {
        throw const FormatException('外轮廓点数不足');
      }
    }
    if (outer.isEmpty) throw const FormatException('缺外轮廓');
    return ModelSilhouette(
      outer: outer,
      holes: loops('h'),
      lines: loops('l'),
    );
  }
}

List<double> _round4(List<double> v) =>
    [for (final c in v) _r4(c)];

double _r4(double x) {
  final r = (x * 10000).roundToDouble() / 10000;
  return r == 0 ? 0.0 : r; // 抹掉 -0.0
}

// ---------------- 渲染用的纯几何 ----------------

/// 构造填充/描边路径：外轮廓 + 孔洞（nonZero）。
///
/// [fw]/[fd] 是画布上的占地像素（= item.footprint × ppm），与旧 RRect 同一个
/// 居中框：轮廓点 (u,v) → ((u-0.5)*fw, (v-0.5)*fd)。返回值已经居中于原点，
/// 调用方（painter）在外面做 translate/rotate。
Path buildSilhouettePath(ModelSilhouette s, double fw, double fd) {
  final path = Path()..fillType = PathFillType.nonZero;
  if (s.outer.isEmpty) return path;
  final outerSign = _areaSign(s.outer.first);
  for (final loop in s.outer) {
    _addLoop(path, loop, fw, fd, reverse: _areaSign(loop) != outerSign);
  }
  for (final loop in s.holes) {
    // 孔洞必须与外轮廓反向，否则 nonZero 填不满（数据已保证，这里兜底）
    _addLoop(path, loop, fw, fd, reverse: _areaSign(loop) == outerSign);
  }
  return path;
}

/// 内部主分隔线（未闭合的线段）。没有线时返回 null，省一次 drawPath。
Path? buildSilhouetteLinesPath(ModelSilhouette s, double fw, double fd) {
  if (s.lines.isEmpty) return null;
  final path = Path();
  for (final seg in s.lines) {
    if (seg.length < 4) continue;
    path.moveTo((seg[0] - 0.5) * fw, (seg[1] - 0.5) * fd);
    path.lineTo((seg[2] - 0.5) * fw, (seg[3] - 0.5) * fd);
  }
  return path;
}

void _addLoop(Path p, List<double> loop, double fw, double fd,
    {bool reverse = false}) {
  final n = loop.length ~/ 2;
  if (n < 3) return;
  for (var i = 0; i < n; i++) {
    final k = reverse ? (n - 1 - i) : i;
    final x = (loop[k * 2] - 0.5) * fw;
    final y = (loop[k * 2 + 1] - 0.5) * fd;
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  p.close();
}

double _areaSign(List<double> loop) {
  final n = loop.length ~/ 2;
  var a = 0.0;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    a += loop[i * 2] * loop[j * 2 + 1] - loop[j * 2] * loop[i * 2 + 1];
  }
  return a >= 0 ? 1.0 : -1.0;
}

/// 外轮廓的 UV 包围盒（调试/测试用；v 轴不加翻转）。
Rect silhouetteUvBounds(ModelSilhouette s) {
  var minU = 1.0, maxU = 0.0, minV = 1.0, maxV = 0.0;
  for (final loop in s.outer) {
    for (var i = 0; i + 1 < loop.length; i += 2) {
      minU = math.min(minU, loop[i]);
      maxU = math.max(maxU, loop[i]);
      minV = math.min(minV, loop[i + 1]);
      maxV = math.max(maxV, loop[i + 1]);
    }
  }
  return Rect.fromLTRB(minU, minV, maxU, maxV);
}

// ---------------- 参考算法（同 tool/silhouette_gen.py） ----------------
// P2 用户素材复用这里；测试也用它证明生成数据与算法一致。

/// 顶点（米，three.js Y-up）。
class SilVec3 {
  final double x, y, z;
  const SilVec3(this.x, this.y, this.z);
}

/// 三角面（顶点下标，0 基）。
class SilTri {
  final int a, b, c;
  const SilTri(this.a, this.b, this.c);
}

/// 从 OBJ 文本算俯视轮廓（只认 v / f，f 允许 v/vt/vn 与负索引）。
ModelSilhouette buildSilhouetteFromObj(String objText) {
  final verts = <SilVec3>[];
  final tris = <SilTri>[];
  for (final raw in objText.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('v ')) {
      final p = line.split(RegExp(r'\s+'));
      if (p.length < 4) continue;
      final x = double.tryParse(p[1]);
      final y = double.tryParse(p[2]);
      final z = double.tryParse(p[3]);
      if (x == null || y == null || z == null) continue;
      verts.add(SilVec3(x, y, z));
    } else if (line.startsWith('f ')) {
      final p = line.split(RegExp(r'\s+')).skip(1).toList();
      if (p.length < 3) continue;
      final idx = <int>[];
      for (final a in p) {
        final n = int.tryParse(a.split('/').first);
        if (n == null) continue;
        idx.add(n > 0 ? n - 1 : verts.length + n);
      }
      for (var k = 1; k < idx.length - 1; k++) {
        final t = SilTri(idx[0], idx[k], idx[k + 1]);
        // 越界索引（闸只数面数/顶点，不校验引用）→ 丢这个三角，
        // 与 Python 版 rasterize/normals 里的 IndexError 跳过等价。
        if (t.a < 0 || t.b < 0 || t.c < 0) continue;
        if (t.a >= verts.length || t.b >= verts.length || t.c >= verts.length) {
          continue;
        }
        tris.add(t);
      }
    }
  }
  return buildSilhouetteFromTriangles(verts, tris);
}

/// 三角网格 → 俯视轮廓（栅格 128×128 + 边界追踪 + DP + 顶面分隔线）。
ModelSilhouette buildSilhouetteFromTriangles(List<SilVec3> verts, List<SilTri> tris) {
  if (verts.isEmpty || tris.isEmpty) {
    throw const FormatException('空几何');
  }
  var minX = double.infinity, maxX = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  var minY = double.infinity, maxY = -double.infinity;
  for (final v in verts) {
    minX = math.min(minX, v.x);
    maxX = math.max(maxX, v.x);
    minZ = math.min(minZ, v.z);
    maxZ = math.max(maxZ, v.z);
    minY = math.min(minY, v.y);
    maxY = math.max(maxY, v.y);
  }
  final w = maxX - minX;
  final d = maxZ - minZ;
  if (w < 1e-9 || d < 1e-9) throw const FormatException('X/Z 跨度为 0');

  final grid = _raster(verts, tris, w, d, minX, minZ);
  final filled = grid.where((c) => c == 1).length;
  if (filled == 0) throw const FormatException('栅格空');

  // 多块碎件：闭运算桥接发丝缝后按绕向分类；取环数最少的 r（≤3）。
  var bestOuter = <List<int>>[];
  var bestHoles = <List<int>>[];
  for (var r = 0; r <= 3; r++) {
    final g = r == 0 ? grid : _closing(grid, r);
    final o = <List<int>>[];
    final hh = <List<int>>[];
    for (final lp in _traceLoops(g)) {
      final a = _polyArea(lp);
      if (a > 0) {
        if (_absArea(lp) >= kSilMinOuterArea * filled) o.add(lp);
      } else if (_absArea(lp) >= kSilMinHoleArea * filled) {
        hh.add(lp);
      }
    }
    if (bestOuter.isEmpty || o.length < bestOuter.length) {
      bestOuter = o;
      bestHoles = hh;
    }
    if (o.length == 1) break;
  }
  if (bestOuter.isEmpty) throw const FormatException('无轮廓');

  bestOuter.sort((a, b) => _polyArea(b).compareTo(_polyArea(a)));
  final outer = <List<double>>[
    for (final lp in bestOuter.take(kSilMaxOuterLoops))
      _toUv(_dpClosed(lp, kSilDpEpsPx, kSilMaxOuterPts), w, d, minX, minZ),
  ];
  final holes = <List<double>>[
    for (final hp in bestHoles.take(8))
      _toUv(_dpClosed(hp, kSilDpEpsPx, kSilMaxHolePts), w, d, minX, minZ),
  ];

  final normals = _normals(verts, tris);
  final lines = _internalLines(verts, tris, normals, w, d, minX, minZ, outer);
  return ModelSilhouette(
    outer: outer,
    holes: holes,
    lines: lines.lines,
  );
}

List<int> _raster(List<SilVec3> verts, List<SilTri> tris, double w, double d,
    double minX, double minZ) {
  final n = kSilGrid;
  final g = List<int>.filled(n * n, 0);
  final invW = n / w;
  final invD = n / d;
  for (final t in tris) {
    final va = verts[t.a], vb = verts[t.b], vc = verts[t.c];
    final ax = (va.x - minX) * invW, ay = (va.z - minZ) * invD;
    final bx = (vb.x - minX) * invW, by = (vb.z - minZ) * invD;
    final cx = (vc.x - minX) * invW, cy = (vc.z - minZ) * invD;
    final area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if (area.abs() < 1e-12) continue;
    final s = area > 0 ? 1.0 : -1.0;
    final t0 = kSilRasterTolPx * math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) * s;
    final t1 = kSilRasterTolPx * math.sqrt((cx - bx) * (cx - bx) + (cy - by) * (cy - by)) * s;
    final t2 = kSilRasterTolPx * math.sqrt((ax - cx) * (ax - cx) + (ay - cy) * (ay - cy)) * s;
    final i0 = math.max(0, math.min(ax, math.min(bx, cx)).floor());
    final i1 = math.min(n - 1, math.max(ax, math.max(bx, cx)).ceil());
    final j0 = math.max(0, math.min(ay, math.min(by, cy)).floor());
    final j1 = math.min(n - 1, math.max(ay, math.max(by, cy)).ceil());
    for (var j = j0; j <= j1; j++) {
      final py = j + 0.5;
      final row = j * n;
      for (var i = i0; i <= i1; i++) {
        final px = i + 0.5;
        var e0 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) * s;
        if (e0 < -t0) continue;
        var e1 = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) * s;
        if (e1 < -t1) continue;
        var e2 = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) * s;
        if (e2 < -t2) continue;
        g[row + i] = 1;
      }
    }
  }
  return g;
}

List<int> _closing(List<int> g, int r) => _filter(_filter(g, r, true), r, false);

List<int> _filter(List<int> g, int r, bool dilate) {
  // 补 r 圈 0 再滤、滤完裁掉：避免外形在数组边界被腐蚀掉 r 像素。
  final n = kSilGrid + 2 * r;
  final pad = List<int>.filled(n * n, 0);
  for (var j = 0; j < kSilGrid; j++) {
    for (var i = 0; i < kSilGrid; i++) {
      pad[(j + r) * n + i + r] = g[j * kSilGrid + i];
    }
  }
  final tmp = List<int>.filled(n * n, dilate ? 0 : 1);
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      var best = dilate ? 0 : 1;
      final lo = math.max(0, i - r), hi = math.min(n - 1, i + r);
      for (var k = lo; k <= hi; k++) {
        final v = pad[j * n + k];
        best = dilate ? math.max(best, v) : math.min(best, v);
      }
      tmp[j * n + i] = best;
    }
  }
  final out = List<int>.filled(kSilGrid * kSilGrid, 0);
  for (var j = 0; j < kSilGrid; j++) {
    for (var i = 0; i < kSilGrid; i++) {
      var best = dilate ? 0 : 1;
      final lo = j, hi = math.min(n - 1, j + 2 * r);
      for (var k = lo; k <= hi; k++) {
        final v = tmp[k * n + i + r];
        best = dilate ? math.max(best, v) : math.min(best, v);
      }
      out[j * kSilGrid + i] = best;
    }
  }
  return out;
}

/// 格子边界追踪（填充区在左 → 外轮廓 CCW、孔洞 CW）。点坐标是格点 (i,j)。
List<List<int>> _traceLoops(List<int> g) {
  final n = kSilGrid;
  bool f(int i, int j) =>
      i >= 0 && i < n && j >= 0 && j < n && g[j * n + i] == 1;

  // 每个格点最多 2 条出边；用 Map<int, List<int>> 存（key = j*(n+1)+i）
  final edges = <int, List<int>>{};
  void add(int x1, int y1, int x2, int y2) {
    final k = y1 * (n + 1) + x1;
    (edges[k] ??= <int>[]).add(y2 * (n + 1) + x2);
  }

  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      if (g[j * n + i] != 1) continue;
      if (!f(i, j - 1)) add(i, j, i + 1, j); // 下边 +u
      if (!f(i + 1, j)) add(i + 1, j, i + 1, j + 1); // 右边 +v
      if (!f(i, j + 1)) add(i + 1, j + 1, i, j + 1); // 上边 -u
      if (!f(i - 1, j)) add(i, j + 1, i, j); // 左边 -v
    }
  }

  final used = <int>{};
  final loops = <List<int>>[];
  for (final start in edges.keys.toList()) {
    while (true) {
      final first = (edges[start] ?? const <int>[])
          .where((q) => !used.contains(start * 100003 + q))
          .toList();
      if (first.isEmpty) break;
      var p = start;
      var q = first.first;
      used.add(p * 100003 + q);
      final loop = <int>[p, q];
      var prevDirX = q % (n + 1) - p % (n + 1);
      var prevDirY = q ~/ (n + 1) - p ~/ (n + 1);
      p = q;
      while (p != start) {
        final cand = (edges[p] ?? const <int>[])
            .where((r) => !used.contains(p * 100003 + r))
            .toList();
        if (cand.isEmpty) break;
        if (cand.length > 1) {
          // 对角相接的歧义点：取最靠左转的边（填充分成 4 连通）
          double turn(int r) {
            final dx = r % (n + 1) - p % (n + 1);
            final dy = r ~/ (n + 1) - p ~/ (n + 1);
            final cross = prevDirX * dy - prevDirY * dx;
            final dot = prevDirX * dx + prevDirY * dy;
            return math.atan2(cross, dot);
          }

          cand.sort((a, b) => turn(b).compareTo(turn(a)));
        }
        final r = cand.first;
        used.add(p * 100003 + r);
        loop.add(r);
        prevDirX = r % (n + 1) - p % (n + 1);
        prevDirY = r ~/ (n + 1) - p ~/ (n + 1);
        p = r;
      }
      if (loop.length >= 5 && loop.last == start) {
        loops.add(loop.sublist(0, loop.length - 1));
      } else if (loop.length >= 4) {
        loops.add(loop);
      }
    }
  }
  return loops;
}

double _polyArea(List<int> loop) {
  final n = kSilGrid + 1;
  var s = 0.0;
  for (var k = 0; k < loop.length; k++) {
    final x1 = (loop[k] % n).toDouble(), y1 = (loop[k] ~/ n).toDouble();
    final k2 = (k + 1) % loop.length;
    final x2 = (loop[k2] % n).toDouble(), y2 = (loop[k2] ~/ n).toDouble();
    s += x1 * y2 - x2 * y1;
  }
  return s / 2;
}

double _absArea(List<int> loop) => _polyArea(loop).abs();

/// Douglas-Peucker（闭环：切成两条开链，超点数则加大 ε）。
List<int> _dpClosed(List<int> pts, double eps, int cap) {
  if (pts.length <= 3) return pts;
  final n = kSilGrid + 1;
  double px(int k) => (pts[k] % n).toDouble();
  double py(int k) => (pts[k] ~/ n).toDouble();
  var cx = 0.0, cy = 0.0;
  for (var k = 0; k < pts.length; k++) {
    cx += px(k);
    cy += py(k);
  }
  cx /= pts.length;
  cy /= pts.length;
  var a = 0;
  var best = -1.0;
  for (var k = 0; k < pts.length; k++) {
    final dd = (px(k) - cx) * (px(k) - cx) + (py(k) - cy) * (py(k) - cy);
    if (dd > best) {
      best = dd;
      a = k;
    }
  }
  var b = 0;
  best = -1.0;
  for (var k = 0; k < pts.length; k++) {
    final dd = (px(k) - px(a)) * (px(k) - px(a)) + (py(k) - py(a)) * (py(k) - py(a));
    if (dd > best) {
      best = dd;
      b = k;
    }
  }
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  final ch1 = pts.sublist(a, b + 1);
  final ch2 = [...pts.sublist(b), ...pts.sublist(0, a + 1)];
  var e = eps;
  var out = <int>[];
  for (var it = 0; it < 12; it++) {
    final s1 = _dp(ch1, e);
    final s2 = _dp(ch2, e);
    out = [...s1.sublist(0, s1.length - 1), ...s2.sublist(0, s2.length - 1)];
    if (out.length <= cap) return out;
    e *= 1.7;
  }
  return out.take(cap).toList();
}

List<int> _dp(List<int> pts, double eps) {
  if (pts.length < 3) return List<int>.of(pts);
  final n = kSilGrid + 1;
  double px(int k) => (pts[k] % n).toDouble();
  double py(int k) => (pts[k] ~/ n).toDouble();
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <List<int>>[
    [0, pts.length - 1]
  ];
  while (stack.isNotEmpty) {
    final seg = stack.removeLast();
    final a = seg[0], b = seg[1];
    if (b <= a + 1) continue;
    final ax = px(a), ay = py(a), bx = px(b), by = py(b);
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    var bi = -1;
    var bd = -1.0;
    for (var k = a + 1; k < b; k++) {
      double dist;
      if (l2 < 1e-12) {
        dist = math.sqrt((px(k) - ax) * (px(k) - ax) + (py(k) - ay) * (py(k) - ay));
      } else {
        var t = ((px(k) - ax) * dx + (py(k) - ay) * dy) / l2;
        t = t.clamp(0.0, 1.0);
        final qx = ax + t * dx, qy = ay + t * dy;
        dist = math.sqrt((px(k) - qx) * (px(k) - qx) + (py(k) - qy) * (py(k) - qy));
      }
      if (dist > bd) {
        bd = dist;
        bi = k;
      }
    }
    if (bd > eps && bi > 0) {
      keep[bi] = true;
      stack.add([a, bi]);
      stack.add([bi, b]);
    }
  }
  return [for (var k = 0; k < pts.length; k++) if (keep[k]) pts[k]];
}

List<double> _toUv(List<int> pxLoop, double w, double d, double minX, double minZ) {
  final n = kSilGrid + 1;
  final out = <double>[];
  for (final p in pxLoop) {
    final u = ((p % n) / kSilGrid).clamp(0.0, 1.0);
    final v = ((p ~/ n) / kSilGrid).clamp(0.0, 1.0);
    out.add(_r4(u.toDouble()));
    out.add(_r4(v.toDouble()));
  }
  return out;
}

List<SilVec3?> _normals(List<SilVec3> verts, List<SilTri> tris) {
  final out = <SilVec3?>[];
  for (final t in tris) {
    final va = verts[t.a], vb = verts[t.b], vc = verts[t.c];
    final ux = vb.x - va.x, uy = vb.y - va.y, uz = vb.z - va.z;
    final wx = vc.x - va.x, wy = vc.y - va.y, wz = vc.z - va.z;
    final nx = uy * wz - uz * wy;
    final ny = uz * wx - ux * wz;
    final nz = ux * wy - uy * wx;
    final ln = math.sqrt(nx * nx + ny * ny + nz * nz);
    out.add(ln < 1e-12 ? null : SilVec3(nx / ln, ny / ln, nz / ln));
  }
  return out;
}

class _Lines {
  final List<List<double>> lines;
  final int candidates;
  const _Lines(this.lines, this.candidates);
}

_Lines _internalLines(List<SilVec3> verts, List<SilTri> tris, List<SilVec3?> ns,
    double w, double d, double minX, double minZ, List<List<double>> outerLoops) {
  final emap = <int, List<int>>{};
  void reg(int a, int b, int ti) {
    final k = a < b ? a * 100003 + b : b * 100003 + a;
    (emap[k] ??= <int>[]).add(ti);
  }

  for (var ti = 0; ti < tris.length; ti++) {
    final t = tris[ti];
    reg(t.a, t.b, ti);
    reg(t.b, t.c, ti);
    reg(t.c, t.a, ti);
  }

  final cand = <List<double>>[]; // [len, u1,v1,u2,v2, midU, midV]
  emap.forEach((k, ts) {
    if (ts.length != 2) return;
    final n1 = ns[ts[0]], n2 = ns[ts[1]];
    if (n1 == null || n2 == null) return;
    if (n1.y <= kSilUpFaceNy || n2.y <= kSilUpFaceNy) return;
    // 共面（同一平板被拆两个三角）→ 三角化对角线，不是分隔线
    if (n1.x * n2.x + n1.y * n2.y + n1.z * n2.z > 0.9995) return;
    final ia = k ~/ 100003, ib = k % 100003;
    if (ia >= verts.length || ib >= verts.length) return;
    final p1 = verts[ia], p2 = verts[ib];
    final u1 = (p1.x - minX) / w, v1 = (p1.z - minZ) / d;
    final u2 = (p2.x - minX) / w, v2 = (p2.z - minZ) / d;
    final len = math.sqrt((u2 - u1) * (u2 - u1) + (v2 - v1) * (v2 - v1));
    if (len < kSilLineMinLen || len > kSilLineMaxLen) return;
    final mu = (u1 + u2) / 2, mv = (v1 + v2) / 2;
    if (_polyDist(mu, mv, outerLoops) < kSilLineEdgeDist) return;
    if (_polyDist(u1, v1, outerLoops) < kSilLineEdgeDist) return;
    if (_polyDist(u2, v2, outerLoops) < kSilLineEdgeDist) return;
    cand.add([len, u1, v1, u2, v2, mu, mv]);
  });

  final nCand = cand.length;
  cand.sort((a, b) => b[0].compareTo(a[0]));
  final kept = <List<double>>[];
  for (final c in cand) {
    final dx0 = c[3] - c[1], dy0 = c[4] - c[2];
    final ln = math.sqrt(dx0 * dx0 + dy0 * dy0);
    if (ln < 1e-12) continue;
    final dx = dx0 / ln, dy = dy0 / ln;
    var dup = false;
    for (final k in kept) {
      if (math.sqrt((c[5] - k[5]) * (c[5] - k[5]) + (c[6] - k[6]) * (c[6] - k[6])) >=
          kSilLineMergeDist) {
        continue;
      }
      final kx0 = k[3] - k[1], ky0 = k[4] - k[2];
      final kln = math.sqrt(kx0 * kx0 + ky0 * ky0);
      if (kln < 1e-12) continue;
      if ((dx * kx0 / kln + dy * ky0 / kln).abs() > kSilLineMergeDot) {
        dup = true;
        break;
      }
    }
    if (dup) continue;
    kept.add(c);
    if (kept.length >= kSilLineMax) break;
  }
  return _Lines([for (final k in kept) _round4(k.sublist(1, 5))], nCand);
}

double _polyDist(double u, double v, List<List<double>> loops) {
  var best = 1e9;
  for (final loop in loops) {
    final n = loop.length ~/ 2;
    if (n < 3) continue;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final d = _segDist(u, v, loop[i * 2], loop[i * 2 + 1], loop[j * 2], loop[j * 2 + 1]);
      if (d < best) best = d;
    }
  }
  return best;
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  if (l2 < 1e-12) return math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay));
  var t = ((px - ax) * dx + (py - ay) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final qx = ax + t * dx, qy = ay + t * dy;
  return math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
}
