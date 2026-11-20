// v0.1.44：用户模型超闸自动减面（顶点聚类）——单测。
//
// 场景：8.8MB 的 japaneseMaple.obj（十万级面）被 300KB/5000 面闸拒；用户要
// 「太大你可以压缩一下」→ 导入时先减面再按同一道闸入库，闸本身不放宽。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/obj_decimate.dart';
import 'package:jiajia/features/floorplan/domain/obj_parse.dart';

/// 起伏网格：nx × ny 个格子，每格两个三角（f 行数 = nx*ny*2）。
/// 尺寸 [w]×[d]，高度按正弦起伏（0..h），保证不是纯平面也非退化。
String _gridObj({
  required int nx,
  required int ny,
  double w = 2.0,
  double d = 2.0,
  double h = 0.4,
}) {
  final b = StringBuffer();
  final cols = nx + 1;
  final rows = ny + 1;
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final x = w * i / nx;
      final z = d * j / ny;
      final y = h *
          (0.5 + 0.5 * math.sin(6.28318 * i / nx) * math.cos(6.28318 * j / ny));
      b.writeln('v ${x.toStringAsFixed(5)} ${y.toStringAsFixed(5)} '
          '${z.toStringAsFixed(5)}');
    }
  }
  int vid(int i, int j) => j * cols + i + 1; // 1 基
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final a = vid(i, j), bb = vid(i + 1, j);
      final c = vid(i + 1, j + 1), dd = vid(i, j + 1);
      b.writeln('f $a $bb $c');
      b.writeln('f $a $c $dd');
    }
  }
  return b.toString();
}

void main() {
  test('2 万面网格 → 减到 ≤4800 面、无退化面、bbox 沿用原始、文本 ≤300KB', () {
    final srcText = _gridObj(nx: 100, ny: 100); // 10000 格 ×2 = 20000 面
    final src = ObjParser.parse(srcText);
    expect(src.faceCount, 20000);

    final dec = ObjDecimate.tryDecimate(src);
    expect(dec.changed, isTrue);
    expect(dec.fromFaces, 20000);
    expect(dec.toFaces, lessThanOrEqualTo(4800));
    expect(dec.objText.length, lessThanOrEqualTo(ObjParser.maxChars));

    // bbox 用减面前的原始值（渲染尺寸不因减面变化）
    expect(dec.data.bboxW, closeTo(src.bboxW, 1e-6));
    expect(dec.data.bboxD, closeTo(src.bboxD, 1e-6));
    expect(dec.data.bboxH, closeTo(src.bboxH, 1e-6));
    expect(dec.data.wMm, src.wMm);

    // 输出可再解析；无退化面（重复索引 / 零面积）
    final back = ObjParser.parse(dec.objText);
    expect(back.faceCount, dec.toFaces);
    expect(back.vertexCount, dec.data.vertexCount);
    expect(back.tris.length ~/ 3, dec.toFaces);
    final v = back.verts;
    for (var i = 0; i < back.tris.length; i += 3) {
      final a = back.tris[i], b = back.tris[i + 1], c = back.tris[i + 2];
      expect(a == b || b == c || a == c, isFalse, reason: '重复索引面');
      final ux = v[b * 3] - v[a * 3];
      final uy = v[b * 3 + 1] - v[a * 3 + 1];
      final uz = v[b * 3 + 2] - v[a * 3 + 2];
      final wx = v[c * 3] - v[a * 3];
      final wy = v[c * 3 + 1] - v[a * 3 + 1];
      final wz = v[c * 3 + 2] - v[a * 3 + 2];
      final cx = uy * wz - uz * wy;
      final cy = uz * wx - ux * wz;
      final cz = ux * wy - uy * wx;
      expect(cx * cx + cy * cy + cz * cz, greaterThan(0), reason: '零面积面');
    }
    // 输出只有 v / f（vt/vn/usemtl 不参与渲染，全部剥掉）
    expect(dec.objText, isNot(contains('usemtl')));
    expect(dec.objText, isNot(contains('vt ')));
    expect(dec.objText, isNot(contains('vn ')));
  });

  test('已 ≤5000 面且 ≤300KB 的输入 → changed=false，原样透传', () {
    final srcText = _gridObj(nx: 20, ny: 20, w: 1.2, d: 0.7, h: 0.75);
    final src = ObjParser.parse(srcText);
    expect(src.faceCount, lessThanOrEqualTo(ObjParser.maxFaces));
    final dec = ObjDecimate.tryDecimate(src);
    expect(dec.changed, isFalse);
    expect(dec.objText, same(srcText));
    expect(dec.toFaces, src.faceCount);
    expect(identical(dec.data, src), isTrue);
  });

  test('退化输入（所有面共线 → 焊接后全零面积）→ 不崩、返回 0 面', () {
    // 手工构造 ObjData：bbox 有跨度（parse 能收），几何全在一条线上
    final verts = <double>[0, 0, 0, 10, 0, 0];
    final tris = <int>[];
    for (var i = 0; i < 6000; i++) {
      tris.addAll([0, 1, 0]);
    }
    final src = ObjData(
      vertexCount: 2,
      faceCount: 6000,
      bboxW: 10,
      bboxD: 0,
      bboxH: 0,
      text: 'v 0 0 0\nv 10 0 0\n${'f 1 2 1\n' * 6000}',
      verts: verts,
      tris: tris,
    );
    final dec = ObjDecimate.tryDecimate(src);
    expect(dec.changed, isTrue);
    expect(dec.toFaces, 0);
    expect(dec.objText, isEmpty);
    // 0 面文本再过闸必然被拒（流程侧给「压缩后模型退化」文案）
    expect(() => ObjParser.gate(dec.objText), throwsA(isA<ObjParseException>()));
  });

  test('性能：10 万面输入减面 <1s（粗粒度计时）', () {
    final srcText = _gridObj(nx: 224, ny: 224); // 100352 面
    final t0 = DateTime.now();
    final src = ObjParser.parse(srcText);
    final parseMs = DateTime.now().difference(t0).inMilliseconds;
    expect(src.faceCount, greaterThan(100000));

    final t1 = DateTime.now();
    final dec = ObjDecimate.tryDecimate(src);
    final decMs = DateTime.now().difference(t1).inMilliseconds;
    // ignore: avoid_print
    print('PERF parse=${parseMs}ms text=${srcText.length} '
        'decimate=${decMs}ms out=${dec.objText.length} '
        'faces ${dec.fromFaces}->${dec.toFaces} levels=${ObjDecimate.gridSteps}');
    expect(decMs, lessThan(1000));
    expect(dec.toFaces, lessThanOrEqualTo(4800));
  });
}
