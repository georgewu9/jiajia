import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../app/theme.dart';
import '../floorplan/state/editor_doc.dart';

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
      c = WebViewController()
        ..addJavaScriptChannel('dart', onMessageReceived: _onJsMessage);
      (c.platform as AndroidWebViewController)
          .setJavaScriptMode(JavaScriptMode.unrestricted);
      c.loadFlutterAsset('web/viewer.html');
    } catch (_) {
      return null; // 平台不可用（widget 测试环境）
    }
    _ctrl = c;
    return c;
  }
  bool _jsReady = false;
  String _mode = 'orbit';
  String _status = '加载 3D 场景…';

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
          _status = '就绪 · 同步中';
        });
        _pushPlan();
      case 'planLoaded':
        setState(() => _status =
            '已加载 ${j['walls']} 面墙 · ${j['items']} 件家具');
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
    final json = ref.read(editorDocProvider).plan.toJsonString();
    await c.runJavaScript(
        "window.jiajia.setPlan(${_jsStringLiteral(json)})");
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

    final plan = ref.watch(editorDocProvider).plan;
    final ctrl = _getCtrl();

    return Scaffold(
      appBar: AppBar(
        title: const Text('3D 浏览'),
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
                  '3D 引擎不可用（测试环境）\n墙 ${plan.walls.length} · 家具 ${plan.items.length}',
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
                      _modeChip('俯视', 'top'),
                      _modeChip('轨道', 'orbit'),
                      _modeChip('第一视角', 'first'),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: '同步 2D 编辑',
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
