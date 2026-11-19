// P2：用户素材 2D 俯视轮廓入口 [ModelSilhouette.fromObjText] + 与 P1 生成器
// （tool/silhouette_gen.py）的一致性实测。
//
// 一致性实测值（m_furn_desk，2026-11 本机 debug/JIT）：
//   · Python 生成器 tool/silhouette_report.txt：316 面 / 188 顶点 →
//     外轮廓 8 点、0 孔、0 分隔线（note=无线）
//   · Dart ModelSilhouette.fromObjText：外轮廓 8 点、0 孔、0 分隔线，
//     bbox = Rect.fromLTRB(0, 0, 1, 1)，单次 ~20ms（JIT；闸上限 5000 面）
//   → 点数/环数/线数与生成数据同档，schema（0..1、u=宽 v=深、CCW）一致；
//     不要求逐点相同（栅格浮点顺序不同），但观感同构（都是「书桌外形 + 膝洞」）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/model_silhouettes.dart';

void main() {
  group('fromObjText 单元', () {
    test('盒子 → 4 点方形外轮廓、bbox≈[0,1]²、0 孔 0 线', () {
      final sil = ModelSilhouette.fromObjText(_boxObj(1.4, 0.6, 0.75));
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

    test('L 形台阶 → 单环 7~9 点（凹角不被 DP 吃掉）', () {
      final sil = ModelSilhouette.fromObjText(_prismObj(_stepShape, 0.8));
      expect(sil.outer.length, 1);
      expect(sil.outer.first.length ~/ 2, inInclusiveRange(7, 9));
      final b = silhouetteUvBounds(sil);
      expect(b.right, closeTo(1, 0.01));
      expect(b.bottom, closeTo(1, 0.01));
    });

    test('f 带 /vt/vn 后缀、负索引、多边形面 → 与纯 v/f 等价', () {
      final plain = ModelSilhouette.fromObjText(_boxObj(2.0, 1.0, 0.5));
      final fancy = ModelSilhouette.fromObjText(_boxObjFancy(2.0, 1.0, 0.5));
      expect(fancy.outer.length, plain.outer.length);
      expect(fancy.outer.first.length, plain.outer.first.length);
      expect(fancy.toJson(), plain.toJson());
    });

    test('有机/顶面杂乱（锯齿顶面）→ 外轮廓仍非空，分隔线整件跳过', () {
      final sil = ModelSilhouette.fromObjText(_sawtoothObj(20));
      expect(sil.outer, isNotEmpty);
      expect(sil.lines, isEmpty);
    });

    test('退化几何（平面片/空文本/垃圾行）→ tryFromObjText 宽容返回 null', () {
      // z 跨度为 0：2D 俯视没有面积，算不出轮廓（闸能收，但轮廓为 null）
      const plane = 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n';
      expect(ModelSilhouette.tryFromObjText(plane), isNull);
      expect(ModelSilhouette.tryFromObjText(''), isNull);
      expect(ModelSilhouette.tryFromObjText(null), isNull);
      expect(
        ModelSilhouette.tryFromObjText('# 只有注释\nvt 0.5 0.5\nvn 0 1 0\n'),
        isNull,
      );
      // 越界面索引（闸只数面数不校验引用）→ 该三角被丢，不抛 RangeError
      const badIdx = 'v 0 0 0\nv 1 0 0\nv 0 0 1\nf 1 2 9\n';
      expect(ModelSilhouette.tryFromObjText(badIdx), isNull);
    });
  });

  group('一致性：Dart 现算 vs Python 生成数据（m_furn_desk）', () {
    test('可解析 + 外轮廓非空 + bbox≈[0,1]±0.02 + 点数 ≤80 + 环/线数与生成报告同档', () {
      final obj = _objOf('m_furn_desk');
      final sw = Stopwatch()..start();
      final sil = ModelSilhouette.fromObjText(obj);
      sw.stop();

      // 可解析、外轮廓非空
      expect(sil.outer, isNotEmpty);
      // bbox 自检（生成器 BBOX_TOL=0.01，这里放宽到 0.02）
      final b = silhouetteUvBounds(sil);
      expect(b.left, closeTo(0, 0.02), reason: 'u min');
      expect(b.top, closeTo(0, 0.02), reason: 'v min');
      expect(b.right, closeTo(1, 0.02), reason: 'u max');
      expect(b.bottom, closeTo(1, 0.02), reason: 'v max');
      // 点数上限（kSilMaxOuterPts=80）
      for (final loop in sil.outer) {
        expect(loop.length ~/ 2, lessThanOrEqualTo(80));
        expect(loop.length % 2, 0);
        for (final c in loop) {
          expect(c, inInclusiveRange(0, 1));
        }
      }
      // 与 tool/silhouette_report.txt 同一行对照：m_furn_desk 8 / 0 / 0
      expect(sil.outer.length, 1, reason: '单块外形');
      expect(sil.outer.first.length ~/ 2, 8, reason: '书桌外形 8 点（膝洞内凹）');
      expect(sil.holes.length, 0);
      expect(sil.lines.length, 0, reason: '生成报告同件 note=无线');
      // 性能：≤5000 面闸内的导入件要毫秒级（JIT 实测 ~20ms；留 20 倍余量）
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'fromObjText 应在导入闸内毫秒级完成');
    });

    test('与生成表 IoU ≥0.90（同一套栅格/DP 参数，形状同构）', () {
      final sil = ModelSilhouette.fromObjText(_objOf('m_furn_desk'));
      final data = silhouetteFor('m_furn_desk')!;
      expect(_pathIoU(data, sil, 1.4, 0.591), greaterThanOrEqualTo(0.90));
    });
  });
}

// ---------------- 断言辅助 ----------------

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

/// 从 assets/web/models*.js 取某 id 的 OBJ 原文（"o" 字段 JSON 字符串）。
String _objOf(String id) {
  for (final path in const [
    'assets/web/models.js',
    'assets/web/models_ext.js',
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

// ---------------- 合成 OBJ ----------------

String _boxObj(double w, double d, double h) {
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

/// 同一个盒子，但面索引写成 `1/1/1` 形式 + 最后一组面用负索引 + 四边形面。
String _boxObjFancy(double w, double d, double h) {
  final v = [
    [0.0, 0.0, 0.0], [w, 0.0, 0.0], [w, 0.0, d], [0.0, 0.0, d],
    [0.0, h, 0.0], [w, h, 0.0], [w, h, d], [0.0, h, d],
  ];
  final b = StringBuffer();
  b.writeln('o test_box');
  b.writeln('vt 0 0');
  b.writeln('vn 0 1 0');
  for (final p in v) {
    b.writeln('v ${p[0]} ${p[1]} ${p[2]}');
  }
  // 底/顶（负索引，四边形扇形三角化）
  b.writeln('f -8 -5 -6 -7');
  b.writeln('f 5/1/1 6/1/1 7/1/1 8/1/1');
  // 侧墙（v//vn 形式）
  b.writeln('f 1//1 2//1 6//1 5//1');
  b.writeln('f 2//1 3//1 7//1 6//1');
  b.writeln('f 3//1 4//1 8//1 7//1');
  b.writeln('f 4//1 1//1 5//1 8//1');
  return b.toString();
}

/// 阶梯形多边形 [x,z]（0..1）：8 个角，两个凹口。
const _stepShape = [
  [0.0, 0.0], [1.0, 0.0], [1.0, 0.3], [0.6, 0.3],
  [0.6, 0.6], [0.3, 0.6], [0.3, 1.0], [0.0, 1.0],
];

String _prismObj(List<List<double>> poly, double h) {
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

/// 锯齿顶面：相邻斜板共享屋脊边（都上向但不同面）→ 候选线饱和。
String _sawtoothObj(int n) {
  final b = StringBuffer();
  final us = [for (var i = 0; i <= n; i++) i / n];
  for (var i = 0; i <= n; i++) {
    final y = i.isEven ? 0.50 : 0.55;
    b.writeln('v ${us[i]} $y 0');
    b.writeln('v ${us[i]} $y 0.8');
  }
  for (var i = 0; i < n; i++) {
    final a = i * 2 + 1, b2 = i * 2 + 3;
    b.writeln('f $a ${a + 1} ${b2 + 1}');
    b.writeln('f $a ${b2 + 1} $b2');
  }
  return b.toString();
}
