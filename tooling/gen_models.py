#!/usr/bin/env python3
"""生成 3D 素材包：assets/web/models.js（内嵌 26 组 OBJ/MTL 文本 + 配置）
与 Dart 目录 lib/features/floorplan/domain/model_assets.dart。
模型来自原 app（家易量）APK 内置 assets/models/。
用法：python3 tooling/gen_models.py
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(ROOT, "assets", "models")

# id: (分类, 中文标签, 目标高度米, 2D色块色)
# 分类按原 app 领域：门 / 五金 / 柜 / 栏杆 / 柱 / 墙体 / 基础体
CFG = {
    "1001": ("门", "白色门板", 2.0, 0xE8E4DA),
    "1003": ("门", "黑色移门", 2.0, 0x2B2E33),
    "1006": ("门", "黑色移门 B", 2.0, 0x3A3F45),
    "1004": ("五金", "银色拉手", 0.35, 0xC0C4C8),
    "1005": ("柜", "柜板", 1.3, 0xB08968),
    "1007": ("柜", "大衣柜", 1.98, 0x9C7A5A),
    "1009": ("栏杆", "现代栏杆", 0.9, 0x8B93A5),
    "5004": ("柜", "柜体方块", 1.0, 0x8F8F8F),
    "5005": ("柜", "柜体", 2.1, 0xA8896A),
    "5006": ("柜", "柜体 B", 2.1, 0xA8896A),
    "7001": ("五金", "小五金 A", 0.09, 0x9AA4AB),
    "7002": ("五金", "小五金 B", 0.09, 0x9AA4AB),
    "7003": ("五金", "小五金 C", 0.09, 0x9AA4AB),
    "7004": ("五金", "五金件 D", 0.12, 0x8A97A1),
    "7005": ("五金", "五金件 E", 0.47, 0x8A97A1),
    "7006": ("五金", "小五金 F", 0.02, 0x7D8A94),
    "7007": ("五金", "小五金 G", 0.19, 0x7D8A94),
    "7008": ("五金", "小五金 H", 0.01, 0x7D8A94),
    "7009": ("五金", "小五金 I", 0.01, 0x7D8A94),
    "7101": ("五金", "小五金 J", 0.01, 0x6E7A84),
    "7102": ("五金", "小五金 K", 0.01, 0x6E7A84),
    "7104": ("五金", "小五金 L", 0.01, 0x6E7A84),
    "7105": ("五金", "小五金 M", 0.02, 0x6E7A84),
    "arcwall": ("墙体", "弧形墙", 2.8, 0x99A5B5),
    "column": ("柱", "方柱", 2.8, 0xB8B2A6),
    "cube": ("基础体", "立方体", 0.8, 0x8F8F8F),
}
CAT_ORDER = ["门", "五金", "柜", "栏杆", "柱", "墙体", "基础体"]


def bbox_of(obj_text):
    vs = re.findall(r"^v ([\-\d.eE+]+) ([\-\d.eE+]+) ([\-\d.eE+]+)", obj_text, re.M)
    xs = [float(a) for a, _, _ in vs]
    ys = [float(b) for _, b, _ in vs]
    zs = [float(c) for _, _, c in vs]
    return max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)


def parse_mtl_colors(mtl_text):
    """{matName: 0xRRGGBB}（取 Kd，缺省灰）"""
    colors, cur = {}, "default"
    for line in mtl_text.splitlines():
        if line.startswith("newmtl"):
            cur = line.split()[1]
        elif line.startswith("Kd"):
            p = line.split()
            r, g, b = int(float(p[1]) * 255 + 0.5), int(float(p[2]) * 255 + 0.5), int(float(p[3]) * 255 + 0.5)
            colors[cur] = (r << 16) | (g << 8) | b
    return colors


def main():
    js_entries = {}
    dart_entries = []
    for mid, (cat, label, h_t, color) in CFG.items():
        obj_path = os.path.join(MODELS_DIR, mid, mid + ".obj")
        mtl_path = os.path.join(MODELS_DIR, mid, mid + ".mtl")
        obj_text = open(obj_path, encoding="utf-8", errors="ignore").read()
        mtl_text = ""
        if os.path.exists(mtl_path):
            mtl_text = open(mtl_path, encoding="utf-8", errors="ignore").read()
        ext_x, ext_y, ext_z = bbox_of(obj_text)
        # 归一化：模型 y 轴 = 竖直。scale = 目标高 / 模型高；
        # 平放件（模型高≈0）退化为按最大水平边。
        s = h_t / ext_y if ext_y > 1e-6 else h_t / max(ext_x, ext_z)
        w = round(ext_x * s, 3)
        d = round(ext_z * s, 3)
        mtl_colors = parse_mtl_colors(mtl_text)
        js_entries[mid] = {
            "n": label, "cat": cat, "w": w, "d": d, "h": round(h_t, 3),
            "c": color, "o": obj_text, "m": mtl_text,
            "mc": {k: f"0x{v:06X}" for k, v in mtl_colors.items()},
        }
        dart_entries.append((mid, cat, label, w, d, round(h_t, 3), color))
        print(f"{mid:8s} {cat} {label}: w={w} d={d} h={h_t} mats={len(mtl_colors)}")

    # ---- models.js ----
    js_path = os.path.join(ROOT, "assets", "web", "models.js")
    with open(js_path, "w", encoding="utf-8") as f:
        f.write("/* 由 tooling/gen_models.py 生成：原 app 内置 26 组 OBJ/MTL 素材 */\n")
        f.write("window.JJ_MODELS = " + json.dumps(js_entries, ensure_ascii=False, separators=(",", ":")) + ";\n")
    print("wrote", js_path, os.path.getsize(js_path), "bytes")

    # ---- model_assets.dart ----
    dart_path = os.path.join(ROOT, "lib", "features", "floorplan", "domain", "model_assets.dart")
    lines = [
        "// 由 tooling/gen_models.py 生成（原 app 内置素材模型，OBJ/MTL 见 assets/models/）。",
        "/// 3D 端解析：assets/web/models.js（window.JJ_MODELS，含 obj/mtl 文本）。",
        "class ModelAsset {",
        "  final String id;",
        "  final String category; // 门/五金/柜/栏杆/柱/墙体/基础体（原 app 分类）",
        "  final String label;",
        "  final double w, d, h; // 2D 占地（米）+ 3D 归一化目标高",
        "  final int color;",
        "  const ModelAsset(this.id, this.category, this.label, this.w, this.d, this.h, this.color);",
        "}",
        "",
        "class ModelAssets {",
        "  const ModelAssets._();",
        "  static const List<String> categories = " + repr(CAT_ORDER).replace("'", '"') + ";",
        "  static const List<ModelAsset> all = [",
    ]
    for mid, cat, label, w, d, h, color in dart_entries:
        lines.append(
            f"    const ModelAsset('{mid}', '{cat}', '{label}', {w}, {d}, {h}, 0x{color:06X}),")
    lines += [
        "  ];",
        "",
        "  static ModelAsset? byId(String id) {",
        "    for (final a in all) {",
        "      if (a.id == id) return a;",
        "    }",
        "    return null;",
        "  }",
        "",
        "  static List<ModelAsset> ofCategory(String c) =>",
        "      all.where((a) => a.category == c).toList(growable: false);",
        "}",
        "",
    ]
    with open(dart_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("wrote", dart_path)


if __name__ == "__main__":
    main()
