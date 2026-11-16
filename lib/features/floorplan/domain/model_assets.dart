// 由 tooling/gen_models.py 生成（原 app 内置素材模型，OBJ/MTL 见 assets/models/）。
/// 3D 端解析：assets/web/models.js（window.JJ_MODELS，含 obj/mtl 文本）。
class ModelAsset {
  final String id;
  final String category; // 门/五金/柜/栏杆/柱/墙体/基础体（原 app 分类）
  final String label;
  final double w, d, h; // 2D 占地（米）+ 3D 归一化目标高
  final int color;
  const ModelAsset(this.id, this.category, this.label, this.w, this.d, this.h, this.color);
}

class ModelAssets {
  const ModelAssets._();
  static const List<String> categories = ["门", "五金", "柜", "栏杆", "柱", "墙体", "基础体"];
  static const List<ModelAsset> all = [
    ModelAsset('1001', '门', '白色门板', 0.803, 0.146, 2.0, 0xE8E4DA),
    ModelAsset('1003', '门', '黑色移门', 1.773, 0.14, 2.0, 0x2B2E33),
    ModelAsset('1006', '门', '黑色移门 B', 1.773, 0.14, 2.0, 0x3A3F45),
    ModelAsset('1004', '五金', '银色拉手', 0.268, 0.037, 0.35, 0xC0C4C8),
    ModelAsset('1005', '柜', '柜板', 0.9, 0.15, 1.3, 0xB08968),
    ModelAsset('1007', '柜', '大衣柜', 1.84, 0.62, 1.98, 0x9C7A5A),
    ModelAsset('1009', '栏杆', '现代栏杆', 3.179, 0.065, 0.9, 0x8B93A5),
    ModelAsset('5004', '柜', '柜体方块', 1.0, 1.0, 1.0, 0x8F8F8F),
    ModelAsset('5005', '柜', '柜体', 1.469, 2.056, 2.1, 0xA8896A),
    ModelAsset('5006', '柜', '柜体 B', 1.469, 2.056, 2.1, 0xA8896A),
    ModelAsset('7001', '五金', '小五金 A', 0.09, 0.008, 0.09, 0x9AA4AB),
    ModelAsset('7002', '五金', '小五金 B', 0.09, 0.008, 0.09, 0x9AA4AB),
    ModelAsset('7003', '五金', '小五金 C', 0.09, 0.008, 0.09, 0x9AA4AB),
    ModelAsset('7004', '五金', '五金件 D', 0.468, 0.468, 0.12, 0x8A97A1),
    ModelAsset('7005', '五金', '五金件 E', 0.344, 0.633, 0.47, 0x8A97A1),
    ModelAsset('7006', '五金', '小五金 F', 0.658, 0.658, 0.02, 0x7D8A94),
    ModelAsset('7007', '五金', '小五金 G', 0.11, 0.11, 0.19, 0x7D8A94),
    ModelAsset('7008', '五金', '小五金 H', 0.01, 0.001, 0.01, 0x7D8A94),
    ModelAsset('7009', '五金', '小五金 I', 0.01, 0.001, 0.01, 0x7D8A94),
    ModelAsset('7101', '五金', '小五金 J', 0.01, 0.001, 0.01, 0x6E7A84),
    ModelAsset('7102', '五金', '小五金 K', 0.01, 0.001, 0.01, 0x6E7A84),
    ModelAsset('7104', '五金', '小五金 L', 0.01, 0.001, 0.01, 0x6E7A84),
    ModelAsset('7105', '五金', '小五金 M', 0.02, 0.005, 0.02, 0x6E7A84),
    ModelAsset('arcwall', '墙体', '弧形墙', 2.08, 1.036, 2.8, 0x99A5B5),
    ModelAsset('column', '柱', '方柱', 2.8, 2.8, 2.8, 0xB8B2A6),
    ModelAsset('cube', '基础体', '立方体', 0.8, 0.8, 0.8, 0x8F8F8F),
  ];

  static ModelAsset? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  static List<ModelAsset> ofCategory(String c) =>
      all.where((a) => a.category == c).toList(growable: false);
}
