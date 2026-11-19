// Dart 侧读 3D 素材包里的 OBJ 原文：assets/web/models.js（JJ_MODELS，26 组）
// 与 assets/web/models_ext.js（JJ_EXT_MODELS，7 门窗 + 11 庭院 + 42 家具）。
//
// 两个文件都是「window.JJ_XXX = {…};」形式的可 JSON.parse 字面量（生成器
// tooling/gen_models*.py 写出），所以 Dart 只需截出 `{…}` 段交给 jsonDecode，
// 不写 JS 解析器、不引新依赖。
//
// 用途：长按系统 tile → 导出单件模型 JSON 时带出逐字节等价的 OBJ 原文。
// 读失败（旧包缺 models_ext.js / 资源损坏）→ 返回 null，调用方回退占位盒，
// 绝不崩。
import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// 一条 3D 素材（models.js / models_ext.js 的条目）。
class AssetModel {
  final String id;

  /// 展示名（生成器写的 n）。
  final String name;

  /// 生成器写的原始 cat：门/窗/庭院/家具/五金/柜…
  final String category;

  /// 规格（米）。
  final double wM;
  final double dM;
  final double hM;

  /// 0xRRGGBB 颜色。
  final int color;

  /// OBJ 原文（逐字节等于 assets 里的 o 字段）。
  final String objText;

  const AssetModel({
    required this.id,
    required this.name,
    required this.category,
    required this.wM,
    required this.dM,
    required this.hM,
    required this.color,
    required this.objText,
  });
}

class ModelAssetLibrary {
  const ModelAssetLibrary._();

  static const List<String> assetPaths = [
    'assets/web/models.js',
    'assets/web/models_ext.js',
  ];

  static Map<String, AssetModel>? _byId;

  static bool get isLoaded => _byId != null;

  /// 读资源（首次调用才读，之后走内存）。任何异常 → 空表（不抛）。
  static Future<void> ensureLoaded({AssetBundle? bundle}) async {
    if (_byId != null) return;
    final texts = <String>[];
    final b = bundle ?? rootBundle;
    for (final p in assetPaths) {
      try {
        texts.add(await b.loadString(p));
      } catch (_) {
        // 旧包可能没有 models_ext.js：跳过，models.js 照常可用
      }
    }
    _byId = parseTexts(texts);
  }

  /// 纯函数入口（单测直接喂文件文本，不依赖 rootBundle/asset bundle）。
  static Future<void> loadFromTexts(Iterable<String> texts) async {
    _byId = parseTexts(texts);
  }

  static void resetForTest() => _byId = null;

  static AssetModel? byId(String? id) => id == null ? null : _byId?[id];

  /// 解析 `window.JJ_MODELS = {…};` 形式文本；单条坏数据跳过。
  static Map<String, AssetModel> parseTexts(Iterable<String> texts) {
    final out = <String, AssetModel>{};
    for (final text in texts) {
      final obj = _objectFromJs(text);
      if (obj == null) continue;
      obj.forEach((k, v) {
        if (v is! Map) return;
        final o = v['o'];
        if (o is! String || o.trim().isEmpty) return;
        double numOf(Object? x) => (x is num && x.isFinite) ? x.toDouble() : 0;
        out[k] = AssetModel(
          id: k,
          name: (v['n'] as String?) ?? k,
          category: (v['cat'] as String?) ?? '',
          wM: numOf(v['w']),
          dM: numOf(v['d']),
          hM: numOf(v['h']),
          color: (v['c'] is num) ? (v['c'] as num).toInt() : 0x8B93A5,
          objText: o,
        );
      });
    }
    return out;
  }

  /// 从 JS 赋值语句里截 `{…}`（first `{` .. last `}`）后 jsonDecode。
  static Map<String, dynamic>? _objectFromJs(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final j = jsonDecode(text.substring(start, end + 1));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }
}
