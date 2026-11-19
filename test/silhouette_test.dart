// 2D 俯视轮廓（P1）测试：算法单元 + 生成数据完整性 + 路径几何 + 方向校验。
//
// 方向校验的依据（读 assets/web/viewer.js 得出，注释在测试里写明，便于复核）：
//   · 俯视相机（applyPlan 的 top 分支，L1053-1056）：
//       camera.position.set(c.x, 25, c.z);
//       camera.up.set(0, 0, -1);
//       camera.lookAt(c);
//     three.js lookAt 推出相机局部 X = 世界 +X、局部 Y = 世界 -Z ⇒ 屏幕右 = +X、
//     屏幕下 = +Z。2D 画布 x 右、y 下，所以 (u,v) 直接映射到 (x,y) 不需要翻 v。
//   · 家具/素材旋转：buildItems 里 inst.rotation.y = -(rot*π/180)（L892、L914 等），
//     three.js 绕 Y 转 a 角的公式 (x cos a + z sin a, -x sin a + z cos a) 取 a=-θ
//     得 (x cosθ - z sinθ, x sinθ + z cosθ)，与 2D canvas.rotate(+θ)（屏幕 y 向下）
//     完全一致 —— 所以 2D 不必反向转。
// 下面 rotationIoU 的 3D 侧就是按这两条写的（three.js 语义，不借助 Flutter 的变换），
// 2D 侧用 Path.transform(M(θ))（等价 canvas.rotate）。两者 IoU 高 = 方向一致。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:jiajia/features/floorplan/domain/model_silhouettes.dart';

void main() {
  group('算法单元（Dart 参考实现）', () {
    test('单位盒 → 外轮廓 4 点方形、0 孔、0 线', () {
      final sil = buildSilhouetteFromObj(_objBox(1, 1, 1));
      expect(sil.outer.length, 1);
      expect(sil.outer.first.length ~/ 2, 4);
      expect(sil.holes, isEmpty);
      expect(sil.lines, isEmpty);
      final b = silhouetteUvBounds(sil);
      expect(b.left, closeTo(0, 0.01));
      expect(b.top, closeTo(0, 0.01));
      expect(b.right, closeTo(1, 0.01));
      expect(b.bottom, closeTo(1, 0.01));
    });

    test('阶梯 L 形（8 个角）→ 外轮廓 8 点', () {
      final sil = buildSilhouetteFromObj(_objPrism(_stepShape, 1.0));
      expect(sil.outer.length, 1);
      final n = sil.outer.first.length ~/ 2;
      expect(n, inInclusiveRange(7, 9),
          reason: '8 角折线在 128 栅格 + DP ε=0.5px 下应回到 8 点（允许 1 点残差）');
      final b = silhouetteUvBounds(sil);
      expect(b.left, closeTo(0, 0.01));
      expect(b.right, closeTo(1, 0.01));
      expect(b.top, closeTo(0, 0.01));
      expect(b.bottom, closeTo(1, 0.01));
    });

    test('已知孔洞 → 1 个孔、孔心不填充、外形仍是 4 点', () {
      final sil = buildSilhouetteFromObj(_objRing(0.35, 0.65));
      expect(sil.outer.length, 1);
      expect(sil.outer.first.length ~/ 2, 4);
      expect(sil.holes.length, 1);
      final path = buildSilhouettePath(sil, 100, 100);
      expect(path.contains(const Offset(0, 0)), isFalse,
          reason: '孔心应被挖空');
      expect(path.contains(const Offset(-45, -45)), isTrue,
          reason: '环体应填充');
    });

    test('顶面杂乱（锯齿顶面，分隔线饱和）→ lines 整件为空', () {
      final sil = buildSilhouetteFromObj(_objSawtooth(20));
      expect(sil.outer, isNotEmpty);
      expect(sil.lines, isEmpty,
          reason: 'cand 多到线数饱和（≥16）时按「顶面杂乱」整件跳过');
    });
  });

  group('生成数据完整性', () {
    test('条目数 76：floor 摆放类，不含门窗', () {
      expect(modelSilhouettes.length, 76);
      for (final k in modelSilhouettes.keys) {
        expect(k.startsWith('m_door'), isFalse, reason: '$k 是门，不该生成');
        expect(k.startsWith('m_window'), isFalse, reason: '$k 是窗，不该生成');
      }
      // 三条内置门（models.js 1001/1003/1006）也不该出现
      expect(modelSilhouettes.containsKey('1001'), isFalse);
      expect(modelSilhouettes.containsKey('1003'), isFalse);
      expect(modelSilhouettes.containsKey('1006'), isFalse);
    });

    test('每条 u/v ∈[0,1]、外轮廓点数 ≤80、孔 ≤40、线是 4 元组', () {
      modelSilhouettes.forEach((id, raw) {
        final s = ModelSilhouette.fromJson(raw);
        expect(s.outer, isNotEmpty, reason: '$id 缺外轮廓');
        for (final loop in s.outer) {
          expect(loop.length % 2, 0, reason: '$id 外形不是 u,v 成对');
          expect(loop.length ~/ 2, lessThanOrEqualTo(80), reason: '$id 外形点超 80');
          expect(loop.length ~/ 2, greaterThanOrEqualTo(3), reason: '$id 外形点不足');
          _expectUnit(loop, '$id 外形');
        }
        for (final loop in s.holes) {
          expect(loop.length % 2, 0, reason: '$id 孔不是 u,v 成对');
          expect(loop.length ~/ 2, lessThanOrEqualTo(40), reason: '$id 孔点超 40');
          _expectUnit(loop, '$id 孔');
        }
        for (final seg in s.lines) {
          expect(seg.length, 4, reason: '$id 线段不是 u1,v1,u2,v2');
          _expectUnit(seg, '$id 线段');
        }
      });
    });

    test('生成文件 < 400KB，且带「勿手改」头', () {
      final f = File('lib/features/floorplan/domain/model_silhouettes.dart');
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), lessThan(400 * 1024),
          reason: '超出体积护栏就要收紧 DP ε / 线条上限后重跑生成器');
      expect(f.readAsStringSync().contains('由 tool/silhouette_gen.py 生成，勿手改'),
          isTrue);
    });

    test('典型件轮廓形状：柜板是矩形、床 4 角、花卉有孔', () {
      // 1005 柜板 0.9×0.15：规整矩形
      expect(modelSilhouettes['1005']!['o'][0].length, 8);
      // 床：矩形外轮廓
      final bed = silhouetteFor('m_furn_bed')!;
      expect(bed.outer.first.length ~/ 2, 4);
      // 插花：花瓶口/枝叶之间会留孔
      final flowers = silhouetteFor('m_furn_flowers')!;
      expect(flowers.holes, isNotEmpty);
    });

    test('silhouetteFor：未知 id / null → null，重复调用命中缓存', () {
      expect(silhouetteFor(null), isNull);
      expect(silhouetteFor('nope_not_a_model'), isNull);
      expect(identical(silhouetteFor('m_furn_bed'), silhouetteFor('m_furn_bed')),
          isTrue);
    });
  });

  group('buildSilhouettePath 几何', () {
    test('外轮廓铺满居中框（与旧 RRect 同一个框）', () {
      final s = silhouetteFor('1005')!;
      final p = buildSilhouettePath(s, 90, 30);
      final b = p.getBounds();
      expect(b.left, closeTo(-45, 0.01));
      expect(b.right, closeTo(45, 0.01));
      expect(b.top, closeTo(-15, 0.01));
      expect(b.bottom, closeTo(15, 0.01));
    });

    test('内部线映射到同一框内，端点可复算', () {
      final s = silhouetteFor('m_furn_dresser')!;
      expect(s.lines, isNotEmpty, reason: '斗柜应有顶面分隔线');
      final p = buildSilhouetteLinesPath(s, 100, 50);
      expect(p, isNotNull);
      final seg = s.lines.first;
      final want = Offset((seg[0] - 0.5) * 100, (seg[1] - 0.5) * 50);
      // 用 PathMetrics 取出第一段起点
      final m = p!.computeMetrics().first;
      final got = m.getTangentForOffset(0)!.position;
      expect(got.dx, closeTo(want.dx, 0.01));
      expect(got.dy, closeTo(want.dy, 0.01));
    });

    test('无线件的 lines 路径为 null（省一次 drawPath）', () {
      final s = silhouetteFor('1005')!;
      expect(buildSilhouetteLinesPath(s, 100, 50), isNull);
    });
  });

  group('方向校验（3D 俯视 vs 2D 画布）', () {
    // 矩形对称件（柜板/床）翻不翻 v 都一样，必须用明显不对称的件：
    // 露台椅的椅背在一侧、书桌有膝洞。
    for (final id in ['m_courtyard_chair', 'm_furn_desk']) {
      test('$id：rot 0/90/180/270 下 3D 俯视投影的顶点全部落在 2D 轮廓里', () {
        final sil = silhouetteFor(id)!;
        final mesh = _readMesh(id);
        for (final rot in const [0.0, 90.0, 180.0, 270.0]) {
          final cov = _outlineCoverage(sil, mesh, rot);
          expect(cov, greaterThanOrEqualTo(0.99),
              reason: '$id rot=$rot：2D 轮廓必须包住俯视投影'
                  '（3D rotation.y=-θ 与 canvas.rotate(+θ) 同向，见文件头依据）');
        }
      });
    }

    test('露台椅：椅背（高顶点）落在 v≈0.26 一侧 → 2D 画在上半（v<0.5）', () {
      // 椅背是整件最高的一片，取 y > 0.75*maxY 的顶点质心定位它所在的 v 侧。
      final mesh = _readMesh('m_courtyard_chair');
      var maxY = -1e9;
      for (final v in mesh.vs) {
        maxY = math.max(maxY, v.y);
      }
      var n = 0;
      var sumV = 0.0;
      for (final v in mesh.vs) {
        if (v.y <= 0.75 * maxY) continue;
        sumV += (v.z - mesh.minZ) / mesh.bboxD;
        n++;
      }
      final backV = sumV / n;
      // 依据：v=(z-minZ)/d 随 Z 增大；top 视图屏幕下 = +Z（viewer.js L1053-1056），
      // 2D 的 y=(v-0.5)*fd 也向下。这把椅子的椅背实测在 Z 小的一侧（v≈0.26），
      // 所以 2D 上必须画在画布上半：若生成器把 v 翻过来，这里和覆盖率都会挂。
      expect(backV, lessThan(0.4), reason: '椅背应在 v<0.5 一侧（-Z / 画布上）');
      final sil = silhouetteFor('m_courtyard_chair')!;
      final path = buildSilhouettePath(sil, 1.0, 1.0);
      expect(path.contains(Offset(0, (backV - 0.5))), isTrue,
          reason: '椅背侧应落在 2D 轮廓内');
    });

    test('露台椅：把 v 轴翻过来后覆盖率明显下降（证明该用例能测出翻转）', () {
      final mesh = _readMesh('m_courtyard_chair');
      final good = _outlineCoverage(silhouetteFor('m_courtyard_chair')!, mesh, 0);
      final bad = _outlineCoverage(_flipModel(silhouetteFor('m_courtyard_chair')!), mesh, 0);
      expect(good, greaterThanOrEqualTo(0.99));
      expect(bad, lessThan(0.9), reason: '翻转 v 后椅背会跑到反侧，覆盖率应掉下来');
    });
  });

  group('生成数据 vs Dart 算法（同参数一致性）', () {
    for (final id in ['m_furn_bed', 'm_furn_dresser', '1005']) {
      test('$id：Dart 现算轮廓与生成数据 IoU ≥0.90', () {
        final w = _readMesh(id).bboxW, d = _readMesh(id).bboxD;
        final data = silhouetteFor(id)!;
        final dart = buildSilhouetteFromObj(_objOf(id));
        expect(_pathIoU(data, dart, w, d), greaterThanOrEqualTo(0.90),
            reason: '$id 生成器（Python）与 Dart 参考实现的栅格/DP 结果应一致');
      });
    }
  });
}

// ---------------- 断言辅助 ----------------

void _expectUnit(List<double> flat, String what) {
  for (final c in flat) {
    expect(c, inInclusiveRange(-0.0001, 1.0001), reason: '$what 越界（$c）');
  }
}

List<double> _flipV(List<double> loop) =>
    [for (var i = 0; i < loop.length; i++) i.isEven ? loop[i] : 1 - loop[i]];

// ---------------- 3D 侧：按 viewer.js 语义投影 ----------------

class _Mesh {
  final List<SilVec3> vs;
  final List<SilTri> ts;
  final double minX, maxX, minZ, maxZ;
  _Mesh(this.vs, this.ts, this.minX, this.maxX, this.minZ, this.maxZ);
  double get bboxW => maxX - minX;
  double get bboxD => maxZ - minZ;
  double get cx => (minX + maxX) / 2;
  double get cz => (minZ + maxZ) / 2;
}

/// 读 assets/web/models*.js 里某 id 的 OBJ 文本（"o":"..." JSON 字符串）。
_Mesh _readMesh(String id) {
  final obj = _objOf(id);
  final vs = <SilVec3>[];
  final ts = <SilTri>[];
  for (final raw in obj.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('v ')) {
      final p = line.split(RegExp(r'\s+'));
      vs.add(SilVec3(double.parse(p[1]), double.parse(p[2]), double.parse(p[3])));
    } else if (line.startsWith('f ')) {
      final idx = [
        for (final a in line.split(RegExp(r'\s+')).skip(1))
          int.parse(a.split('/').first) - 1
      ];
      for (var k = 1; k < idx.length - 1; k++) {
        ts.add(SilTri(idx[0], idx[k], idx[k + 1]));
      }
    }
  }
  var minX = double.infinity, maxX = -double.infinity;
  var minZ = double.infinity, maxZ = -double.infinity;
  for (final v in vs) {
    minX = math.min(minX, v.x);
    maxX = math.max(maxX, v.x);
    minZ = math.min(minZ, v.z);
    maxZ = math.max(maxZ, v.z);
  }
  return _Mesh(vs, ts, minX, maxX, minZ, maxZ);
}

String _objOf(String id) {
  for (final path in const [
    'assets/web/models.js',
    'assets/web/models_ext.js'
  ]) {
    final text = File(path).readAsStringSync();
    final at = text.indexOf('"$id":{');
    if (at < 0) continue;
    final k = text.indexOf('"o":"', at);
    if (k < 0) throw StateError('$id 没有 o 字段');
    var i = k + 5;
    final buf = StringBuffer();
    while (i < text.length) {
      final ch = text[i];
      if (ch == '\\') {
        buf.write(text.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (ch == '"') break;
      buf.write(ch);
      i++;
    }
    return jsonDecode('"${buf.toString()}"') as String;
  }
  throw StateError('找不到模型 $id');
}

/// 3D 俯视投影的顶点有多少落在 2D 轮廓里（含 2% 边距容差）。
///
/// 3D 侧完全按 viewer.js 语义算，不借用 Flutter 的变换：
///   p_local = ((x-cx)*fw/w, (z-cz)*fd/d)       ← buildItems 的 sw/md.w 缩放
///   three.js rotation.y = -θ（L892/L914）：(x cos a + z sin a, -x sin a + z cos a)
/// 2D 侧：buildSilhouettePath + Path.transform(M(θ))（等价 Canvas.rotate(θ)）。
double _outlineCoverage(ModelSilhouette sil, _Mesh mesh, double rotDeg) {
  final w = mesh.bboxW, d = mesh.bboxD;
  final fw = w, fd = d;
  final th = rotDeg * math.pi / 180;
  final c = math.cos(th), s = math.sin(th);
  final path = buildSilhouettePath(sil, fw, fd).transform(Float64List.fromList([
    c, s, 0, 0, //
    -s, c, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]));
  final eps = 0.02 * math.max(fw, fd);
  var inside = 0;
  for (final v in mesh.vs) {
    final xl = (v.x - mesh.cx) / w * fw;
    final zl = (v.z - mesh.cz) / d * fd;
    final a = -th;
    final x = xl * math.cos(a) + zl * math.sin(a);
    final z = -xl * math.sin(a) + zl * math.cos(a);
    var ok = path.contains(Offset(x, z));
    if (!ok) {
      for (final dx in const [-1.0, 0.0, 1.0]) {
        for (final dy in const [-1.0, 0.0, 1.0]) {
          if (path.contains(Offset(x + dx * eps, z + dy * eps))) {
            ok = true;
            break;
          }
        }
        if (ok) break;
      }
    }
    if (ok) inside++;
  }
  return inside / mesh.vs.length;
}

ModelSilhouette _flipModel(ModelSilhouette s) => ModelSilhouette(
      outer: [for (final l in s.outer) _flipV(l)],
      holes: [for (final l in s.holes) _flipV(l)],
      lines: const [],
    );

/// 两个轮廓的占用重合度（同尺寸居中框，不旋转）。
double _pathIoU(ModelSilhouette a, ModelSilhouette b, double fw, double fd) {
  const n = 24;
  final pa = buildSilhouettePath(a, fw, fd);
  final pb = buildSilhouettePath(b, fw, fd);
  var inter = 0, union = 0;
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final p = Offset(-fw / 2 + (i + 0.5) * fw / n, -fd / 2 + (j + 0.5) * fd / n);
      final ina = pa.contains(p), inb = pb.contains(p);
      if (ina && inb) inter++;
      if (ina || inb) union++;
    }
  }
  return union == 0 ? 0 : inter / union;
}

// ---------------- 合成 OBJ（算法单元用） ----------------

String _objBox(double w, double d, double h) {
  final v = [
    [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0], [0.0, 0.0, 1.0],
    [0.0, 1.0, 0.0], [1.0, 1.0, 0.0], [1.0, 1.0, 1.0], [0.0, 1.0, 1.0],
  ];
  for (final p in v) {
    p[0] = p[0] * w;
    p[1] = p[1] * h;
    p[2] = p[2] * d;
  }
  final faces = [
    [1, 4, 3, 2], [5, 6, 7, 8], // 底/顶
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

/// 阶梯形多边形 [x,z]（0..1）：8 个角，两个凹口，专测 DP 会不会吃掉凹角。
const _stepShape = [
  [0.0, 0.0], [1.0, 0.0], [1.0, 0.3], [0.6, 0.3],
  [0.6, 0.6], [0.3, 0.6], [0.3, 1.0], [0.0, 1.0],
];

/// 多边形棱柱：底 y=0、顶 y=h，顶/底扇形三角化 + 侧墙。
String _objPrism(List<List<double>> poly, double h) {
  final b = StringBuffer();
  for (final p in poly) {
    b.writeln('v ${p[0]} 0 ${p[1]}');
  }
  for (final p in poly) {
    b.writeln('v ${p[0]} $h ${p[1]}');
  }
  final n = poly.length;
  for (var k = 1; k < n - 1; k++) {
    b.writeln('f ${k + 1} ${k + 2} 1');
    b.writeln('f ${n + 1} ${n + k + 2} ${n + k + 1}');
  }
  for (var k = 0; k < n; k++) {
    final j = (k + 1) % n;
    b.writeln('f ${k + 1} ${j + 1} ${n + j + 1}');
    b.writeln('f ${k + 1} ${n + j + 1} ${n + k + 1}');
  }
  return b.toString();
}

/// 方形环（中间留方孔）：孔洞面积占比 = (hi-lo)²。
String _objRing(double lo, double hi) {
  final quads = <List<List<double>>>[];
  void quad(double x0, double z0, double x1, double z1) {
    quads.add([
      [x0, z0], [x1, z0], [x1, z1], [x0, z1],
    ]);
  }

  quad(0, 0, 1, lo); // 下
  quad(0, hi, 1, 1); // 上
  quad(0, lo, lo, hi); // 左
  quad(hi, lo, 1, hi); // 右
  final b = StringBuffer();
  var base = 0;
  for (final q in quads) {
    for (final p in q) {
      b.writeln('v ${p[0]} 0 ${p[1]}');
    }
    b.writeln('v ${q[0][0]} 1 ${q[0][1]}');
    b.writeln('v ${q[1][0]} 1 ${q[1][1]}');
    b.writeln('v ${q[2][0]} 1 ${q[2][1]}');
    b.writeln('v ${q[3][0]} 1 ${q[3][1]}');
    // 顶面
    b.writeln('f ${base + 5} ${base + 6} ${base + 7}');
    b.writeln('f ${base + 5} ${base + 7} ${base + 8}');
    // 底面
    b.writeln('f ${base + 1} ${base + 3} ${base + 2}');
    b.writeln('f ${base + 1} ${base + 4} ${base + 3}');
    // 侧墙
    for (var k = 0; k < 4; k++) {
      final j = (k + 1) % 4;
      b.writeln('f ${base + k + 1} ${base + j + 1} ${base + j + 5}');
      b.writeln('f ${base + k + 1} ${base + j + 5} ${base + k + 5}');
    }
    base += 8;
  }
  return b.toString();
}

/// 锯齿顶面：n 条沿 u 的斜板，相邻板共享屋脊边（法线都朝上但不同）。
/// 用来触发「候选分隔线饱和 → 顶面杂乱整件跳过」。
String _objSawtooth(int n) {
  final b = StringBuffer();
  final us = [for (var i = 0; i <= n; i++) i / n];
  for (var i = 0; i <= n; i++) {
    final y = i.isEven ? 0.50 : 0.55;
    b.writeln('v ${us[i]} $y 0');
    b.writeln('v ${us[i]} $y 0.8');
  }
  for (var i = 0; i < n; i++) {
    final a = i * 2 + 1, b2 = i * 2 + 3; // a..a+1 是 (u_i,0)/(u_i,0.8)
    b.writeln('f $a ${a + 1} ${b2 + 1}');
    b.writeln('f $a ${b2 + 1} $b2');
  }
  return b.toString();
}
