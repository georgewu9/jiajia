// OBJ 导入的「原文件单位」换算（v0.1.45）。
//
// 背景：app 约定 OBJ 坐标按**米**解释（viewer.js 的 parseOBJ 与 bbox→mm 都据此），
// 但外部文件的导出单位经常不是米。japaneseMaple.obj 是厘米：7.9m 的树 bbox 按米
// 读成 790330/697160/699960 → 尺寸栏 790330mm 顶穿 50000 上限 → 入库被 `_mm()`
// 拦下，提示走底部 4 秒 snack，用户没看见，空白关框 3 次。
//
// 这里只做两件纯函数的事：
//   1) [ImportUnits.autoPick]：按原始 bbox（米约定的 mm 跨度）挑一个能把三边都
//      落回 [autoMinMm, maxMm] 的单位，作为命名对话框的预选（大 s 优先）；
//   2) [ObjUnit.scaleVertexText]：入库前把 OBJ 的 `v` 坐标整体 ×s（s ≤ 1，文本
//      只会更短），入库尺寸用换算后的 mm；`f` 索引与其它行原样保留。
//
// 单位语义：scale 是「原文件 1 单位 = scale 米」，即 raw(米值) × scale = 真实米。
// 因此 m=1.0 / dm=0.1 / cm=0.01 / mm=0.001。

/// 一个可选的原文件单位：显示用 [label]（m/cm/dm/mm），换算系数 [scale]。
class UnitOption {
  final String label;
  final double scale;

  const UnitOption(this.label, this.scale);

  @override
  bool operator ==(Object other) => other is UnitOption && other.scale == scale;

  @override
  int get hashCode => scale.hashCode;

  @override
  String toString() => 'UnitOption($label, $scale)';
}

class ImportUnits {
  const ImportUnits._();

  /// 尺寸栏合法区间（与 `_LibModelDialog._mm()` 同一口径）。
  static const int minMm = 1;
  static const int maxMm = 50000;

  /// 自动预检的**下限**：比这还小的边说明缩过头了（薄片被压成一条线），
  /// 该单位不选。上限与尺寸栏一致。
  static const int autoMinMm = 100;

  static const UnitOption meters = UnitOption('m', 1.0);
  static const UnitOption decimeters = UnitOption('dm', 0.1);
  static const UnitOption centimeters = UnitOption('cm', 0.01);
  static const UnitOption millimeters = UnitOption('mm', 0.001);

  /// 对话框 chips 顺序（默认第一个 = 米，app 原有约定）。
  static const List<UnitOption> options = [
    meters,
    centimeters,
    decimeters,
    millimeters,
  ];

  /// 自动预检的搜索顺序：**大 s 优先**（dm → cm → mm）。
  /// 能少缩放就少缩放——0.1 过闸时不选 0.01（更保守，几何改动更小）。
  static const List<UnitOption> _autoOrder = [
    decimeters,
    centimeters,
    millimeters,
  ];

  /// 自动预检：三边都已在 [maxMm] 内 → null（用米，不缩放）。
  /// 任一边超上限 → 返回第一个让三边全部落在 [autoMinMm, maxMm] 的单位；
  /// 一个都救不回来（如 7.9 亿 mm）→ null，调用方按默认 m 打开对话框，
  /// 由框内校验（红字 + 「入库」置灰）告诉用户为什么不能入库。
  static UnitOption? autoPick(int wMm, int dMm, int hMm) {
    if (wMm <= maxMm && dMm <= maxMm && hMm <= maxMm) return null;
    for (final u in _autoOrder) {
      if (fits(wMm, dMm, hMm, u.scale)) return u;
    }
    return null;
  }

  /// 三边 ×[scale] 后是否全部落在 [autoMinMm, maxMm]。
  static bool fits(int wMm, int dMm, int hMm, double scale) {
    for (final raw in [wMm, dMm, hMm]) {
      final mm = toMm(raw, scale);
      if (mm < autoMinMm || mm > maxMm) return false;
    }
    return true;
  }

  /// 米约定的 mm 跨度 → 目标单位下的 mm（向下取整）。
  ///
  /// 用 floor 不用 round：真机值 697160 × 0.01 = 6971.6 期望显示 6971（round 会
  /// 得 6972）；floor 同时避免四舍五入把 49999.6 顶到 50000 的闸边上。
  static int toMm(int rawMm, double scale) => (rawMm * scale).floor();

  /// 换算系数 → chips 标签（bootLog 用；未知系数回 'm'）。
  static String labelOf(double scale) {
    for (final u in options) {
      if (u.scale == scale) return u.label;
    }
    return 'm';
  }
}

/// OBJ 文本的顶点坐标换算（只动 `v` 行，其余逐字节保留）。
class ObjUnit {
  const ObjUnit._();

  /// 把 [text] 里所有 `v x y z [w ...]` 的**前三个分量** ×[scale]，坐标按
  /// 「6 位小数 + 去尾零」写出（与 `ObjDecimate._writeObj` 同一格式，入库文本
  /// 观感一致）；`vt/vn/f/usemtl/#` 等行原样保留。
  ///
  /// [scale] == 1.0 → 同一 String 实例返回（零改动，和减面器的透传口径一致）。
  /// 解析不出三个有限分量的 `v` 行（畸形行）也原样保留，不阻断导入。
  static String scaleVertexText(String text, double scale) {
    if (scale == 1.0) return text;
    final lines = text.split('\n');
    final b = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) b.write('\n');
      final line = lines[i];
      final scaled = _scaleLine(line, scale);
      b.write(scaled ?? line);
    }
    return b.toString();
  }

  static String? _scaleLine(String line, double s) {
    final toks = <String>[];
    final len = line.length;
    var p = 0;
    while (p < len) {
      while (p < len && _isSpace(line.codeUnitAt(p))) {
        p++;
      }
      if (p >= len) break;
      final start = p;
      while (p < len && !_isSpace(line.codeUnitAt(p))) {
        p++;
      }
      toks.add(line.substring(start, p));
    }
    if (toks.length < 4 || toks[0] != 'v') return null;
    final x = double.tryParse(toks[1]);
    final y = double.tryParse(toks[2]);
    final z = double.tryParse(toks[3]);
    if (x == null || y == null || z == null) return null;
    if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
    final b = StringBuffer('v ')
      ..write(fmtCoord(x * s))
      ..write(' ')
      ..write(fmtCoord(y * s))
      ..write(' ')
      ..write(fmtCoord(z * s));
    // 第四分量起（齐次 w / 顶点色 …）不是坐标，原样带着。
    for (var i = 4; i < toks.length; i++) {
      b
        ..write(' ')
        ..write(toks[i]);
    }
    return b.toString();
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0D;

  /// 6 位小数 + 去尾零：1e-6 米 = 1µm，远细于任何格宽；同时避免
  /// `toString()` 把 0.30000000000000004 这类浮点噪声写成 20 字符。
  /// 与 `ObjDecimate._fmt` 保持一致（同一份入库文本的两种写出路径）。
  static String fmtCoord(double v) {
    if (v == 0) return '0';
    final s = v.toStringAsFixed(6);
    var end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0x30) {
      end--;
    }
    if (end > 0 && s.codeUnitAt(end - 1) == 0x2E) end--; // '.'
    return s.substring(0, end);
  }
}
