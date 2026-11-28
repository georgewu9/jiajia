// 外部 OBJ 模型导入：只做「校验 + 包围盒 (+ 减面所需的轻量几何)」，不深解析面片。
//
// 几何三角化/材质分组/归一化缩放仍由 assets/web/viewer.js 的 parseOBJ 负责：
// 3D 端同一份 OBJ 文本喂给同一条 JS 管线（不引入新 loader），Dart 只回答
// 四个问题——能不能收（体积/面数/顶点）、尺寸多大（bbox，供对话框预填 mm）、
// 值不值得入库（空面片/畸形行直接拒）、超闸时能不能减面（顶点+三角面）。
//
// 约定：OBJ 坐标单位按「米」解释（与 app 内置 MODEL 的 w/d/h 一致）；
// 用户导入后可在对话框里把 mm 改掉，2D/3D 都按改后的尺寸 fit。
//
// v0.1.44：parse 的硬上限放大到 10MB 文本 / 20 万面（用户大模型导入时先
// 收进来再减面）；「直接入库」的 300KB/5000 面闸只剩 [ObjParser.gate]：
// JSON 单件/批量导入仍走它，OBJ 流程 parse → 超闸减面 → 再过闸。

import '../../../app/i18n.dart';

/// 校验失败（消息可直接进 SnackBar）。
class ObjParseException implements Exception {
  /// 面向用户的中文原因（含实际值与上限）。
  final String message;
  const ObjParseException(this.message);

  @override
  String toString() => message;
}

/// 通过校验的 OBJ 摘要：顶点/面计数 + 包围盒尺寸（米）+ 减面用几何。
///
/// [text]/[verts]/[tris] 是 v0.1.44 加的：导入流程超闸时把它交给
/// [ObjDecimate.tryDecimate] 重建拓扑；未超闸时 [text] 原样入库（零改动）。
class ObjData {
  final int vertexCount;
  final int faceCount;

  /// 包围盒宽（X 轴跨度，米）。
  final double bboxW;

  /// 包围盒深（Z 轴跨度，米）。
  final double bboxD;

  /// 包围盒高（Y 轴跨度，米）。
  final double bboxH;

  /// 原始 OBJ 文本（Dart String 不可变，这里只是引用，不复制内存）。
  final String text;

  /// 顶点坐标扁平数组 `[x0,y0,z0,x1,...]`（米，与 [text] 的 `v` 行同序、只含合法行）。
  final List<double> verts;

  /// 三角面扁平索引 `[a0,b0,c0,a1,...]`（0 基；多边形 `f` 按扇形三角化；
  /// 越界/负索引的三角已剔除）。仅供减面器使用，渲染仍走 JS。
  final List<int> tris;

  const ObjData({
    required this.vertexCount,
    required this.faceCount,
    required this.bboxW,
    required this.bboxD,
    required this.bboxH,
    this.text = '',
    this.verts = const <double>[],
    this.tris = const <int>[],
  });

  int get wMm => (bboxW * 1000).round();
  int get dMm => (bboxD * 1000).round();
  int get hMm => (bboxH * 1000).round();
}

class ObjParser {
  const ObjParser._();

  /// 「直接入库」文本上限（字符，v0.1.38 的导入闸；不放宽）。
  static const int maxChars = 300000;

  /// 「直接入库」面数上限（OBJ 的 `f` 行计数；不放宽）。
  static const int maxFaces = 5000;

  /// 解析硬上限：10MB 文本。超过说明选错文件（视频/整套包），不算「大模型」。
  /// 8.8MB 的 japaneseMaple.obj 在这里放行，进减面器。
  static const int maxParseChars = 10 * 1024 * 1024;

  /// 解析硬上限：20 万面（f 行）。再大纯 Dart 减面也救不回手机内存。
  static const int maxParseFaces = 200000;

  /// 解析并校验 [text]；不合法抛 [ObjParseException]。
  ///
  /// 只做**硬上限**（10MB/20 万面）+ 语义校验 + bbox + 几何收集；
  /// 300KB/5000 面入库闸在 [gate]。
  static ObjData parse(String text) {
    if (text.length > maxParseChars) {
      throw ObjParseException(
        t('obj_too_large', args: [text.length, maxParseChars ~/ (1024 * 1024)]),
      );
    }

    var vertexCount = 0;
    var faceCount = 0;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;

    // 减面用几何：v 行的坐标与 f 行扇形三角化后的索引（0 基）。
    final verts = <double>[];
    final tris = <int>[];

    final lines = text.split('\n');
    // 逐行宽松解析：畸形行（缺分量/非数字/未知指令）直接跳过，不抛异常——
    // 真实导出文件常带注释、空行、扩展指令（vn/vt/g/s/o/l），不能因此拒收。
    // 手工扫描空白（不用 RegExp split / trim）：8.8MB 十万行文本要走 O(n)，
    // 正则逐行切分在 VM 上会吃掉几百 ms。
    for (final line in lines) {
      final len = line.length;
      var p = 0;
      while (p < len) {
        final c = line.codeUnitAt(p);
        if (c != 0x20 && c != 0x09 && c != 0x0D) break;
        p++;
      }
      if (p >= len) continue;
      final tag = line.codeUnitAt(p);
      if (tag == 0x23) continue; // '#'
      if (tag == 0x76 /* v */ || tag == 0x66 /* f */) {
        // 指令必须独占一个 token（"vertex ..." 不算 v 行）
        if (p + 1 < len) {
          final nx = line.codeUnitAt(p + 1);
          if (nx != 0x20 && nx != 0x09 && nx != 0x0D) continue;
        }
        if (tag == 0x76) {
          // v x y z [w]：只取前三个分量
          double? x, y, z;
          var q = p + 1;
          for (var k = 0; k < 3; k++) {
            while (q < len) {
              final c = line.codeUnitAt(q);
              if (c != 0x20 && c != 0x09 && c != 0x0D) break;
              q++;
            }
            if (q >= len) break;
            final start = q;
            while (q < len) {
              final c = line.codeUnitAt(q);
              if (c == 0x20 || c == 0x09 || c == 0x0D) break;
              q++;
            }
            final d = double.tryParse(line.substring(start, q));
            if (k == 0) {
              x = d;
            } else if (k == 1) {
              y = d;
            } else {
              z = d;
            }
          }
          if (x == null || y == null || z == null) continue;
          if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
          vertexCount++;
          verts
            ..add(x)
            ..add(y)
            ..add(z);
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          if (z < minZ) minZ = z;
          if (z > maxZ) maxZ = z;
        } else {
          // f：顶点索引允许 `1`、`1/2`、`1//3`、`1/2/3`、负索引；
          // 只认「有 ≥3 个可解析索引」的面，畸形行不计也不报错。
          final idx = <int>[];
          var q = p + 1;
          while (q < len) {
            while (q < len) {
              final c = line.codeUnitAt(q);
              if (c != 0x20 && c != 0x09 && c != 0x0D) break;
              q++;
            }
            if (q >= len) break;
            final start = q;
            var slash = -1;
            while (q < len) {
              final c = line.codeUnitAt(q);
              if (c == 0x20 || c == 0x09 || c == 0x0D) break;
              if (c == 0x2F && slash < 0) slash = q; // '/'
              q++;
            }
            final n = int.tryParse(
              line.substring(start, slash >= 0 ? slash : q),
            );
            if (n == null) continue;
            // 负索引相对「当前已读顶点数」（OBJ 语义）
            final zero = n > 0 ? n - 1 : vertexCount + n;
            idx.add(zero);
          }
          if (idx.length < 3) continue;
          faceCount++;
          if (faceCount > maxParseFaces) {
            throw ObjParseException(
              t('obj_face_limit', args: [faceCount, maxParseFaces]),
            );
          }
          // 扇形三角化（与 viewer.js parseOBJ / silhouette 的 f 处理一致）
          for (var k = 1; k < idx.length - 1; k++) {
            tris
              ..add(idx[0])
              ..add(idx[k])
              ..add(idx[k + 1]);
          }
        }
      }
    }

    if (vertexCount == 0) {
      throw ObjParseException(t('obj_no_vertices'));
    }
    if (faceCount == 0) {
      throw ObjParseException(t('obj_no_faces'));
    }

    final w = maxX - minX;
    final d = maxZ - minZ;
    final h = maxY - minY;
    if (w <= 0 && d <= 0 && h <= 0) {
      throw ObjParseException(t('obj_empty_bbox'));
    }

    // 越界索引的三角剔除（闸只数面数/顶点，不校验引用；渲染侧各自跳过）。
    var triOk = true;
    for (var i = 0; i < tris.length; i += 3) {
      final a = tris[i], b = tris[i + 1], c = tris[i + 2];
      if (a < 0 || b < 0 || c < 0 || a >= vertexCount || b >= vertexCount ||
          c >= vertexCount) {
        triOk = false;
        break;
      }
    }
    final cleanTris = triOk ? tris : _dropBadTris(tris, vertexCount);

    return ObjData(
      vertexCount: vertexCount,
      faceCount: faceCount,
      bboxW: w,
      bboxD: d,
      bboxH: h,
      text: text,
      verts: verts,
      tris: cleanTris,
    );
  }

  /// 入库闸（300KB 文本 / 5000 面）：**只给「直接入库」用**（单件 JSON /
  /// 全量导入 / 旧条目补 bbox）。OBJ 导入流程先 [parse]，超闸再减面。
  static ObjData gate(String text) {
    if (text.length > maxChars) {
      throw ObjParseException(t('obj_too_large_chars', args: [text.length, maxChars]));
    }
    final data = parse(text);
    if (data.faceCount > maxFaces) {
      throw ObjParseException(t('obj_face_limit_short', args: [data.faceCount, maxFaces]));
    }
    return data;
  }

  static List<int> _dropBadTris(List<int> tris, int vertexCount) {
    final out = <int>[];
    for (var i = 0; i + 2 < tris.length; i += 3) {
      final a = tris[i], b = tris[i + 1], c = tris[i + 2];
      if (a < 0 || b < 0 || c < 0) continue;
      if (a >= vertexCount || b >= vertexCount || c >= vertexCount) continue;
      out
        ..add(a)
        ..add(b)
        ..add(c);
    }
    return out;
  }
}
