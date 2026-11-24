import 'dart:convert';
import 'dart:math' as math;

import 'model_assets.dart';

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

  Map<String, num> toJson() => {
    'x': x.roundToFraction(1000),
    'y': y.roundToFraction(1000),
  };
  static Vec2 fromJson(Map<String, num> j) =>
      Vec2((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
}

extension _NumR on num {
  /// 四舍五入到 1/d 的精度（d=1000 → 毫米；旧实现写反成 1/d 的倍数，
  /// 4.0m 会被取整成 0.0 → 户型保存全变 (0,0) 空图，已修）。
  double roundToFraction(double d) => (this * d).round() / d;
}

/// 墙：从 a 到 b 的线段。thickness 米（默认 0.24 砖墙），height 米（默认 2.8）。
class Wall {
  final String id;
  final Vec2 a;
  Vec2 b;
  double thickness;
  double height;

  Wall({
    required this.id,
    required this.a,
    required this.b,
    this.thickness = 0.24,
    this.height = 2.8,
  });

  double get length => a.distanceTo(b);

  Map<String, dynamic> toJson() => {
    'id': id,
    'ax': a.toJson()['x'],
    'ay': a.toJson()['y'],
    'bx': b.toJson()['x'],
    'by': b.toJson()['y'],
    't': thickness,
    'h': height,
  };
}

enum OpeningKind { door, window }

/// 门型（家易量约定）：门洞=无门扇的洞口；单开门/双开门=平开门；移门=推拉门。
enum DoorType { doorway, single, double, sliding }

extension DoorTypeX on DoorType {
  String get label => switch (this) {
    DoorType.doorway => '门洞',
    DoorType.single => '单开门',
    DoorType.double => '双开门',
    DoorType.sliding => '移门',
  };

  /// 默认宽（mm）。双开门 1500，移门 1000，其余 900。
  int get defaultWidthMm => switch (this) {
    DoorType.double => 1500,
    DoorType.sliding => 1000,
    _ => 900,
  };

  /// 默认高（mm）。
  int get defaultHeightMm => switch (this) {
    DoorType.double => 2100,
    _ => 2000,
  };
}

/// mm <-> m 换算（UI 一律 mm，模型一律 m）。
int toMm(double m) => (m * 1000).round();
double fromMm(num mm) => mm / 1000;

/// 门/窗开洞：挂在某面墙上，offset = 距墙起点 a 的米数（即"离墙距离"）。
class Opening {
  final String id;
  final String wallId;
  final OpeningKind kind;
  DoorType doorType; // 仅 kind==door 有意义
  double offset;
  double width;
  double sill; // 窗台高（door 为 0）
  double height; // 开洞高（门高 / 窗高，sill+height 为窗顶）
  bool outSwing; // 外开门（false=内开，默认；仅单开/双开门有意义）
  // v0.1.24：铰链侧（true=左开，false=右开；仅单开/双开门有意义，与内/外开正交）
  bool hingeLeft;
  // v0.1.34：洞口挂的 3D 门窗素材 id（models_ext.js JJ_EXT_MODELS / 内置 JJ_MODELS）；
  // null = 通用门扇/窗玻璃渲染（旧数据宽容）。
  final String? modelId;

  Opening({
    required this.id,
    required this.wallId,
    required this.kind,
    required this.offset,
    required this.width,
    this.sill = 0,
    this.doorType = DoorType.single,
    this.outSwing = false,
    this.hingeLeft = true,
    this.modelId,
    double? height,
  }) : height =
           height ??
           (kind == OpeningKind.window ? 1.5 : doorType.defaultHeightMm / 1000);

  String get label {
    final w = toMm(width), h = toMm(height);
    if (kind == OpeningKind.window) {
      final s = toMm(sill);
      return s > 0 ? '窗 $w×$h(台$s)' : '窗 $w×$h';
    }
    final swings = doorType == DoorType.single || doorType == DoorType.double;
    final swing = swings ? (outSwing ? '外开' : '内开') : '';
    final hinge = swings ? '·${hingeLeft ? '左开' : '右开'}' : '';
    return '${doorType.label} $w×$h$swing$hinge';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'wall': wallId,
    'kind': kind.name,
    'dt': doorType.name,
    'off': offset.roundToFraction(100),
    'w': width,
    'sill': sill,
    'ht': height,
    'out': outSwing,
    'hl': hingeLeft,
    // v0.1.34：仅挂了 CC0 门窗素材的洞口写 m（旧数据无此键 → null）
    if (modelId != null) 'm': modelId,
  };
}

/// 家具目录（MVP 用占位体素：w×d  footprint + 3D 盒高/色；后续换 glTF）。
enum FurnitureKind {
  sofa,
  bed,
  table,
  chair,
  wardrobe,
  tv,
  plant,
  desk,
  stool,
  fridge,
  washer,
  heater,
  stove,
  hood,
  sink,
  microwave,
  oven,
  coffee,
  shoe,
  shelf,

  /// 原 app 素材模型（OBJ/MTL，见 ModelAssets）；2D 占地由 item.footprint 决定。
  asset,

  // ---- 原 app「模型」模块（2D 符号类：柱/楼梯/台面/五金）----
  pillar,
  roundPillar,
  stair,
  stairL,
  stairR,
  vanity,
  gasStove,
  gasCupboard,
  drain,
  pipe,
  meterBox,
  waterMeter,
  radiator,
  acSlot,
  socketWall,
  socketFloor,
  switchPanel,

  /// 楼梯平台（模块·楼梯）。
  landing,

  /// 弧形墙（模块·特殊墙窗；本版以薄墙段占位摆放，弧线绘制后续迭代）。
  arcWall,

  // ---- 梁柱菜单构件（梁 / 风管 / 包管道 / 裸管 / 地台）----
  beam,
  duct,
  pipeCase,
  barePipe,
  platform,

  /// 用户导入的模型库（外部 OBJ，见 LibModelsStore）；实际几何由 item.lib 决定。
  lib,
}

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
    FurnitureKind.stool: (0.35, 0.35, 0.45, 0xB98D6E),
    FurnitureKind.fridge: (0.7, 0.7, 1.8, 0xB8C4CC),
    FurnitureKind.washer: (0.6, 0.6, 0.9, 0xA8B8C4),
    FurnitureKind.heater: (0.5, 0.4, 0.8, 0xCC9A6E),
    FurnitureKind.stove: (0.75, 0.6, 0.85, 0x9AA4AB),
    FurnitureKind.hood: (0.9, 0.7, 1.6, 0x7D8A94),
    FurnitureKind.sink: (0.6, 0.5, 0.85, 0x8FA8B8),
    FurnitureKind.microwave: (0.5, 0.4, 0.35, 0x6E7A84),
    FurnitureKind.oven: (0.6, 0.6, 0.8, 0x8A97A1),
    FurnitureKind.coffee: (1.1, 0.6, 0.4, 0xA8896A),
    FurnitureKind.shoe: (0.8, 0.35, 1.0, 0x8F6F52),
    FurnitureKind.shelf: (0.8, 0.3, 1.8, 0x9C7A5A),
    FurnitureKind.asset: (0.6, 0.6, 0.6, 0x8B93A5),
    FurnitureKind.pillar: (0.4, 0.4, 2.8, 0xB8B2A6),
    FurnitureKind.roundPillar: (0.4, 0.4, 2.8, 0xD8D4CA),
    FurnitureKind.stair: (1.2, 2.6, 2.8, 0x8B93A5),
    FurnitureKind.stairL: (1.2, 2.6, 2.8, 0x7D8A94),
    FurnitureKind.stairR: (1.2, 2.6, 2.8, 0x99A5B5),
    FurnitureKind.vanity: (0.9, 0.45, 0.8, 0xA8896A),
    FurnitureKind.gasStove: (0.75, 0.65, 0.85, 0x9AA4AB),
    FurnitureKind.gasCupboard: (0.6, 0.65, 1.9, 0x9C7A5A),
    FurnitureKind.drain: (0.15, 0.15, 0.05, 0x7D8A94),
    FurnitureKind.pipe: (0.1, 0.3, 2.8, 0x7D8A94),
    FurnitureKind.meterBox: (0.4, 0.12, 0.6, 0x8A97A1),
    FurnitureKind.waterMeter: (0.3, 0.25, 0.4, 0x8FA8B8),
    FurnitureKind.radiator: (1.2, 0.12, 0.8, 0xCC9A6E),
    FurnitureKind.acSlot: (0.7, 0.7, 0.1, 0x6E7A84),
    FurnitureKind.socketWall: (0.1, 0.1, 0.1, 0x6FCF97),
    FurnitureKind.socketFloor: (0.12, 0.12, 0.02, 0x6FCF97),
    FurnitureKind.switchPanel: (0.1, 0.1, 0.1, 0xE5C97A),
    FurnitureKind.landing: (1.2, 1.2, 0.15, 0x9AA4B8),
    FurnitureKind.arcWall: (2.0, 0.24, 2.8, 0x9C8B7A),
    // 梁柱菜单构件（亮色建筑风占位色，3D 侧 viewer.js CATALOG 同步）
    FurnitureKind.beam: (2.4, 0.30, 0.35, 0xCFCFCF),
    FurnitureKind.duct: (1.2, 0.40, 0.35, 0xD8D8D8),
    FurnitureKind.pipeCase: (0.35, 0.35, 2.8, 0xE3E3E3),
    FurnitureKind.barePipe: (0.15, 0.15, 2.8, 0xBFC6CE),
    FurnitureKind.platform: (1.5, 1.2, 0.15, 0xE8E8E8),
    // 外部模型库占位（实际尺寸取 item.sizeW/D/H，颜色仅 2D/3D 缺库时兜底）
    FurnitureKind.lib: (1.0, 0.6, 1.0, 0x8F8F8F),
  };

  /// v0.1.32：家具 tab 放置柜类时默认挂的原 app 素材模型（OBJ 真几何）。
  /// 只影响 _placeKindItem（家具 tab）；「画房模型」模块的 ModelSpec 路径不读此表。
  /// 值 = (模型 id, 目标宽, 目标深, 目标高)：5005/5006 是 1.47×2.06 的深柜体，
  /// 直接按模型 bbox 放置太占房间，故用柜类自身尺寸覆盖；1007 大衣柜用原生尺寸。
  static const Map<FurnitureKind, (String, double, double, double)>
      cabinetModel = {
    FurnitureKind.wardrobe: ('1007', 1.84, 0.62, 1.98),
    FurnitureKind.shelf: ('5005', 1.0, 0.4, 1.9),
    FurnitureKind.shoe: ('5006', 0.9, 0.4, 1.1),
    FurnitureKind.tv: ('5005', 1.4, 0.4, 0.5),
  };

  /// 家具工具栏可选种类（不含素材模型 asset —— 走「素材」入口）。
  static const List<FurnitureKind> kinds = [
    FurnitureKind.sofa,
    FurnitureKind.bed,
    FurnitureKind.table,
    FurnitureKind.chair,
    FurnitureKind.wardrobe,
    FurnitureKind.tv,
    FurnitureKind.plant,
    FurnitureKind.desk,
    FurnitureKind.stool,
    FurnitureKind.fridge,
    FurnitureKind.washer,
    FurnitureKind.heater,
    FurnitureKind.stove,
    FurnitureKind.hood,
    FurnitureKind.sink,
    FurnitureKind.microwave,
    FurnitureKind.oven,
    FurnitureKind.coffee,
    FurnitureKind.shoe,
    FurnitureKind.shelf,
  ];

  static String labelOf(FurnitureKind k) {
    const names = {
      FurnitureKind.sofa: '沙发',
      FurnitureKind.bed: '床',
      FurnitureKind.table: '餐桌',
      FurnitureKind.chair: '椅',
      FurnitureKind.wardrobe: '衣柜',
      FurnitureKind.tv: '电视柜',
      FurnitureKind.plant: '绿植',
      FurnitureKind.desk: '书桌',
      FurnitureKind.stool: '凳子',
      FurnitureKind.fridge: '冰箱',
      FurnitureKind.washer: '洗衣机',
      FurnitureKind.heater: '热水器',
      FurnitureKind.stove: '燃气灶',
      FurnitureKind.hood: '烟机',
      FurnitureKind.sink: '水槽',
      FurnitureKind.microwave: '微波炉',
      FurnitureKind.oven: '烤箱',
      FurnitureKind.coffee: '茶几',
      FurnitureKind.shoe: '鞋柜',
      FurnitureKind.shelf: '置物架',
      FurnitureKind.asset: '素材',
      FurnitureKind.pillar: '方柱',
      FurnitureKind.roundPillar: '圆柱',
      FurnitureKind.stair: '直楼梯',
      FurnitureKind.stairL: '左拐楼梯',
      FurnitureKind.stairR: '右拐楼梯',
      FurnitureKind.vanity: '梳妆台',
      FurnitureKind.gasStove: '燃气灶',
      FurnitureKind.gasCupboard: '燃气柜',
      FurnitureKind.drain: '下水口',
      FurnitureKind.pipe: '落管',
      FurnitureKind.meterBox: '电表箱',
      FurnitureKind.waterMeter: '水表',
      FurnitureKind.radiator: '暖气片',
      FurnitureKind.acSlot: '空调洞',
      FurnitureKind.socketWall: '墙插',
      FurnitureKind.socketFloor: '地插',
      FurnitureKind.switchPanel: '开关',
      FurnitureKind.landing: '平台',
      FurnitureKind.arcWall: '弧形墙',
      FurnitureKind.beam: '梁',
      FurnitureKind.duct: '风管',
      FurnitureKind.pipeCase: '包管道',
      FurnitureKind.barePipe: '裸管',
      FurnitureKind.platform: '地台',
      FurnitureKind.lib: '库模型',
    };
    // 防崩：新加的 kind 若漏补 label（names 缺键），`!` 会空指针崩画布。
    return names[k] ?? k.name;
  }
}

class FurnitureItem {
  final String id;
  FurnitureKind kind;
  Vec2 pos;
  double rotationDeg; // 绕 Z 轴，度
  final String? modelId; // 原 app 素材模型 id（OBJ/MTL，见 ModelAssets）；null=占位盒
  // v0.1.20：自定义尺寸（米，null=用目录/素材默认值；JSON 键 sw/sd/sh，旧数据宽容解析）
  double? sizeW, sizeD, sizeH;
  // v0.1.24：整体离地高度（米，默认 0；楼梯用于二楼/错层，JSON 键 el）
  double elevation;
  // v0.1.31：模型库 id（kind=lib 时指向 LibModelsStore 的一条；JSON 键 lib）
  String? lib;
  // v0.1.37：mm 口径「离地高度」= 吊装/架空件**底面**相对本层地面的毫米值（JSON 键 off）。
  // 适用：实模（kind=model/asset）、梁（梁底标高）、地台（台底标高；台面 = 离地 + 高）。
  // 与 elevation（米，楼梯楼层抬升）互斥由调用方保证：同一件只写 off 或只写 el；
  // 放置时取 ModelSpec.offFloorMm（null → 0）；2D 占地不受影响。
  int? offFloorMm;

  FurnitureItem({
    required this.id,
    required this.kind,
    required this.pos,
    this.rotationDeg = 0,
    this.modelId,
    this.sizeW,
    this.sizeD,
    this.sizeH,
    this.elevation = 0,
    this.lib,
    this.offFloorMm,
  });

  /// 目录/素材默认占地（宽×深×高，米）。
  (double, double, double) get baseDims {
    final m = modelId == null ? null : ModelAssets.byId(modelId!);
    if (m != null) return (m.w, m.d, m.h);
    final s = FurnitureCatalog.spec[kind]!;
    return (s.$1, s.$2, s.$3);
  }

  /// 2D 占地（宽×深，米）：自定义值优先，否则目录/素材默认。
  (double, double) get footprint {
    final b = baseDims;
    return (sizeW ?? b.$1, sizeD ?? b.$2);
  }

  /// 3D 高度（米）：自定义值优先，否则目录/素材默认。
  double get heightM => sizeH ?? baseDims.$3;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (modelId != null) 'model': modelId,
    'x': pos.toJson()['x'],
    'y': pos.toJson()['y'],
    'rot': rotationDeg.round(),
    if (lib != null) 'lib': lib,
    if (sizeW != null) 'sw': sizeW,
    if (sizeD != null) 'sd': sizeD,
    if (sizeH != null) 'sh': sizeH,
    if (elevation != 0) 'el': elevation,
    if (offFloorMm != null) 'off': offFloorMm,
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
    final p = FloorPlan()..name = (j['name'] as String?) ?? '户型';
    for (final w
        in (j['walls'] as List<dynamic>).cast<Map<String, dynamic>>()) {
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
    for (final o
        in (j['openings'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      final kind = OpeningKind.values.firstWhere(
        (k) => k.name == o['kind'],
        orElse: () => OpeningKind.door,
      );
      DoorType dt;
      try {
        dt = DoorType.values.firstWhere((d) => d.name == o['dt']);
      } catch (_) {
        dt = DoorType.single;
      }
      p.openings[o['id'] as String] = Opening(
        id: o['id'] as String,
        wallId: o['wall'] as String,
        kind: kind,
        doorType: dt,
        offset: (o['off'] as num).toDouble(),
        width: (o['w'] as num).toDouble(),
        sill: (o['sill'] as num?)?.toDouble() ?? 0,
        height: (o['ht'] as num?)?.toDouble(), // null → 按 kind/dt 默认
        outSwing: o['out'] == true,
        // 旧 JSON 无 hl 字段 → 左开（宽容解析）
        hingeLeft: o['hl'] != false,
        // 旧 JSON 无 m 字段 → null（通用门窗渲染）
        modelId: o['m'] as String?,
      );
      p._seq = p.maxSeq(p._seq, o['id'] as String, 'o');
    }
    for (final i
        in (j['items'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      // 防崩：旧版本写过、当前 enum 已删掉的 kind，`firstWhere` 没有 orElse
      // 会抛 StateError → 整份户型打不开（且每次打开都崩 → 启动就弹日志页）。
      // 未知件跳过，不让一条脏数据毁掉整份户型。
      FurnitureKind? kind;
      for (final k in FurnitureKind.values) {
        if (k.name == i['kind']) {
          kind = k;
          break;
        }
      }
      if (kind == null) continue;
      p.items[i['id'] as String] = FurnitureItem(
        id: i['id'] as String,
        kind: kind,
        pos: Vec2((i['x'] as num).toDouble(), (i['y'] as num).toDouble()),
        rotationDeg: (i['rot'] as num?)?.toDouble() ?? 0,
        modelId: i['model'] as String?,
        sizeW: (i['sw'] as num?)?.toDouble(),
        sizeD: (i['sd'] as num?)?.toDouble(),
        sizeH: (i['sh'] as num?)?.toDouble(),
        // 旧 JSON 无 el 字段 → 离地 0
        elevation: (i['el'] as num?)?.toDouble() ?? 0,
        // 旧 JSON 无 off → null（落地 0）
        offFloorMm: (i['off'] as num?)?.toInt(),
        // 旧 JSON 无 lib 字段 → null（宽容解析）
        lib: i['lib'] as String?,
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

  /// 一键建房间：4 面墙围合矩形（at=左上角，世界坐标 y 向下；l=长(东西)，w=宽(南北)）。
  /// withDoor 时在底墙（p3→p4）中央加一扇标准宽门。返回 4 面墙 id（上/右/下/左）。
  List<String> addRoom({
    required Vec2 at,
    required double l,
    required double w,
    double h = 2.8,
    double thickness = 0.24,
    bool withDoor = true,
    double doorW = 0.9,
  }) {
    final p1 = at; // 左上
    final p2 = Vec2(at.x + l, at.y); // 右上
    final p3 = Vec2(at.x + l, at.y + w); // 右下
    final p4 = Vec2(at.x, at.y + w); // 左下
    final ids = <String>[];
    for (final (a, b) in [(p1, p2), (p2, p3), (p3, p4), (p4, p1)]) {
      final id = newId('w');
      walls[id] = Wall(id: id, a: a, b: b, thickness: thickness, height: h);
      ids.add(id);
    }
    if (withDoor) {
      final bw = walls[ids[2]]!; // 底墙
      final off = ((bw.length - doorW) / 2).clamp(0.0, bw.length);
      final oid = newId('o');
      openings[oid] = Opening(
        id: oid,
        wallId: ids[2],
        kind: OpeningKind.door,
        offset: off,
        width: math.min(doorW, bw.length * 0.9),
      );
    }
    return ids;
  }

  /// 导入另一户型的全部内容（示例户型 / 复制粘贴用），同步 id 序列防撞号。
  void importPlan(FloorPlan other) {
    for (final w in other.walls.values) {
      walls[w.id] = w;
      _seq = maxSeq(_seq, w.id, 'w');
    }
    for (final o in other.openings.values) {
      openings[o.id] = o;
      _seq = maxSeq(_seq, o.id, 'o');
    }
    for (final i in other.items.values) {
      items[i.id] = i;
      _seq = maxSeq(_seq, i.id, 'i');
    }
  }
}

/// 房间环：由若干墙围合出的闭合房间。area 单位 m²，centroid 用于面积标注。
class RoomLoop {
  final List<Wall> walls;
  final double area;
  final Vec2 centroid;
  RoomLoop(this.walls, this.area, this.centroid);
}

extension FloorPlanRooms on FloorPlan {
  /// 找出所有闭合房间（墙图上的简单环，3~12 面墙，面积 ≥0.25m²，去重，上限 60 个）。
  /// 典型户型 <40 面墙，DFS 足够快；用于平面图面积标注（原 app「房间面积」同款）。
  List<RoomLoop> roomLoops() {
    const eps = 0.03;
    final nodes = <Vec2>[];
    int nodeOf(Vec2 p) {
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].distanceTo(p) < eps) return i;
      }
      nodes.add(p);
      return nodes.length - 1;
    }

    final adj = <int, List<(int, String)>>{};
    for (final w in walls.values) {
      if (w.length < 0.05) continue;
      final i = nodeOf(w.a), j = nodeOf(w.b);
      if (i == j) continue;
      adj.putIfAbsent(i, () => []).add((j, w.id));
      adj.putIfAbsent(j, () => []).add((i, w.id));
    }

    final found = <RoomLoop>[];
    final seen = <String>{};

    void dfs(
      int start,
      int cur,
      List<int> path,
      List<String> used,
      Set<String> usedSet,
    ) {
      if (found.length >= 60 || path.length > 12) return;
      for (final (next, wid) in adj[cur] ?? const <(int, String)>[]) {
        if (usedSet.contains(wid)) continue;
        if (next == start && path.length >= 3) {
          final keySet = Set<String>.from(used)..add(wid);
          if (keySet.length < 3 || seen.contains(keySet.join('|'))) continue;
          // 面积（shoelace）
          var s = 0.0;
          var cx = 0.0, cy = 0.0;
          for (var i = 0; i < path.length; i++) {
            final a = nodes[path[i]],
                b = nodes[i + 1 < path.length ? i + 1 : 0];
            s += a.x * b.y - b.x * a.y;
            cx += a.x;
            cy += a.y;
          }
          final area = s.abs() / 2;
          if (area < 0.25) continue;
          seen.add(keySet.join('|'));
          final loopWalls = <Wall>[for (final wid in keySet) walls[wid]!]
            ..sort((a, b) => a.id.compareTo(b.id));
          found.add(
            RoomLoop(loopWalls, area, Vec2(cx / path.length, cy / path.length)),
          );
        }
        if (next <= start || path.contains(next)) continue;
        dfs(start, next, [...path, next], [...used, wid], {...usedSet, wid});
      }
    }

    for (var s = 0; s < nodes.length; s++) {
      dfs(s, s, [s], const <String>[], const <String>{});
      if (found.length >= 60) break;
    }
    found.sort((a, b) => b.area.compareTo(a.area));
    // ① 按墙集去重（DFS 可能把同一组墙以不同路径顺序吐多次，面积各不同）
    // ② 面积/质心用「有序多边形」shoelace 重算（DFS 路径顺序不可靠）
    final bySet = <String, RoomLoop>{};
    for (final l in found) {
      bySet.putIfAbsent(l.walls.map((w) => w.id).join('|'), () => l);
    }
    var rooms = bySet.values
        .map((l) {
          final nodes = orderedNodes(l);
          double s = 0;
          var cx = 0.0, cy = 0.0;
          for (var i = 0; i < nodes.length; i++) {
            final a = nodes[i],
                b = nodes[(i + 1) % nodes.length];
            s += a.x * b.y - b.x * a.y;
            cx += a.x;
            cy += a.y;
          }
          final n = nodes.length;
          return RoomLoop(l.walls, s.abs() / 2, Vec2(cx / n, cy / n));
        })
        .toList();
    // ③ 剔除「假环」：被隔墙穿过的环（非成员墙中点严格落在环内）不是房间
    rooms.removeWhere((loop) {
      for (final w in walls.values) {
        if (loop.walls.any((m) => m.id == w.id)) continue;
        final mid = Vec2((w.a.x + w.b.x) / 2, (w.a.y + w.b.y) / 2);
        bool inside = false;
        // 防崩：`orderedNodes` 链断了可能返回空表（`.first` 直接 RangeError →
        // 白屏 + 下次启动弹日志页）。空环不是房间，跳过即可；顺便只算一次。
        final on = orderedNodes(loop);
        if (on.isEmpty) return false;
        var prev = on.first;
        for (final n in on.skip(1)) {
          final cur = n;
          if ((prev.y > mid.y) != (cur.y > mid.y)) {
            final xInt =
                prev.x + (mid.y - prev.y) / (cur.y - prev.y) * (cur.x - prev.x);
            if (mid.x < xInt) inside = !inside;
          }
          prev = cur;
        }
        if (!inside) continue;
        var dMin = 1e9;
        for (final m in loop.walls) {
          final abx = m.b.x - m.a.x,
              aby = m.b.y - m.a.y;
          final l2 = abx * abx + aby * aby;
          double d;
          if (l2 < 1e-9) {
            d = Vec2(mid.x - m.a.x, mid.y - m.a.y).length;
          } else {
            var t =
                ((mid.x - m.a.x) * abx + (mid.y - m.a.y) * aby) / l2;
            t = t.clamp(0.0, 1.0);
            d = Vec2(m.a.x + t * abx - mid.x, m.a.y + t * aby - mid.y)
                .length;
          }
          dMin = math.min(dMin, d);
        }
        if (dMin > 0.05) return true; // 有隔墙在房间内部 → 假环
      }
      return false;
    });
    // ④ 按多边形签名去重：同一物理房间可能以两种墙集（共位双墙）或
    // 两种方向（CW/CCW）各出现一次 → 签名取「正向/反向」的字典序较小者
    final seenPoly = <String>{};
    String sigOf(List<Vec2> v) {
      int minI = 0;
      for (var i = 1; i < v.length; i++) {
        final a = v[i], b = v[minI];
        if (a.x < b.x || (a.x == b.x && a.y < b.y)) minI = i;
      }
      return List<String>.generate(v.length, (i) {
        final n = v[(minI + i) % v.length];
        return '${(n.x * 20).round()}:${(n.y * 20).round()}';
      }).join(',');
    }

    rooms.removeWhere((loop) {
      final nodes = orderedNodes(loop);
      final uniq = nodes.length > 1 ? nodes.sublist(0, nodes.length - 1) : nodes;
      if (uniq.isEmpty) return true;
      final key = [
        sigOf(uniq),
        sigOf(uniq.reversed.toList()),
      ].reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      return !seenPoly.add(key);
    });
    return rooms;
  }
}

/// 房间几何操作（拆/合/删房 + 房间包含测试，原 app「分房/合并」同款）。
extension RoomOps on FloorPlan {
  /// 把房间的墙按端点衔接成有序多边形（节点序列，首尾不重复）。
  /// 房间环是简单回路（T 型三通取「非来向」边），3~12 面墙足够。
  List<Vec2> orderedNodes(RoomLoop loop) {
    const eps = 0.05;
    if (loop.walls.isEmpty) return const [];
    // 从任意墙出发链式走：在节点处贪心找「未用过、与上一面墙尾端共点」的墙
    final usedW = <String>{};
    final rest = <Wall>[...loop.walls];
    final first = loop.walls.first;
    final out = <Vec2>[first.a, first.b];
    usedW.add(first.id);
    var guard = 0;
    while (guard++ < 16 && rest.isNotEmpty) {
      final prevB = out.last;
      Wall? nextWall;
      Vec2? nextNode;
      outer:
      for (final w in rest) {
        if (usedW.contains(w.id)) continue;
        for (final e in [w.a, w.b]) {
          if (e.distanceTo(prevB) < eps) {
            nextWall = w;
            // 取「另一端」为新节点（e 是与上墙尾重合的端点）
            nextNode = w.a.distanceTo(prevB) < eps ? w.b : w.a;
            break outer;
          }
        }
      }
      if (nextWall == null) break; // 断链（非简单环）→ 用已有序列
      usedW.add(nextWall.id);
      rest.remove(nextWall);
      out.add(nextNode!);
    }
    if (out.length < 3) {
      // 兜底：墙端点集合（退化情况，仅用于 bbox）
      return loop.walls.expand((w) => [w.a, w.b]).toSet().toList();
    }
    return out;
  }

  /// 点是否在房间内（shoelace 射线法，节点取 orderedNodes）。
  bool roomContains(RoomLoop loop, Vec2 p) {
    final nodes = orderedNodes(loop);
    if (nodes.length < 3) return false;
    var inside = false;
    var j = nodes.length - 1;
    for (var i = 0; i < nodes.length; i++) {
      final a = nodes[i], b = nodes[j];
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  /// 两房间共用的隔墙 id（无则 null）。
  String? sharedWallBetween(RoomLoop a, RoomLoop b) {
    final sa = a.walls.map((w) => w.id).toSet();
    for (final w in b.walls) {
      if (sa.contains(w.id)) return w.id;
    }
    return null;
  }

  /// 把「包含点 pt 的边界墙」切成两段（T 型节点），开洞按位置迁移。
  /// axis：拆房方向（'v' 竖直隔墙 → 切的是水平墙；'h' → 切垂直墙）。
  void _splitBoundaryWallAt(Vec2 pt, String axis) {
    const eps = 0.06;
    for (final w in walls.values.toList()) {
      final horiz = (w.a.dy - w.b.dy).abs() < (w.a.dx - w.b.dx).abs();
      if (axis == 'v' && !horiz) continue;
      if (axis == 'h' && horiz) continue;
      // pt 在 w 上：
      final onSeg = horiz
          ? ((pt.dy - w.a.dy).abs() < eps &&
              pt.dx >= math.min(w.a.dx, w.b.dx) - eps &&
              pt.dx <= math.max(w.a.dx, w.b.dx) + eps)
          : ((pt.dx - w.a.dx).abs() < eps &&
              pt.dy >= math.min(w.a.dy, w.b.dy) - eps &&
              pt.dy <= math.max(w.a.dy, w.b.dy) + eps);
      if (!onSeg) continue;
      // 端点已在 pt（非 T 型）不切
      if (w.a.distanceTo(pt) < eps || w.b.distanceTo(pt) < eps) continue;
      final d = pt.distanceTo(w.a);
      final id1 = newId('w'), id2 = newId('w');
      walls[id1] = Wall(id: id1, a: w.a, b: pt, thickness: w.thickness);
      walls[id2] = Wall(id: id2, a: pt, b: w.b, thickness: w.thickness);
      walls.remove(w.id);
      // 开洞是 final wallId → 重建并迁移到新段
      for (final o in openings.values.toList()) {
        if (o.wallId != w.id) continue;
        final o2 = o.offset <= d
            ? Opening(
                id: o.id,
                wallId: id1,
                kind: o.kind,
                doorType: o.doorType,
                offset: o.offset,
                width: o.width,
                sill: o.sill,
                height: o.height,
                outSwing: o.outSwing,
                hingeLeft: o.hingeLeft,
                modelId: o.modelId,
              )
            : Opening(
                id: o.id,
                wallId: id2,
                kind: o.kind,
                doorType: o.doorType,
                offset: o.offset - d,
                width: o.width,
                sill: o.sill,
                height: o.height,
                outSwing: o.outSwing,
                hingeLeft: o.hingeLeft,
                modelId: o.modelId,
              );
        openings[o.id] = o2;
      }
      return;
    }
  }

  /// 拆分房间：在房间内加一面隔墙（v=竖直墙分左右 / h=水平墙分上下），
  /// 位置 frac ∈ (0,1) 相对房间 bbox。withDoor 时隔墙中央加 900 门。
  /// 返回新墙 id；房间不可拆（太小/非轴对齐）返回 null。
  String? splitRoom(
    RoomLoop loop, {
    required String axis,
    double frac = 0.5,
    bool withDoor = true,
  }) {
    final nodes = orderedNodes(loop);
    if (nodes.length < 4) return null;
    double minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
    for (final n in nodes) {
      minx = math.min(minx, n.x);
      maxx = math.max(maxx, n.x);
      miny = math.min(miny, n.y);
      maxy = math.max(maxy, n.y);
    }
    final thick = loop.walls.first.thickness;
    Vec2 p1, p2;
    if (axis == 'v') {
      if ((maxx - minx) < 0.6) return null; // 太窄
      final x = minx + frac.clamp(0.1, 0.9) * (maxx - minx);
      p1 = Vec2(x, miny);
      p2 = Vec2(x, maxy);
    } else {
      if ((maxy - miny) < 0.6) return null;
      final y = miny + frac.clamp(0.1, 0.9) * (maxy - miny);
      p1 = Vec2(minx, y);
      p2 = Vec2(maxx, y);
    }
    if (p1.distanceTo(p2) < 0.3) return null;
    final id = newId('w');
    walls[id] = Wall(id: id, a: p1, b: p2, thickness: thick, height: 2.8);
    // 隔墙端点落在边界墙中间（T 型）→ 必须把被穿的边界墙切成两段，
    // 否则 DFS 房间图里还是 1 个大环（房间没真正拆开）
    _splitBoundaryWallAt(p1, axis);
    _splitBoundaryWallAt(p2, axis);
    if (withDoor) {
      final w = walls[id]!;
      final off = ((w.length - 0.9) / 2).clamp(0.05, w.length - 0.9);
      final oid = newId('o');
      openings[oid] = Opening(
        id: oid,
        wallId: id,
        kind: OpeningKind.door,
        offset: off,
        width: 0.9,
      );
    }
    return id;
  }

  /// 合并两个房间：删除共用隔墙 + 该墙上的门窗。返回删除墙数（0=不相邻）。
  int mergeRooms(RoomLoop a, RoomLoop b) {
    final id = sharedWallBetween(a, b);
    if (id == null) return 0;
    openings.removeWhere((_, o) => o.wallId == id);
    walls.remove(id);
    return 1;
  }

  /// 删除房间：只删「不与其他房间共用」的墙（外墙保留）。返回删除数。
  int removeRoomWalls(RoomLoop loop) {
    final others = roomLoops()..removeWhere((l) => identical(l, loop));
    final shared = <String>{};
    for (final l in others) {
      for (final w in loop.walls) {
        if (l.walls.any((o) => o.id == w.id)) shared.add(w.id);
      }
    }
    var n = 0;
    for (final w in loop.walls) {
      if (shared.contains(w.id)) continue;
      openings.removeWhere((_, o) => o.wallId == w.id);
      walls.remove(w.id);
      n++;
    }
    return n;
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
  p.openings['o1'] = Opening(
    id: 'o1',
    wallId: 'w4',
    kind: OpeningKind.door,
    offset: 1.2,
    width: 0.9,
  );
  p.openings['o2'] = Opening(
    id: 'o2',
    wallId: 'w1',
    kind: OpeningKind.window,
    offset: 1.5,
    width: 2.0,
    sill: 0.9,
  );
  p.items['i1'] = FurnitureItem(
    id: 'i1',
    kind: FurnitureKind.sofa,
    pos: const Vec2(1.0, 3.2),
    rotationDeg: 0,
  );
  p.items['i2'] = FurnitureItem(
    id: 'i2',
    kind: FurnitureKind.tv,
    pos: const Vec2(1.0, 0.8),
  );
  p.items['i3'] = FurnitureItem(
    id: 'i3',
    kind: FurnitureKind.table,
    pos: const Vec2(3.6, 2.0),
  );
  p.items['i4'] = FurnitureItem(
    id: 'i4',
    kind: FurnitureKind.coffee,
    pos: const Vec2(1.0, 2.2),
  );
  p.items['i5'] = FurnitureItem(
    id: 'i5',
    kind: FurnitureKind.stool,
    pos: const Vec2(4.2, 2.6),
  );
  p.items['i6'] = FurnitureItem(
    id: 'i6',
    kind: FurnitureKind.shelf,
    pos: const Vec2(4.9, 1.0),
    rotationDeg: 90,
  );
  p.items['i7'] = FurnitureItem(
    id: 'i7',
    kind: FurnitureKind.stove,
    pos: const Vec2(2.0, 3.7),
  );
  p.items['i8'] = FurnitureItem(
    id: 'i8',
    kind: FurnitureKind.sink,
    pos: const Vec2(2.8, 3.7),
  );
  p.items['i9'] = FurnitureItem(
    id: 'i9',
    kind: FurnitureKind.fridge,
    pos: const Vec2(4.4, 0.59),
  );
  p.items['i10'] = FurnitureItem(
    id: 'i10',
    kind: FurnitureKind.washer,
    pos: const Vec2(0.54, 1.8),
    rotationDeg: 90,
  );
  return p;
}
