import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'features/floorplan/presentation/floorplan_editor.dart';
import 'features/viewer3d/viewer3d_page.dart';

/// jiajia：画户型 → 摆家具 → 3D 浏览。
void main() {
  runApp(const ProviderScope(child: JiajiaApp()));
}

class JiajiaApp extends StatelessWidget {
  const JiajiaApp({super.key});

  @override
  Widget build(BuildContext context) {
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
    final pages = [
      const FloorplanEditorPage(),
      const Viewer3dPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
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
