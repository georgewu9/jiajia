// 外部 OBJ 模型导入：只做「校验 + 包围盒」，不深解析面片。
//
// 几何三角化/材质分组/归一化缩放仍由 assets/web/viewer.js 的 parseOBJ 负责：
// 3D 端同一份 OBJ 文本喂给同一条 JS 管线（不引入新 loader），Dart 只回答
// 三个问题——能不能收（体积/面数/顶点）、尺寸多大（bbox，供对话框预填 mm）、
// 值不值得入库（空面片/畸形行直接拒）。
//
// 约定：OBJ 坐标单位按「米」解释（与 app 内置 MODEL 的 w/d/h 一致）；
// 用户导入后可在对话框里把 mm 改掉，2D/3D 都按改后的尺寸 fit。

/// 校验失败（消息可直接进 SnackBar）。
class ObjParseException implements Exception {
  /// 面向用户的中文原因（含实际值与上限）。
  final String message;
  const ObjParseException(this.message);

  @override
  String toString() => message;
}

/// 通过校验的 OBJ 摘要：顶点/面计数 + 包围盒尺寸（米）。
class ObjData {
  final int vertexCount;
  final int faceCount;

  /// 包围盒宽（X 轴跨度，米）。
  final double bboxW;

  /// 包围盒深（Z 轴跨度，米）。
  final double bboxD;

  /// 包围盒高（Y 轴跨度，米）。
  final double bboxH;

  const ObjData({
    required this.vertexCount,
    required this.faceCount,
    required this.bboxW,
    required this.bboxD,
    required this.bboxH,
  });

  int get wMm => (bboxW * 1000).round();
  int get dMm => (bboxD * 1000).round();
  int get hMm => (bboxH * 1000).round();
}

class ObjParser {
  const ObjParser._();

  /// 文本长度上限（字符，防止把整个 APK 塞进来当模型）。
  static const int maxChars = 300000;

  /// 面数上限（OBJ 的 `f` 行计数）。
  static const int maxFaces = 5000;

  /// 解析并校验 [text]；不合法抛 [ObjParseException]。
  static ObjData parse(String text) {
    if (text.length > maxChars) {
      throw ObjParseException('OBJ 文件过大：${text.length} 字符，上限 $maxChars 字符');
    }

    var vertexCount = 0;
    var faceCount = 0;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var maxZ = double.negativeInfinity;

    final lines = text.split('\n');
    // 逐行宽松解析：畸形行（缺分量/非数字/未知指令）直接跳过，不抛异常——
    // 真实导出文件常带注释、空行、扩展指令（vn/vt/g/s/o/l），不能因此拒收。
    final ws = RegExp(r'\s+');
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(ws);
      final tag = parts[0];
      if (tag == 'v') {
        if (parts.length < 4) continue;
        final x = double.tryParse(parts[1]);
        final y = double.tryParse(parts[2]);
        final z = double.tryParse(parts[3]);
        if (x == null || y == null || z == null) continue;
        if (!x.isFinite || !y.isFinite || !z.isFinite) continue;
        vertexCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (z < minZ) minZ = z;
        if (z > maxZ) maxZ = z;
      } else if (tag == 'f') {
        // 顶点索引允许 `1`、`1/2`、`1//3`、`1/2/3`、负索引；
        // 只认「有 ≥3 个可解析索引」的面，畸形行不计也不报错。
        var n = 0;
        for (var i = 1; i < parts.length; i++) {
          final idx = int.tryParse(parts[i].split('/').first);
          if (idx != null) n++;
        }
        if (n >= 3) faceCount++;
      }
    }

    if (vertexCount == 0) {
      throw const ObjParseException('OBJ 没有顶点数据（缺少 v 行）');
    }
    if (faceCount == 0) {
      throw const ObjParseException('OBJ 没有面数据（缺少 f 行）');
    }
    if (faceCount > maxFaces) {
      throw ObjParseException('面数超限：$faceCount 面，上限 $maxFaces 面');
    }

    final w = maxX - minX;
    final d = maxZ - minZ;
    final h = maxY - minY;
    if (w <= 0 && d <= 0 && h <= 0) {
      throw const ObjParseException('OBJ 包围盒为空（所有顶点重合）');
    }

    return ObjData(
      vertexCount: vertexCount,
      faceCount: faceCount,
      bboxW: w,
      bboxD: d,
      bboxH: h,
    );
  }
}
