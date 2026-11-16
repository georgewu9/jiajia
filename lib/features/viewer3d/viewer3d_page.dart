import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../floorplan/state/editor_doc.dart';

/// 3D 浏览页（M3：Three.js WebView 真场景；当前为占位 + 数据预览）。
class Viewer3dPage extends ConsumerWidget {
  const Viewer3dPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(editorDocProvider).plan;
    final json = plan.toJsonString();
    return Scaffold(
      appBar: AppBar(title: const Text('3D 浏览')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.view_in_ar,
                  size: 48, color: JiajiaColors.accent),
              const SizedBox(height: 12),
              const Text('3D 场景即将上线（M3）',
                  style: TextStyle(color: JiajiaColors.text1, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                  '${plan.walls.length} 面墙 · ${plan.items.length} 件家具 · ${plan.openings.length} 个开洞',
                  style: const TextStyle(color: JiajiaColors.text2, fontSize: 13)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JiajiaColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: JiajiaColors.line),
                ),
                child: SelectableText(
                  json,
                  style: const TextStyle(
                      color: JiajiaColors.text2,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
