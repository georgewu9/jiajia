// 「家具」一级入口（模块 → 家具）的纯数据表：5 个二级分类 × 素材引用。
//
// 引用统一写成 `<source>:<id>`：
//   · 'kind:sofa'            → FurnitureCatalog 里的 19 个 FurnitureKind 之一
//   · 'model:shuzhuangtai'   → ModelItems（原 app 模型模块）里 floor 摆放的 ModelSpec
// 后者目前用于梳妆台 / 暖气片：它们在「台面/五金」分类里，已有图标与尺寸，
// 走现有的 model 放置路径（_startPlacingModel），不另造一种家具 kind。
//
// 同一件素材允许跨分类复用（书桌出现在 卧室 + 书房，电视柜出现在 卧室 + 客餐厅，
// 洗衣机出现在 厨房 + 其他）。
import 'floor_plan.dart';
import 'model_items.dart';

/// 一个已解析的家具菜单项。
class FurnitureTabItem {
  /// 原始引用串（'kind:sofa' / 'model:shuzhuangtai'），保留便于测试与日志。
  final String ref;
  final String label;

  /// kind:xxx 的来源；model:xxx 为 null。
  final FurnitureKind? kind;

  /// model:xxx 的来源（ModelItems 的 floor 摆放项）；kind:xxx 为 null。
  final ModelSpec? model;

  /// 模型库条目（kind=lib）的 id / 尺寸（米）；非库模型为 null。
  /// 由家具抽屉里「库」分类的 tile 构造，放置时写进 FurnitureItem.lib。
  final String? libId;
  final double? libW;
  final double? libD;
  final double? libH;

  const FurnitureTabItem({
    required this.ref,
    required this.label,
    this.kind,
    this.model,
    this.libId,
    this.libW,
    this.libD,
    this.libH,
  });

  /// 是否模型库条目（走 kind=lib 放置路径，但仍复用 _placeKindItem）。
  bool get isLib => libId != null;

  /// 是否走模型素材放置路径（ModelSpec → _startPlacingModel）。
  bool get isModel => model != null;

  /// 原 app 2D 图标（仅 model 素材有；家具 kind 多数无图 → UI 用占位 Icon）。
  String? get icon => model?.icon;

  /// 尺寸文案：宽×深×高（米），与模块二级网格的 specText 同款。
  String get specText {
    final m = model;
    if (m != null) return m.specText;
    final lw = libW;
    if (lw != null) {
      final ld = libD ?? 0.6;
      final lh = libH ?? 1.0;
      return '${_m(lw)}×${_m(ld)}×${_m(lh)}m';
    }
    final k = kind;
    if (k == null) return label;
    final s = FurnitureCatalog.spec[k]!;
    return '${s.$1}×${s.$2}×${s.$3}m';
  }

  /// 米 → 一位小数（1.0 显示 1，0.85 显示 0.85）。
  static String _m(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class FurnitureTabs {
  const FurnitureTabs._();

  /// 二级分类（顺序即 chips 顺序，默认选第一个）。
  static const List<String> cats = ['卧室', '客餐厅', '书房', '厨房', '其他'];

  /// 分类 → 引用串列表。数量：6 / 6 / 4 / 8 / 3。
  static const Map<String, List<String>> items = {
    '卧室': [
      'kind:bed',
      'kind:wardrobe',
      'kind:desk',
      'kind:shelf',
      'kind:tv',
      'model:shuzhuangtai', // 梳妆台（台面/五金）
    ],
    '客餐厅': [
      'kind:sofa',
      'kind:table',
      'kind:coffee',
      'kind:shoe',
      'kind:chair',
      'kind:tv',
    ],
    '书房': ['kind:desk', 'kind:shelf', 'kind:chair', 'kind:sofa'],
    '厨房': [
      'kind:fridge',
      'kind:washer',
      'kind:stove',
      'kind:hood',
      'kind:sink',
      'kind:microwave',
      'kind:oven',
      'model:nuanqipian', // 暖气片（台面/五金）
    ],
    '其他': ['kind:plant', 'kind:stool', 'kind:washer'],
  };

  /// 解析引用串；无法解析（未知前缀 / 未知 id）返回 null，由调用方过滤。
  static FurnitureTabItem? resolve(String ref) {
    final i = ref.indexOf(':');
    if (i <= 0 || i == ref.length - 1) return null;
    final source = ref.substring(0, i);
    final id = ref.substring(i + 1);
    if (source == 'kind') {
      FurnitureKind? hit;
      for (final k in FurnitureKind.values) {
        if (k.name == id) {
          hit = k;
          break;
        }
      }
      if (hit == null || !FurnitureCatalog.spec.containsKey(hit)) return null;
      return FurnitureTabItem(
        ref: ref,
        label: FurnitureCatalog.labelOf(hit),
        kind: hit,
      );
    }
    if (source == 'model') {
      for (final m in ModelItems.all) {
        if (m.id == id) {
          return FurnitureTabItem(ref: ref, label: m.label, model: m);
        }
      }
      return null;
    }
    return null;
  }

  /// 某分类下已解析的项（无法解析的引用直接跳过，不抛异常）。
  static List<FurnitureTabItem> ofCat(String cat) {
    final out = <FurnitureTabItem>[];
    for (final r in items[cat] ?? const <String>[]) {
      final it = resolve(r);
      if (it != null) out.add(it);
    }
    return List.unmodifiable(out);
  }
}
