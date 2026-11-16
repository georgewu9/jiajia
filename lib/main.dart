import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/theme.dart';
import 'diag/boot_log.dart' show bootLog;
import 'features/floorplan/presentation/floorplan_editor.dart';
import 'features/viewer3d/viewer3d_page.dart';

/// jiajia：画户型 → 摆家具 → 3D 浏览。
void main() {
  // 外部原始探针：/sdcard/Android/data/com.georgewu.jiajia/files/jiajia_diag.txt
  // 系统在进程启动时就建好该目录（无需权限、不依赖 path_provider），
  // main() 第一行就能写；Kotlin Application 写同一文件 → 切分 NATIVE/DART 两层。
  bootLog.attachRaw(File('/sdcard/Android/data/com.georgewu.jiajia/files/jiajia_diag.txt'));
  bootLog.line('main-start');
  final panel = ValueNotifier<String?>(null);
  // 根级护栏：树里任何位置（含 JiajiaApp.build / theme / MaterialApp）的
  // build 异常都被接住 → 面板可见，不再静默白屏。
  FlutterError.onError = (d) {
    final msg = '${d.exception}\n${d.stack}';
    bootLog.error('FlutterError: $msg');
    panel.value = bootLog.panelText(liveError: '${d.exception}');
  };
  FlutterError.presentError = (d) => bootLog.error('present: ${d.exception}');
  try {
    WidgetsFlutterBinding.ensureInitialized();
    bootLog.line('binding-init');
    getApplicationDocumentsDirectory().then((dir) {
      bootLog.attach(File('${dir.path}/jiajia_boot.log'));
      bootLog.line('bootlog-attached');
      if (bootLog.hasErrors) panel.value = bootLog.panelText();
    }).catchError((Object e) => bootLog.error('path_provider-failed: $e'));
    runZonedGuarded(() {
      runApp(ErrorRoot(panel: panel, child: const ProviderScope(child: JiajiaApp())));
      bootLog.line('runApp-called');
    }, (e, st) {
      bootLog.error('zone-async: $e\n$st');
    });
  } catch (e, st) {
    bootLog.error('main-crash: $e\n$st');
    panel.value = bootLog.panelText();
  }
}

/// 包住整个 runApp 树的错误面板：即使子树死掉也能画出来。
class ErrorRoot extends StatefulWidget {
  final ValueNotifier<String?> panel;
  final Widget child;
  const ErrorRoot({super.key, required this.panel, required this.child});

  @override
  State<ErrorRoot> createState() => _ErrorRootState();
}

class _ErrorRootState extends State<ErrorRoot> {
  bool _showDiag = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) bootLog.line('first-frame');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<String?>(
          valueListenable: widget.panel,
          builder: (context, text, _) {
            if (text == null) return const SizedBox.shrink();
            return _DiagnosticScreen(
              title: '⚠ 运行异常 / 启动记录（截图发我即可定位）',
              content: text,
              onClose: () => widget.panel.value = null,
            );
          },
        ),
        // 诊断按钮：根级，即使下层界面全坏也能点
        Positioned(
          right: 12,
          bottom: 88,
          child: GestureDetector(
            onTap: () => setState(() => _showDiag = !_showDiag),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JiajiaColors.raised,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: JiajiaColors.accent),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.bug_report,
                  size: 20, color: JiajiaColors.accent),
            ),
          ),
        ),
        if (_showDiag)
          _DiagnosticScreen(
            title: '启动诊断（长按文本可复制；截图发我）',
            content: bootLog.panelText(liveError: widget.panel.value),
            onClose: () => setState(() => _showDiag = false),
          ),
      ],
    );
  }
}

/// 全屏诊断文本屏（SelectableText，截图即诊断数据）。
class _DiagnosticScreen extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onClose;
  const _DiagnosticScreen({
    required this.title,
    required this.content,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xF2141821),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: const TextStyle(
                    color: JiajiaColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(
                      color: JiajiaColors.text1,
                      fontSize: 11,
                      height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClose,
                child: const Text('关闭',
                    style: TextStyle(color: JiajiaColors.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class JiajiaApp extends StatelessWidget {
  const JiajiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog.line('JiajiaApp-built');
    return MaterialApp(
      title: 'jiajia',
      theme: JiajiaTheme.dark,
      home: const LandingPage(),
    );
  }
}

/// 初始落地页：纯标准 Material widget（无 CustomPainter / 无 WebView），
/// 保证 release 下一定能画出来；户型编辑 / 3D 全部按需路由进入。
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog.line('LandingPage-built');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: JiajiaColors.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.view_quilt,
                      size: 40, color: JiajiaColors.accent),
                ),
                const SizedBox(height: 16),
                const Text(
                  'jiajia',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: JiajiaColors.text1),
                ),
                const SizedBox(height: 6),
                const Text('画户型 · 摆家具 · 3D 浏览',
                    style: TextStyle(fontSize: 14, color: JiajiaColors.text2)),
                const SizedBox(height: 40),
                SizedBox(
                  width: 220,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: JiajiaColors.accent,
                      padding:
                          const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const FloorplanEditorPage())),
                    icon: const Icon(Icons.draw, size: 20, color: JiajiaColors.bgBase),
                    label: const Text('开始画户型',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: JiajiaColors.bgBase)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 220,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: JiajiaColors.text1,
                      side: const BorderSide(color: JiajiaColors.line),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const Viewer3dPage())),
                    icon: const Icon(Icons.view_in_ar,
                        size: 20, color: JiajiaColors.accent),
                    label: const Text('3D 浏览',
                        style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
