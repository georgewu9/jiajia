import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jiajia/main.dart';

void main() {
  testWidgets('App 冒烟：落地页可构建，「开始画户型」能进编辑器', (tester) async {
    // 按真实根结构泵：main() 是 ErrorRoot(panel, ProviderScope(JiajiaApp()))。
    // 根级 bug 图标/诊断屏在 MaterialApp 之外、必须自带 Directionality，
    // 否则首帧 Icon.build 的 Directionality.of! 崩 → 白屏（v0.1.6 实锤根因）。
    final panel = ValueNotifier<String?>(null);
    await tester.pumpWidget(
      ErrorRoot(
        panel: panel,
        child: const ProviderScope(child: JiajiaApp()),
      ),
    );
    await tester.pump();
    expect(find.text('开始画户型'), findsOneWidget);
    expect(find.text('3D 浏览'), findsOneWidget);
    await tester.tap(find.text('开始画户型'));
    await tester.pumpAndSettle();
    // 编辑器工具条出现
    expect(find.text('画墙'), findsOneWidget);
    expect(find.text('家具'), findsOneWidget);
  });
}
