import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../app/i18n.dart';
import '../../../app/theme.dart';
import '../../../diag/boot_log.dart' show bootLog;
import '../floorplan/state/editor_doc.dart';
import '../floorplan/state/lib_models_store.dart';

/// 3D 浏览页：Three.js 跑在本地 WebView（离线资源 assets/web/），
/// 与 2D 编辑器共用同一份户型数据（editorDocProvider），编辑即实时同步。
///
/// 桥协议：
///  Dart → JS：window.jiajia.setPlan(jsonString) / setMode('top'|'orbit'|'first')
///  JS → Dart：channel 'dart' 收 {type:'ready'|'planLoaded'|'mode', ...}
class Viewer3dPage extends ConsumerStatefulWidget {
  /// 仅当所在 tab 激活时才真正创建 WebView（IndexedStack 启动即构建子树，
  /// 避免首帧就碰平台视图）。
  final bool active;
  const Viewer3dPage({super.key, this.active = true});

  @override
  ConsumerState<Viewer3dPage> createState() => _Viewer3dPageState();
}

class _Viewer3dPageState extends ConsumerState<Viewer3dPage> {
  WebViewController? _ctrl;

  /// 惰性创建（测试环境没有 webview 平台实现 → 返回 null，页面降级为占位）。
  WebViewController? _getCtrl() {
    final existing = _ctrl;
    if (existing != null) return existing;
    WebViewController c;
    try {
      bootLog.line('webview-creating');
      c = WebViewController()
        ..addJavaScriptChannel('dart', onMessageReceived: _onJsMessage)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              bootLog.line('webview-nav: $url');
            },
            onPageFinished: (url) {
              bootLog.line('webview-loaded: $url');
            },
            onWebResourceError: (err) {
              bootLog.error('webview-resource-error: ${err.description}'
                  ' url=${err.url}');
              if (mounted) {
                setState(() => _status = t('resource_load_failed', args: [
                      err.description,
                      err.errorType == WebResourceErrorType.fileNotFound
                          ? t('resource_missing')
                          : '',
                    ]));
              }
            },
          ),
        );
      (c.platform as AndroidWebViewController)
          .setJavaScriptMode(JavaScriptMode.unrestricted);
      // 资产在 APK 内是 flutter_assets/assets/web/…（pubspec 声明的是
      // assets/web/ 目录），loadFlutterAsset 需要带完整逻辑路径，
      // 写成 'web/viewer.html' 会 404 → 白板。
      c.loadFlutterAsset('assets/web/viewer.html');
    } catch (e) {
      bootLog.error('webview-failed: $e');
      return null; // 平台不可用（widget 测试环境）
    }
    _ctrl = c;
    bootLog.line('webview-created');
    return c;
  }
  bool _jsReady = false;
  String _mode = 'orbit';
  String _status = t('loading_3d');

  void _onJsMessage(JavaScriptMessage msg) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (j['type']) {
      case 'ready':
        setState(() {
          _jsReady = true;
          _status = t('ready_syncing');
        });
        _pushLang(); // v0.1.50：初始化先把 3D 覆盖层语言带上
        _pushPlan();
      case 'planLoaded':
        setState(() => _status = t('loaded_summary', args: [j['walls'], j['items']]));
      case 'mode':
        // JS 侧确认视角切换
        break;
      default:
        break;
    }
  }

  Future<void> _pushPlan() async {
    final c = _ctrl;
    if (c == null || !_jsReady) return;
    final plan = ref.read(editorDocProvider).plan;
    final data = plan.toJson();
    // 模型库：只下发本户型 items 引用到的条（OBJ 文本可达 MB 级，不能全量塞）。
    // 读库失败/库缺失 → 空数组，viewer.js 对 kind=lib 回退占位盒 + 名字。
    try {
      data['libs'] = await LibModelsStore.payloadForPlan(plan);
    } catch (_) {
      data['libs'] = const <Map<String, dynamic>>[];
    }
    final json = jsonEncode(data);
    // 第二参 lang：JS 侧 3D 文案/图例随语言重建（旧 viewer.js 忽略多余参数）。
    await c.runJavaScript(
        "window.jiajia.setPlan(${_jsStringLiteral(json)}, "
        "${_jsStringLiteral(ref.read(languageProvider))})");
  }

  /// 语言切换通道：JS 侧重建提示条/滑杆名/占位盒名字贴图。
  Future<void> _pushLang() async {
    final c = _ctrl;
    if (c == null || !_jsReady) return;
    await c.runJavaScript(
        'window.jiajia.setLang(${_jsStringLiteral(ref.read(languageProvider))})');
  }

  /// Dart 字符串 → JS 字符串字面量（双引号包裹 + 全量转义）。
  static String _jsStringLiteral(String s) {
    final e = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
    return '"$e"';
  }

  Future<void> _setMode(String m) async {
    setState(() => _mode = m);
    final c = _ctrl;
    if (c == null || !_jsReady) return;
    await c.runJavaScript("window.jiajia.setMode('$m')");
  }

  @override
  Widget build(BuildContext context) {
    // 2D 侧数据变了就同步给 3D
    ref.listen(editorDocProvider, (prev, next) => _pushPlan());

    ref.watch(languageProvider); // 切语言 → 状态文案/按钮重建
    // 切语言 → 同步给 3D 覆盖层（viewer.js STRINGS 重建）
    ref.listen(languageProvider, (prev, next) => _pushLang());
    final plan = ref.watch(editorDocProvider).plan;
    // 只有本页激活时才真正创建 WebView 平台视图（避免隐藏态下建平台视图）
    final ctrl = widget.active ? _getCtrl() : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('viewer3d_title')),
        actions: [
          Text(_status,
              style: const TextStyle(fontSize: 11, color: JiajiaColors.text3)),
          const SizedBox(width: 12),
        ],
      ),
      body: Stack(
        children: [
          if (ctrl != null)
            WebViewWidget(controller: ctrl)
          else
            Center(
              child: Text(
                  t('engine_unavailable',
                      args: [plan.walls.length, plan.items.length]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JiajiaColors.text2)),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: JiajiaColors.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _modeChip(t('mode_top'), 'top'),
                      _modeChip(t('mode_orbit'), 'orbit'),
                      _modeChip(t('mode_first'), 'first'),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: t('sync_2d'),
                        onPressed: _pushPlan,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, String m) {
    final active = _mode == m;
    return ActionChip(
      label: Text(label),
      backgroundColor: active ? JiajiaColors.accentSoft : JiajiaColors.raised,
      side: BorderSide(
          color: active ? JiajiaColors.accent : JiajiaColors.line),
      labelStyle: TextStyle(
          color: active ? JiajiaColors.accent : JiajiaColors.text1,
          fontSize: 13),
      onPressed: () => _setMode(m),
    );
  }
}
