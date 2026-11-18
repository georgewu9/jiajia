import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/theme.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';

/// 回归两个工具栏交互 bug：
///  ① 「建房」与「画墙」高亮必须互不影响（旧代码两个 chip 都拿
///     EditorTool.wall 做高亮条件 → 按一个两个都亮）。
///  ② 完成「建房」或「画墙」操作后自动切回「选择」工具。
///
/// 断言方式：读 ActionChip 的 backgroundColor —— 高亮 = accentSoft，
/// 未高亮 = raised（与 _toolChip 的实现一致）。
void main() {
  Future<WidgetTester> pumpEditorTall(WidgetTester tester) async {
    // 建房面板在 800×600 测试视口里会落到屏幕下沿之外（点不到），
    // 故加高视口（沿用 room_snap_test / persist_ui_test 的做法）。
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FloorplanEditorPage()),
    ));
    await tester.pump();
    return tester;
  }

  /// 取某个底栏 chip 的高亮状态（true = 高亮）。
  bool chipLit(WidgetTester tester, String label) {
    final chip = tester.widget<ActionChip>(
      find
          .ancestor(of: find.text(label), matching: find.byType(ActionChip))
          .first,
    );
    return chip.backgroundColor == JiajiaColors.accentSoft;
  }

  testWidgets('「画墙」和「建房」高亮互不影响', (tester) async {
    await pumpEditorTall(tester);

    // 初始工具 = 画墙：只有「画墙」亮，「建房」不亮
    // （旧 bug：建房 chip 也用 EditorTool.wall → 两个同时亮）
    expect(chipLit(tester, '画墙'), true, reason: '默认应为画墙工具');
    expect(chipLit(tester, '建房'), false, reason: '建房不应跟着画墙一起亮');

    // 切到「选择」：只有「选择」亮
    await tester.tap(find.text('选择'));
    await tester.pump();
    expect(chipLit(tester, '选择'), true);
    expect(chipLit(tester, '画墙'), false);
    expect(chipLit(tester, '建房'), false);

    // 打开「建房」面板：只有「建房」亮
    await tester.tap(find.text('建房'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
    expect(chipLit(tester, '建房'), true, reason: '建房面板打开时建房应高亮');
    expect(chipLit(tester, '画墙'), false, reason: '画墙不应被建房点亮');
    expect(chipLit(tester, '选择'), false);

    // 关掉面板 → 恢复「选择」高亮
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(chipLit(tester, '选择'), true);
    expect(chipLit(tester, '建房'), false);
  });

  testWidgets('建房完成 → 自动切回「选择」工具', (tester) async {
    await pumpEditorTall(tester);
    await tester.tap(find.text('建房'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // DSS 动画
    await tester.tap(find.text('创建房间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 建房后应自动回「选择」，无需用户手动切
    expect(chipLit(tester, '选择'), true, reason: '建房完成后应自动回选择');
    expect(chipLit(tester, '建房'), false);
    expect(chipLit(tester, '画墙'), false);
  });

  testWidgets('画完一面墙 → 自动切回「选择」工具', (tester) async {
    await pumpEditorTall(tester);
    expect(chipLit(tester, '画墙'), true, reason: '默认应为画墙工具');

    // 画布中心单指拖 → 生成一面墙
    await tester.drag(find.byKey(const ValueKey('cv')), const Offset(300, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(chipLit(tester, '选择'), true, reason: '画完墙应自动回选择');
    expect(chipLit(tester, '画墙'), false);
  });
}
