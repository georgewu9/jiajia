// 原 app（家易量）「模型」模块复刻：门/窗/柱/楼梯/台面五金 五类。
// 图标取自原 apk `static/images/draw/`（见 assets/models2d/）。
// 放置规则：门/窗=贴墙开洞（wall），柱/楼梯/台面/五金=平面摆放（floor）。
import 'floor_plan.dart';

enum ModelPlace { wall, floor }

class ModelSpec {
  final String id;
  final String category; // 门/窗/柱/楼梯/台面五金/特殊墙窗
  final String label;
  final String? icon; // assets/models2d/icon_*.png|jpeg；null = 无原 app 图标（用占位图标）
  final ModelPlace place;

  // ---- wall（门/窗）参数，mm ----
  final OpeningKind kind;
  final DoorType doorType; // 仅门
  final int defaultWmm;
  final int sillMm;
  final int heightMm;
  final bool noLeaf; // 垭口/门洞/窗口：无扇
  // v0.1.34：关联 3D 素材 id（内置 JJ_MODELS 或 models_ext.js 的 JJ_EXT_MODELS）；
  // 仅门窗（place=wall）用，null = 走原 app 通用门扇/窗玻璃渲染。
  final String? modelId;

  // ---- floor（柱/楼梯/台面五金）----
  final FurnitureKind? floorKind;

  const ModelSpec({
    required this.id,
    required this.category,
    required this.label,
    this.icon,
    required this.place,
    this.kind = OpeningKind.door,
    this.doorType = DoorType.single,
    this.defaultWmm = 900,
    this.sillMm = 0,
    this.heightMm = 2000,
    this.noLeaf = false,
    this.modelId,
    this.floorKind,
  });

  String get specText {
    if (place == ModelPlace.wall) {
      final label = noLeaf ? '洞口' : (kind == OpeningKind.door ? doorType.label : '窗');
      final s = sillMm > 0 ? ' 台$sillMm' : '';
      return '$label $defaultWmm×$heightMm$s';
    }
    final k = floorKind;
    if (k == null) return label;
    final spec = FurnitureCatalog.spec[k]!;
    return '${spec.$1}×${spec.$2}×${spec.$3}m';
  }
}

class ModelItems {
  const ModelItems._();

  static const categories = [
    '门',
    '窗',
    '柱',
    '梁', // 梁/风管/包管道/裸管/地台（梁柱菜单另 5 件，设计稿称 beam）
    '楼梯',
    '台面/五金',
    '特殊墙窗',
  ];

  static const List<ModelSpec> all = [
    // ---------- 门 ----------
    ModelSpec(
      id: 'menjin',
      category: '门',
      label: '进户门',
      icon: 'assets/models2d/icon_menjin.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.single,
      defaultWmm: 1000,
      heightMm: 2000,
    ),
    ModelSpec(
      id: 'yimen',
      category: '门',
      label: '单开门',
      icon: 'assets/models2d/icon_yimen.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.single,
      defaultWmm: 900,
      heightMm: 2000,
    ),
    ModelSpec(
      id: 'shuangkaimen',
      category: '门',
      label: '双开门',
      icon: 'assets/models2d/icon_shuangkaimen.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.double,
      defaultWmm: 1500,
      heightMm: 2100,
    ),
    ModelSpec(
      id: 'mendong',
      category: '门',
      label: '门洞',
      icon: 'assets/models2d/icon_mendong.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.doorway,
      defaultWmm: 1000,
      heightMm: 2000,
      noLeaf: true,
    ),
    ModelSpec(
      id: 'yakou',
      category: '门',
      label: '垭口',
      icon: 'assets/models2d/icon_yakou.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.doorway,
      defaultWmm: 1000,
      heightMm: 2000,
      noLeaf: true,
    ),
    ModelSpec(
      id: 'yimen_huadong',
      category: '门',
      label: '移门',
      icon: 'assets/models2d/icon_yimen_huadong.png',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.sliding,
      defaultWmm: 1200,
      heightMm: 2000,
    ),
    // ---------- 门 · CC0 实模（v0.1.34：用户提供的 OBJ，见 assets/web/models_ext.js）----------
    ModelSpec(
      id: 'm_door1',
      category: '门',
      label: '标准单门',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.single,
      defaultWmm: 910,
      heightMm: 2140,
      modelId: 'm_door1',
    ),
    ModelSpec(
      id: 'm_frontDoorDark',
      category: '门',
      label: '入户大门',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.single,
      defaultWmm: 910,
      heightMm: 2100,
      modelId: 'm_frontDoorDark',
    ),
    ModelSpec(
      id: 'm_frenchDoors',
      category: '门',
      label: '法式门',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.double,
      defaultWmm: 910,
      heightMm: 2100,
      modelId: 'm_frenchDoors',
    ),
    ModelSpec(
      id: 'm_thick_double_2x4',
      category: '门',
      label: '厚框双移门',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.sliding,
      defaultWmm: 1600,
      heightMm: 2100,
      modelId: 'm_thick_double_2x4',
    ),
    ModelSpec(
      id: 'm_doorGlassPanels',
      category: '门',
      label: '玻璃门',
      place: ModelPlace.wall,
      kind: OpeningKind.door,
      doorType: DoorType.single,
      defaultWmm: 770,
      heightMm: 2060,
      modelId: 'm_doorGlassPanels',
    ),
    // ---------- 窗 ----------
    ModelSpec(
      id: 'luodichuang',
      category: '窗',
      label: '落地窗',
      icon: 'assets/models2d/icon_luodichuang.png',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1500,
      sillMm: 0,
      heightMm: 2400,
    ),
    ModelSpec(
      id: 'piaochuang',
      category: '窗',
      label: '飘窗',
      icon: 'assets/models2d/icon_piaochuang.png',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1800,
      sillMm: 900,
      heightMm: 450,
    ),
    ModelSpec(
      id: 'chuang',
      category: '窗',
      label: '普通窗',
      icon: 'assets/models2d/icon_chuang.jpeg',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1500,
      sillMm: 900,
      heightMm: 1500,
    ),
    ModelSpec(
      id: 'huxingchuang',
      category: '窗',
      label: '凸窗',
      icon: 'assets/models2d/icon_huxingchuang.png',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1800,
      sillMm: 500,
      heightMm: 1800,
    ),
    ModelSpec(
      id: 'zhichuang',
      category: '窗',
      label: '高窗',
      icon: 'assets/models2d/icon_zhichuang.png',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 900,
      sillMm: 1800,
      heightMm: 600,
    ),
    ModelSpec(
      id: 'wangkou',
      category: '窗',
      label: '窗口',
      icon: 'assets/models2d/icon_wangkou.png',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 900,
      sillMm: 900,
      heightMm: 1500,
      noLeaf: true,
    ),
    // ---------- 窗 · CC0 实模（v0.1.34）----------
    ModelSpec(
      id: 'm_window_deep',
      category: '窗',
      label: '深窗框',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1050,
      sillMm: 900,
      heightMm: 1500,
      modelId: 'm_window_deep',
    ),
    ModelSpec(
      id: 'm_window_double_sill',
      category: '窗',
      label: '双框窗台',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1230,
      sillMm: 900,
      heightMm: 1100,
      modelId: 'm_window_double_sill',
    ),
    // ---------- 柱 ----------
    ModelSpec(
      id: 'fangzhu',
      category: '柱',
      label: '方柱',
      icon: 'assets/models2d/icon_fangzhu.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.pillar,
    ),
    ModelSpec(
      id: 'yuanzhu',
      category: '柱',
      label: '圆柱',
      icon: 'assets/models2d/icon_yuanzhu.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.roundPillar,
    ),
    // ---------- 梁（梁柱菜单：梁/风管/包管道/裸管/地台）----------
    ModelSpec(
      id: 'liang',
      category: '梁',
      label: '梁',
      icon: 'assets/models2d/icon_liang.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.beam,
    ),
    ModelSpec(
      id: 'fengguan',
      category: '梁',
      label: '风管',
      icon: 'assets/models2d/icon_fengguan.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.duct,
    ),
    ModelSpec(
      id: 'baoguandao',
      category: '梁',
      label: '包管道',
      icon: 'assets/models2d/icon_baoguandao.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.pipeCase,
    ),
    ModelSpec(
      id: 'laoguan',
      category: '梁',
      label: '裸管',
      icon: 'assets/models2d/icon_laoguan.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.barePipe,
    ),
    ModelSpec(
      id: 'ditai',
      category: '梁',
      label: '地台',
      icon: 'assets/models2d/icon_ditai.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.platform,
    ),
    // ---------- 楼梯 ----------
    ModelSpec(
      id: 'zhilouti',
      category: '楼梯',
      label: '直楼梯',
      icon: 'assets/models2d/icon_zhilouti.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.stair,
    ),
    ModelSpec(
      id: 'youzhuanjiaolouti',
      category: '楼梯',
      label: '右拐楼梯',
      icon: 'assets/models2d/icon_youzhuanjiaolouti.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.stairR,
    ),
    ModelSpec(
      id: 'zuozhuanjiaolouti',
      category: '楼梯',
      label: '左拐楼梯',
      icon: 'assets/models2d/icon_zuozhuanjiaolouti.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.stairL,
    ),
    // ---------- 台面/五金 ----------
    ModelSpec(
      id: 'shuzhuangtai',
      category: '台面/五金',
      label: '梳妆台',
      icon: 'assets/models2d/icon_shuzhuangtai.jpeg',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.vanity,
    ),
    ModelSpec(
      id: 'ranqizao',
      category: '台面/五金',
      label: '燃气灶',
      icon: 'assets/models2d/icon_ranqizao.jpeg',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.gasStove,
    ),
    ModelSpec(
      id: 'ranqigui',
      category: '台面/五金',
      label: '燃气柜',
      icon: 'assets/models2d/icon_ranqigui.jpeg',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.gasCupboard,
    ),
    ModelSpec(
      id: 'xiashuikou',
      category: '台面/五金',
      label: '下水口',
      icon: 'assets/models2d/icon_xiashuikou.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.drain,
    ),
    ModelSpec(
      id: 'luoguan',
      category: '台面/五金',
      label: '落管',
      icon: 'assets/models2d/icon_luoguan.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.pipe,
    ),
    ModelSpec(
      id: 'meiqibiao',
      category: '台面/五金',
      label: '电表箱',
      icon: 'assets/models2d/icon_meiqibiao.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.meterBox,
    ),
    ModelSpec(
      id: 'shuibiao',
      category: '台面/五金',
      label: '水表',
      icon: 'assets/models2d/icon_shuibiao.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.waterMeter,
    ),
    ModelSpec(
      id: 'nuanqipian',
      category: '台面/五金',
      label: '暖气片',
      icon: 'assets/models2d/icon_nuanqipian.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.radiator,
    ),
    ModelSpec(
      id: 'kongtiaodong',
      category: '台面/五金',
      label: '空调洞',
      icon: 'assets/models2d/icon_kongtiaodong.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.acSlot,
    ),
    ModelSpec(
      id: 'qiangdianxiang',
      category: '台面/五金',
      label: '墙插',
      icon: 'assets/models2d/icon_qiangdianxiang.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.socketWall,
    ),
    ModelSpec(
      id: 'ruodianxiang',
      category: '台面/五金',
      label: '地插',
      icon: 'assets/models2d/icon_ruodianxiang.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.socketFloor,
    ),
    ModelSpec(
      id: 'kaiguan',
      category: '台面/五金',
      label: '开关',
      icon: 'assets/models2d/icon_kaiguan.png',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.switchPanel,
    ),
    // ---------- 楼梯（模块扩展：平台） ----------
    ModelSpec(
      id: 'pingtai',
      category: '楼梯',
      label: '平台',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.landing,
    ),
    // ---------- 特殊墙窗 ----------
    ModelSpec(
      id: 'huxiangqiang',
      category: '特殊墙窗',
      label: '弧形墙',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.arcWall,
    ),
    ModelSpec(
      id: 'huxiangchuang',
      category: '特殊墙窗',
      label: '弧形窗',
      place: ModelPlace.wall,
      kind: OpeningKind.window,
      defaultWmm: 1500,
      sillMm: 900,
      heightMm: 1500,
    ),
  ];

  static List<ModelSpec> ofCategory(String c) =>
      all.where((m) => m.category == c).toList(growable: false);

  /// 多类合并（模块·梁柱 = 柱 + 梁，共 7 件：方柱/圆柱 + 梁/风管/包管道/裸管/地台）。
  /// 台面/五金（12 件）不再进梁柱菜单。
  static List<ModelSpec> byCategories(Iterable<String> cs) =>
      all.where((m) => cs.contains(m.category)).toList(growable: false);
}
