import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/i18n.dart';

/// v0.1.50 第二轮：3D 视图层（assets-web）双语。
///
/// 只锁三件事：
///   1. viewer.js 的 STRINGS 表 zh/en key 一致、英文不含中文；
///   2. models.js 每条带 n_en/cat_en，且与 Dart 词表 asset-ID 逐字一致
///      （中文 n/cat 仍是数据键，不能被翻译污染）；
///   3. Dart→JS 语言通道齐备（初始化 setPlan 带 lang + 切语言 setLang）。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  Map<String, String> stringsOf(String js, String lang) {
    final m = RegExp('\\b$lang:\\s*\\{([\\s\\S]*?)\\n    \\}').firstMatch(js);
    final block = m?.group(1);
    if (block == null) throw StateError('viewer.js STRINGS 缺 $lang 表');
    final out = <String, String>{};
    for (final hit in RegExp("\"([a-z_]+)\":\\s*'([^']*)'").allMatches(block)) {
      out[hit.group(1)!] = hit.group(2)!;
    }
    return out;
  }

  test('viewer.js STRINGS：zh/en key 一致，英文表零中文，提示条走词表', () {
    final js = read('assets/web/viewer.js');
    final zh = stringsOf(js, 'zh');
    final en = stringsOf(js, 'en');

    expect(zh.length, 12, reason: '3D 覆盖层文案 12 条');
    expect(en.length, zh.length);
    expect(en.keys.toSet(), zh.keys.toSet());

    final cjk = RegExp(r'[\u4e00-\u9fff]');
    for (final k in zh.keys) {
      expect(cjk.hasMatch(zh[k]!), true, reason: 'zh[$k] 应是中文');
      expect(cjk.hasMatch(en[k]!), false, reason: 'en[$k] 混入中文：${en[k]}');
      expect(en[k]!.trim().isEmpty, false, reason: 'en[$k] 为空');
    }
    // 关键覆盖：等待/三种视角/滑杆/方向键/占位盒回退名
    for (final k in [
      'hint_wait',
      'hint_first',
      'hint_top',
      'hint_orbit',
      'fov',
      'eye',
      'dp_up',
      'dp_down',
      'lib_default',
      'model_missing',
    ]) {
      expect(zh.containsKey(k), true, reason: '缺 $k');
    }

    // 文案不再硬编码：hint 统一由 updateHint()/applyLang() 写
    expect(js.contains("textContent = '等待户型数据"), false,
        reason: 'hint 应走 STRINGS，不再硬编码中文');
    expect(js.contains("isFirst ? '方向键移动"), false,
        reason: 'setMode 提示条应走 updateHint()');
    expect(js.contains('function updateHint()'), true);
    expect(js.contains('setLang: setLang'), true, reason: '缺 JS 侧 setLang 入口');
    expect(js.contains('modelName(m)'), true, reason: 'models.js 英文名应被消费');

    // viewer.html：滑杆标签有 id 供语言切换改写
    final html = read('assets/web/viewer.html');
    expect(html.contains('id="fovLab"'), true);
    expect(html.contains('id="eyeLab"'), true);
  });

  test('models.js：26 条带 n_en/cat_en，与 Dart 词表一致；语言通道齐备', () {
    final txt = read('assets/web/models.js');
    final data = jsonDecode(txt.substring(txt.indexOf('{'), txt.lastIndexOf('}') + 1))
        as Map<String, dynamic>;
    expect(data.length, 26);

    final cjk = RegExp(r'[\u4e00-\u9fff]');
    final catEn = <String>{};
    for (final id in data.keys) {
      final e = data[id] as Map<String, dynamic>;
      // 数据键保持中文（序列化 / 旧数据 / 3D 分类判断都用它）
      expect(cjk.hasMatch(e['n'] as String), true, reason: '$id 的 n 应是中文原名');
      expect(cjk.hasMatch(e['cat'] as String), true, reason: '$id 的 cat 应是中文分类');
      // 显示层英文
      expect((e['n_en'] as String?)?.trim().isNotEmpty, true, reason: '$id 缺 n_en');
      expect((e['cat_en'] as String?)?.trim().isNotEmpty, true,
          reason: '$id 缺 cat_en');
      expect(cjk.hasMatch(e['n_en'] as String), false,
          reason: '$id 的 n_en 混入中文');
      expect(cjk.hasMatch(e['cat_en'] as String), false,
          reason: '$id 的 cat_en 混入中文');
      // 与 Dart 词表同源：不许两边文案漂移
      expect(e['n_en'], AppI18n.t('asset_$id', lang: 'en'), reason: '$id 英文名与词表不一致');
      expect(AppI18n.t('asset_$id', lang: 'zh'), e['n'], reason: '$id 中文名与词表不一致');
      catEn.add(e['cat_en'] as String);
    }
    expect(catEn, {'Door', 'Hardware', 'Cabinet', 'Railing', 'Column', 'Wall', 'Base'});

    // Dart→JS 通道：初始化 setPlan(json, lang) + 切换 setLang(lang) + ready 时先推语言
    final page = read('lib/features/viewer3d/viewer3d_page.dart');
    expect(page.contains('window.jiajia.setPlan(\${_jsStringLiteral(json)}, '), true,
        reason: 'setPlan 应带上 lang');
    expect(page.contains('window.jiajia.setLang('), true,
        reason: '语言切换应推 setLang');
    expect(page.contains('_pushLang();'), true, reason: 'ready 时应先推语言');
    expect(page.contains('ref.listen(languageProvider'), true,
        reason: '语言变化应触发 JS 重建');
  });
}
