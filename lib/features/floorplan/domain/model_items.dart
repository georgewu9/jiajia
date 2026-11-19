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

  // v0.1.36：floor 素材的显式规格（mm，宽×深×高）。null = 用 floorKind 的目录尺寸。
  // 庭院 12 件必须带（树/棚等尺寸差异极大，不能落 FurnitureCatalog 默认）。
  final int? specWmm;
  final int? specDmm;
  final int? specHmm;

  /// CC-BY 素材署名（null = 无需署名）。fountain 为 CC-BY 3.0，必须可见。
  final String? credit;

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
    this.specWmm,
    this.specDmm,
    this.specHmm,
    this.credit,
  });

  String get specText {
    if (place == ModelPlace.wall) {
      final label = noLeaf ? '洞口' : (kind == OpeningKind.door ? doorType.label : '窗');
      final s = sillMm > 0 ? ' 台$sillMm' : '';
      return '$label $defaultWmm×$heightMm$s';
    }
    if (specWmm != null) return '$specWmm×$specDmm×$specHmm';
    final k = floorKind;
    if (k == null) return label;
    final spec = FurnitureCatalog.spec[k]!;
    return '${spec.$1}×${spec.$2}×${spec.$3}m';
  }

  /// 序列化（模型库/导出的通用条目形状；旧数据缺 credit 等新键一律宽容）。
  Map<String, dynamic> toJson() => {
        'id': id,
        'cat': category,
        'label': label,
        if (icon != null) 'icon': icon,
        'place': place.name,
        'kind': kind.name,
        'dt': doorType.name,
        'wmm': defaultWmm,
        'sill': sillMm,
        'hmm': heightMm,
        'noLeaf': noLeaf,
        if (modelId != null) 'model': modelId,
        if (floorKind != null) 'floor': floorKind!.name,
        if (specWmm != null) 'swmm': specWmm,
        if (specDmm != null) 'sdmm': specDmm,
        if (specHmm != null) 'shmm': specHmm,
        if (credit != null) 'credit': credit,
      };

  /// 反序列化：模型库旧数据无 credit/swmm… → null，不抛。
  factory ModelSpec.fromJson(Map<String, dynamic> j) {
    T? byName<T extends Enum>(List<T> vals, Object? n) {
      if (n == null) return null;
      for (final v in vals) {
        if (v.name == n) return v;
      }
      return null;
    }

    return ModelSpec(
      id: j['id'] as String,
      category: (j['cat'] as String?) ?? '台面/五金',
      label: (j['label'] as String?) ?? (j['id'] as String),
      icon: j['icon'] as String?,
      place: byName(ModelPlace.values, j['place']) ?? ModelPlace.floor,
      kind: byName(OpeningKind.values, j['kind']) ?? OpeningKind.door,
      doorType: byName(DoorType.values, j['dt']) ?? DoorType.single,
      defaultWmm: (j['wmm'] as num?)?.toInt() ?? 900,
      sillMm: (j['sill'] as num?)?.toInt() ?? 0,
      heightMm: (j['hmm'] as num?)?.toInt() ?? 2000,
      noLeaf: (j['noLeaf'] as bool?) ?? false,
      modelId: j['model'] as String?,
      floorKind: byName(FurnitureKind.values, j['floor']),
      specWmm: (j['swmm'] as num?)?.toInt(),
      specDmm: (j['sdmm'] as num?)?.toInt(),
      specHmm: (j['shmm'] as num?)?.toInt(),
      credit: j['credit'] as String?,
    );
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
    '庭院', // v0.1.36：12 件 CC0/CC-BY 庭院 OBJ（地面摆放）
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
    // ---------- 庭院（v0.1.36：12 件 CC0/CC-BY OBJ，地面摆放；模型在 models_ext.js）----------
    ModelSpec(
      id: 'm_courtyard_awning',
      category: '庭院',
      label: '遮阳棚支架',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_awning',
      specWmm: 3100,
      specDmm: 1690,
      specHmm: 620,
    ),
    ModelSpec(
      id: 'm_courtyard_birch',
      category: '庭院',
      label: '白桦',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_birch',
      specWmm: 4160,
      specDmm: 3860,
      specHmm: 7920,
    ),
    ModelSpec(
      id: 'm_courtyard_chair',
      category: '庭院',
      label: '黑色露台椅',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_chair',
      specWmm: 290,
      specDmm: 370,
      specHmm: 620,
    ),
    ModelSpec(
      id: 'm_courtyard_table',
      category: '庭院',
      label: '黑色露台桌',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_table',
      specWmm: 910,
      specDmm: 920,
      specHmm: 420,
    ),
    ModelSpec(
      id: 'm_courtyard_palm',
      category: '庭院',
      label: '扇叶棕榈',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_palm',
      specWmm: 5060,
      specDmm: 5680,
      specHmm: 6340,
    ),
    ModelSpec(
      id: 'm_courtyard_fountain',
      category: '庭院',
      label: '庭院喷泉',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_fountain',
      specWmm: 1850,
      specDmm: 1850,
      specHmm: 1500,
      credit: 'High poly Fountain，by pndrdm（blendswap.com/blends/view/78775），'
          'CC-BY 3.0，修改：Emmanuel Puybaret / eTeks',
    ),
    ModelSpec(
      id: 'm_courtyard_greenhouse',
      category: '庭院',
      label: '温室',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_greenhouse',
      specWmm: 3100,
      specDmm: 3100,
      specHmm: 2900,
    ),
    ModelSpec(
      id: 'm_courtyard_pine',
      category: '庭院',
      label: '松树',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_pine',
      specWmm: 3400,
      specDmm: 3760,
      specHmm: 6130,
    ),
    ModelSpec(
      id: 'm_courtyard_railing',
      category: '庭院',
      label: '栏杆',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_railing',
      specWmm: 4750,
      specDmm: 330,
      specHmm: 1810,
    ),
    ModelSpec(
      id: 'm_courtyard_ramp',
      category: '庭院',
      label: '坡道栏杆',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_ramp',
      specWmm: 20000,
      specDmm: 8530,
      specHmm: 1170,
    ),
    ModelSpec(
      id: 'm_courtyard_sassafras',
      category: '庭院',
      label: '马桑树',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_sassafras',
      specWmm: 1770,
      specDmm: 1520,
      specHmm: 2070,
    ),
    ModelSpec(
      id: 'm_courtyard_tree',
      category: '庭院',
      label: '庭院树',
      place: ModelPlace.floor,
      floorKind: FurnitureKind.asset,
      modelId: 'm_courtyard_tree',
      specWmm: 7500,
      specDmm: 8000,
      specHmm: 10000,
    ),
  ];

  static List<ModelSpec> ofCategory(String c) =>
      all.where((m) => m.category == c).toList(growable: false);

  /// 按 id 查（v0.1.36：物品显示名用；未命中返回 null）。
  static ModelSpec? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 多类合并（模块·梁柱 = 柱 + 梁，共 7 件：方柱/圆柱 + 梁/风管/包管道/裸管/地台）。
  /// 台面/五金（12 件）不再进梁柱菜单。
  static List<ModelSpec> byCategories(Iterable<String> cs) =>
      all.where((m) => cs.contains(m.category)).toList(growable: false);
}
