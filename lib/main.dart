import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'features/floorplan/presentation/floorplan_editor.dart';
import 'features/viewer3d/viewer3d_page.dart';

/// jiajia：画户型 → 摆家具 → 3D 浏览。
void main() {
  final errNotif = ValueNotifier<String?>(null);
  // 白屏自救：任何 build/运行时异常都在这里被接住，屏幕上直接可见
  FlutterError.onError = (details) {
    errNotif.value = '${details.exception}\n\n${details.stack}';
    debugPrint('jiajia error: ${details.exception}');
  };
  runApp(
    ProviderScope(
      child: JiajiaApp(errNotif: errNotif),
    ),
  );
}

class JiajiaApp extends StatelessWidget {
  final ValueNotifier<String?> errNotif;
  const JiajiaApp({super.key, required this.errNotif});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'jiajia',
      theme: JiajiaTheme.dark,
      home: Stack(
        children: [
          const HomePage(),
          // 设备侧错误面板（release 白屏时能直接看到异常文本）
          ValueListenableBuilder<String?>(
            valueListenable: errNotif,
            builder: (context, err, _) {
              if (err == null) return const SizedBox.shrink();
              return Container(
                color: const Color(0xEE141821),
                padding: const EdgeInsets.all(16),
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠ 运行异常（发截图给我即可定位）',
                        style: TextStyle(color: JiajiaColors.err, fontSize: 13)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SelectableText(
                        err,
                        style: const TextStyle(
                            color: JiajiaColors.text1, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => errNotif.value = null,
                        child: const Text('忽略',
                            style: TextStyle(color: JiajiaColors.accent))),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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
