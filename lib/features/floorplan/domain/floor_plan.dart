import 'dart:convert';
import 'dart:math' as math;

/// 户型领域模型。单位：米。坐标为 2D 平面（y 向下为正，与画布一致）。
/// 2D 编辑器、3D 视图（JSON 桥）、持久化共用这一份数据。

class Vec2 {
  final double x;
  final double y;
  const Vec2(this.x, this.y);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  double get dx => x;
  double get dy => y;
  double get length => math.sqrt(x * x + y * y);
  Vec2 normalized() {
    final l = length;
    return l == 0 ? const Vec2(0, 0) : Vec2(x / l, y / l);
  }

  double distanceTo(Vec2 o) => (this - o).length;

  Map<String, num> toJson() => {'x': x.roundToFraction(1000), 'y': y.roundToFraction(1000)};
  static Vec2 fromJson(Map<String, num> j) =>
      Vec2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

extension _NumR on num {
  double roundToFraction(double d) => (this / d).round() * d;
}

/// 墙：从 a 到 b 的线段。thickness 米（默认 0.24 砖墙），height 米（默认 2.8）。
class Wall {
  final String id;
  final Vec2 a;
  Vec2 b;
  double thickness;
  double height;

  Wall({required this.id, required this.a, required this.b, this.thickness = 0.24, this.height = 2.8});

  double get length => a.distanceTo(b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ax': a.toJson()['x'], 'ay': a.toJson()['y'],
        'bx': b.toJson()['x'], 'by': b.toJson()['y'],
        't': thickness, 'h': height,
      };
}

enum OpeningKind { door, window }

/// 门/窗开洞：挂在某面墙上，offset = 距墙起点 a 的米数。
class Opening {
  final String id;
  final String wallId;
  final OpeningKind kind;
  double offset;
  double width;
  double sill; // 窗台高（door 为 0）

  Opening({required this.id, required this.wallId, required this.kind, required this.offset, required this.width, this.sill = 0});

  Map<String, dynamic> toJson() => {
        'id': id, 'wall': wallId, 'kind': kind.name,
        'off': offset.roundToFraction(100), 'w': width, 'sill': sill,
      };
}

/// 家具目录（MVP 用占位体素：w×d  footprint + 3D 盒高/色；后续换 glTF）。
enum FurnitureKind { sofa, bed, table, chair, wardrobe, tv, plant, desk }

class FurnitureCatalog {
  const FurnitureCatalog._();

  /// footprint 宽×深（米），3D 盒高，占位色（0xRRGGBB）。
  static const Map<FurnitureKind, (double, double, double, int)> spec = {
    FurnitureKind.sofa: (1.8, 0.85, 0.8, 0x8FD3A8),
    FurnitureKind.bed: (1.6, 2.0, 0.5, 0x9FB6D9),
    FurnitureKind.table: (1.2, 0.8, 0.75, 0xD9B28A),
    FurnitureKind.chair: (0.45, 0.45, 0.9, 0xC7A88F),
    FurnitureKind.wardrobe: (1.2, 0.6, 2.1, 0xB08968),
    FurnitureKind.tv: (1.4, 0.4, 0.5, 0x6FCF97),
    FurnitureKind.plant: (0.4, 0.4, 1.2, 0x66BB6A),
    FurnitureKind.desk: (1.2, 0.6, 0.75, 0xC9A86A),
  };

  static String labelOf(FurnitureKind k) {
    const names = {
      FurnitureKind.sofa: '沙发', FurnitureKind.bed: '床',
      FurnitureKind.table: '餐桌', FurnitureKind.chair: '椅',
      FurnitureKind.wardrobe: '衣柜', FurnitureKind.tv: '电视柜',
      FurnitureKind.plant: '绿植', FurnitureKind.desk: '书桌',
    };
    return names[k]!;
  }
}

class FurnitureItem {
  final String id;
  FurnitureKind kind;
  Vec2 pos;
  double rotationDeg; // 绕 Z 轴，度

  FurnitureItem({required this.id, required this.kind, required this.pos, this.rotationDeg = 0});

  (double, double) get footprint {
    final s = FurnitureCatalog.spec[kind]!;
    return (s.$1, s.$2);
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind.name,
        'x': pos.toJson()['x'], 'y': pos.toJson()['y'],
        'rot': rotationDeg.round(),
      };
}

/// 户型图：墙 + 开洞 + 家具。
class FloorPlan {
  String name = '新建户型';
  final Map<String, Wall> walls = {};
  final Map<String, Opening> openings = {};
  final Map<String, FurnitureItem> items = {};
  int _seq = 1;

  String newId(String p) => '$p${_seq++}';

  /// three.js / 持久化 用的扁平 JSON。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'walls': walls.values.map((w) => w.toJson()).toList(),
      'openings': openings.values.map((o) => o.toJson()).toList(),
      'items': items.values.map((i) => i.toJson()).toList(),
    };
  }

  String toJsonString() => jsonEncode(toJson());

  /// 仅编辑器内部用：从 JSON 恢复（drift 持久化 M4 再换结构化表）。
  static FloorPlan fromJsonString(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final p = FloorPlan()
      ..name = (j['name'] as String?) ?? '户型';
    for (final w in (j['walls'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final wall = Wall(
        id: w['id'] as String,
        a: Vec2((w['ax'] as num).toDouble(), (w['ay'] as num).toDouble()),
        b: Vec2((w['bx'] as num).toDouble(), (w['by'] as num).toDouble()),
        thickness: (w['t'] as num?)?.toDouble() ?? 0.24,
        height: (w['h'] as num?)?.toDouble() ?? 2.8,
      );
      p.walls[wall.id] = wall;
      p._seq = p.maxSeq(p._seq, wall.id, 'w');
    }
    for (final o in (j['openings'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      p.openings[o['id'] as String] = Opening(
        id: o['id'] as String,
        wallId: o['wall'] as String,
        kind: OpeningKind.values.firstWhere((k) => k.name == o['kind']),
        offset: (o['off'] as num).toDouble(),
        width: (o['w'] as num).toDouble(),
        sill: (o['sill'] as num?)?.toDouble() ?? 0,
      );
      p._seq = p.maxSeq(p._seq, o['id'] as String, 'o');
    }
    for (final i in (j['items'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      p.items[i['id'] as String] = FurnitureItem(
        id: i['id'] as String,
        kind: FurnitureKind.values.firstWhere((k) => k.name == i['kind']),
        pos: Vec2((i['x'] as num).toDouble(), (i['y'] as num).toDouble()),
        rotationDeg: (i['rot'] as num?)?.toDouble() ?? 0,
      );
      p._seq = p.maxSeq(p._seq, i['id'] as String, 'i');
    }
    return p;
  }

  int maxSeq(int cur, String id, String prefix) {
    final m = RegExp('$prefix([0-9]+)\$').firstMatch(id);
    if (m == null) return cur;
    final n = int.tryParse(m.group(1)!) ?? cur;
    return n >= cur ? n + 1 : cur;
  }
}

/// 示例户型：3m×4m 客厅 + 2.4m 门 + 2.1m 窗，放沙发/电视柜/桌。
FloorPlan samplePlan() {
  final p = FloorPlan()..name = '示例 · 一居室';
  final w1 = Wall(id: 'w1', a: const Vec2(0, 0), b: const Vec2(5, 0));
  final w2 = Wall(id: 'w2', a: const Vec2(5, 0), b: const Vec2(5, 4));
  final w3 = Wall(id: 'w3', a: const Vec2(5, 4), b: const Vec2(0, 4));
  final w4 = Wall(id: 'w4', a: const Vec2(0, 4), b: const Vec2(0, 0));
  for (final w in [w1, w2, w3, w4]) {
    p.walls[w.id] = w;
  }
  p.openings['o1'] = Opening(id: 'o1', wallId: 'w4', kind: OpeningKind.door, offset: 1.2, width: 0.9);
  p.openings['o2'] = Opening(id: 'o2', wallId: 'w1', kind: OpeningKind.window, offset: 1.5, width: 2.0, sill: 0.9);
  p.items['i1'] = FurnitureItem(id: 'i1', kind: FurnitureKind.sofa, pos: const Vec2(1.0, 3.2), rotationDeg: 0);
  p.items['i2'] = FurnitureItem(id: 'i2', kind: FurnitureKind.tv, pos: const Vec2(1.0, 0.8));
  p.items['i3'] = FurnitureItem(id: 'i3', kind: FurnitureKind.table, pos: const Vec2(3.6, 2.0));
  return p;
}
