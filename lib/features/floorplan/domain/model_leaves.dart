// 用户模型的「叶子分类」：用户导入时 cat 的取值域。
//
// 与 [ModelItems.categories] 的区别：这里只列菜单里看得见的一层叶子
// （门 / 窗 / 梁柱 / 楼梯 / 特殊墙窗 / 家具 / 庭院 / 用户素材），
// 家具再按 subCat 分 5 个 tab（见 FurnitureTabs.cats）。
//
// 「无分类」语义（用户素材菜单）：cat 为空、等于「用户素材」、或不是任何
// 已知叶子分类的用户模型都归这里——v0.1.37 及以前导入的老条目 cat 写的是
// 卧室/书房/厨房…（旧家具分类，不是叶子分类），因此全部落进「用户素材」。
import '../../../app/i18n.dart';
import 'model_items.dart';

class ModelLeaves {
  const ModelLeaves._();

  static const String door = '门';
  static const String window = '窗';
  static const String columnBeam = '梁柱';
  static const String stair = '楼梯';
  static const String specialWallWindow = '特殊墙窗';
  static const String furniture = '家具';
  static const String courtyard = '庭院';
  static const String userAssets = '用户素材';

  /// 顺序与模块一级菜单一致（用户素材放最后）。
  static const List<String> all = [
    door,
    window,
    columnBeam,
    stair,
    specialWallWindow,
    furniture,
    courtyard,
    userAssets,
  ];

  static const Map<String, String> _labelKeys = {
    door: 'leaf_door',
    window: 'leaf_window',
    columnBeam: 'leaf_column_beam',
    stair: 'leaf_stair',
    specialWallWindow: 'leaf_special',
    furniture: 'leaf_furniture',
    courtyard: 'leaf_courtyard',
    userAssets: 'leaf_user_assets',
  };

  /// 叶子分类的显示名（按当前语言）；未知值原样返回（用户模型分类兜底）。
  static String labelOf(String leaf) {
    final k = _labelKeys[leaf];
    return k == null ? leaf : t(k);
  }

  static bool contains(String? cat) => cat != null && all.contains(cat);

  /// 是否进「用户素材」网格：cat 为空 / 是「用户素材」/ 不在叶子分类内（旧条目）。
  static bool isUserAsset(String? cat) =>
      cat == null || cat.trim().isEmpty || cat == userAssets || !contains(cat);

  /// 叶子分类的稳定默认色（导入 OBJ 没有颜色信息时按 id 散列取一个）。
  /// 与 3D 占位调色板同一组色，末档为与强调色同族的翡翠绿，避免用户模型全是灰。
  static const List<int> palette = [
    0x8FB7D6,
    0x9FD3A8,
    0xD9B28A,
    0xC7A88F,
    0xB08968,
    0x00A88F,
  ];

  static int defaultColor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }

  /// 系统 ModelSpec 的原始 category → 叶子分类（导出单模型时兜底用）。
  /// 柱/梁/楼梯/台面五金 在菜单里拆成梁柱 + 楼梯两个叶子，导出时以菜单
  /// 上下文为准；这里只回答「按目录归类时算哪一类」。
  static String? ofSpecCategory(String category) => switch (category) {
    '门' => door,
    '窗' => window,
    '柱' || '梁' || '台面/五金' => columnBeam,
    '楼梯' => stair,
    '特殊墙窗' => specialWallWindow,
    '家具' => furniture,
    '庭院' => courtyard,
    _ => null,
  };

  /// 系统 ModelSpec 在某个叶子菜单里的展示名（标题/导出文件名兜底）。
  static String? leafOfSpec(ModelSpec m) => ofSpecCategory(m.category);
}
