import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/theme.dart';
import 'diag/boot_log.dart' show bootLog;
import 'features/floorplan/domain/floor_plan.dart';
import 'features/floorplan/presentation/floorplan_editor.dart';
import 'features/floorplan/state/editor_doc.dart';
import 'features/viewer3d/viewer3d_page.dart';

/// jiajia：画户型 → 摆家具 → 3D 浏览。
void main() {
  // 外部原始探针：/sdcard/Android/data/com.georgewu.jiajia/files/jiajia_diag.txt
  // 系统在进程启动时就建好该目录（无需权限、不依赖 path_provider），
  // main() 第一行就能写；Kotlin Application 写同一文件 → 切分 NATIVE/DART 两层。
  bootLog.attachRaw(
    File('/sdcard/Android/data/com.georgewu.jiajia/files/jiajia_diag.txt'),
  );
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
    getApplicationDocumentsDirectory()
        .then((dir) {
          bootLog.attach(File('${dir.path}/jiajia_boot.log'));
          bootLog.line('bootlog-attached');
          if (bootLog.hasErrors) panel.value = bootLog.panelText();
        })
        .catchError((Object e) => bootLog.error('path_provider-failed: $e'));
    runZonedGuarded(
      () {
        runApp(
          ErrorRoot(
            panel: panel,
            child: const ProviderScope(child: JiajiaApp()),
          ),
        );
        bootLog.line('runApp-called');
      },
      (e, st) {
        bootLog.error('zone-async: $e\n$st');
      },
    );
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
    // 整个根包 Directionality：这里在 MaterialApp 之外（Directionality
    // 只由 MaterialApp 内部安装），缺了它 Stack/Icon/Text 全崩 → 白屏。
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
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
                child: const Icon(
                  Icons.bug_report,
                  size: 20,
                  color: JiajiaColors.accent,
                ),
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
      ),
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
            Text(
              title,
              style: const TextStyle(
                color: JiajiaColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(
                    color: JiajiaColors.text1,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClose,
                child: const Text(
                  '关闭',
                  style: TextStyle(color: JiajiaColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 落地页路由哨兵：从编辑器/3D 返回（任意路由 pop）时通知落地页刷新
/// 「我的户型」列表（刚保存过的方案要显示出来）。
class PlansRouteObserver extends RouteObserver<PageRoute> {
  void Function()? onPop;

  @override
  void didPop(Route route, Route? previousRoute) => onPop?.call();
}

final plansRouteObserver = PlansRouteObserver();

class JiajiaApp extends StatelessWidget {
  const JiajiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    bootLog.line('JiajiaApp-built');
    return MaterialApp(
      title: 'jiajia',
      theme: JiajiaTheme.dark,
      navigatorObservers: [plansRouteObserver],
      home: const LandingPage(),
    );
  }
}

/// 初始落地页：纯标准 Material widget（无 CustomPainter / 无 WebView），
/// 保证 release 下一定能画出来；户型编辑 / 3D 全部按需路由进入。
/// 含「我的户型」：打开/删除已保存的方案（本地 plans/*.json）。
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => LandingPageState();
}

class LandingPageState extends State<LandingPage> {
  final _store = PlanStore();
  List<PlanEntry> _plans = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    plansRouteObserver.onPop = _refresh; // 从编辑器/3D 返回 → 刷新列表
  }

  @override
  void dispose() {
    plansRouteObserver.onPop = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await _store.list(); // 环境不支持（单测）→ 空表
    if (mounted) {
      setState(() {
        _plans = list;
        _loading = false;
      });
    }
  }

  /// 打开已存户型：载入 → 替换编辑器文档 → 进编辑器。
  Future<void> _openPlan(BuildContext context, PlanEntry e) async {
    final p = await _store.loadPath(e.path);
    if (p == null || !context.mounted) return; // 文件损坏/丢失/页面已销毁
    ProviderScope.containerOf(context)
        .read(editorDocProvider.notifier)
        .replace(p);
    if (context.mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const FloorplanEditorPage()));
    }
  }

  Future<void> _deletePlan(PlanEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除「${e.name}」？'),
        content: const Text('户型、门窗洞和家具摆放都会一并删除，不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(e);
    await _refresh();
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month + 1)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    bootLog.line('LandingPage-built');
    final plansSection = _loading
        ? const Text('读取已存户型…',
            style: TextStyle(fontSize: 13, color: JiajiaColors.text2))
        : _plans.isEmpty
            ? const Text('还没有保存的户型。画完点编辑器右上角「保存」就会出现在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: JiajiaColors.text2))
            : Column(
                children: [
                  for (final e in _plans)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      leading: const Icon(Icons.architecture,
                          size: 20, color: JiajiaColors.accent),
                      title: Text(e.name,
                          style: const TextStyle(
                              fontSize: 14,
                              color: JiajiaColors.text1)),
                      subtitle: Text(
                          '${_fmtTime(e.mtime)} · ${(e.sizeBytes / 1024).toStringAsFixed(1)} KB',
                          style:
                              const TextStyle(fontSize: 11, color: JiajiaColors.text2)),
                      onTap: () => _openPlan(context, e),
                      trailing: IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: JiajiaColors.text2),
                        onPressed: () => _deletePlan(e),
                      ),
                    ),
                ],
              );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                    child: const Icon(
                      Icons.view_quilt,
                      size: 40,
                      color: JiajiaColors.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'jiajia',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: JiajiaColors.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '画户型 · 摆家具 · 3D 浏览',
                    style: TextStyle(fontSize: 14, color: JiajiaColors.text2),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 220,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: JiajiaColors.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        ProviderScope.containerOf(context)
                            .read(editorDocProvider.notifier)
                            .replace(FloorPlan()..name = '新建户型');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FloorplanEditorPage(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.draw,
                        size: 20,
                        color: JiajiaColors.bgBase,
                      ),
                      label: const Text(
                        '开始画户型',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: JiajiaColors.bgBase,
                        ),
                      ),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const Viewer3dPage()),
                      ),
                      icon: const Icon(
                        Icons.view_in_ar,
                        size: 20,
                        color: JiajiaColors.accent,
                      ),
                      label: const Text('3D 浏览', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // ---------------- 我的户型 ----------------
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('我的户型',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: JiajiaColors.text1)),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: plansSection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
