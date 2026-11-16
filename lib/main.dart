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
    getApplicationDocumentsDirectory().then((dir) {
      bootLog.attach(File('${dir.path}/jiajia_boot.log'));
      bootLog.line('bootlog-attached');
      if (bootLog.hasErrors) panel.value = bootLog.panelText();
    }).catchError((Object e) => bootLog.error('path_provider-failed: $e'));
    runApp(ErrorRoot(panel: panel, child: const ProviderScope(child: JiajiaApp())));
    bootLog.line('runApp-called');
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
            return Container(
              color: const Color(0xEE141821),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      '⚠ 运行异常 / 启动记录（把本屏截图发我即可定位）',
                      style: TextStyle(color: JiajiaColors.err, fontSize: 13)),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                            color: JiajiaColors.text1, fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: () => widget.panel.value = null,
                      child: const Text(
                          '关闭',
                          style: TextStyle(color: JiajiaColors.accent))),
                ],
              ),
            );
          },
        ),
      ],
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  static const _tabs = [
    (icon: Icons.edit, label: '画户型'),
    (icon: Icons.view_in_ar, label: '3D 浏览'),
  ];

  @override
  Widget build(BuildContext context) {
    bootLog.line('HomePage-built');
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const FloorplanEditorPage(),
          Viewer3dPage(active: _tab == 1),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon, size: 22),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
