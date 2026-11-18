import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';

/// 回归：RangeError (length) at _RoomActionBar.build
/// 根因：plan.roomLoops() 为空（房间被拆/墙被删后）时，旧代码回退到索引 0
/// 仍越界。修复：build 空列表直接 SizedBox.shrink()；_panEnd 切回选择时校验 _sel。
void main() {
  Future<(ProviderContainer, WidgetTester)> pumpEditor(
    WidgetTester tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FloorplanEditorPage()),
      ),
    );
    await tester.pump();
    return (container, tester);
  }

  testWidgets('选中房间后房间消失 → 底栏不崩（空 roomLoops 保护）', (tester) async {
    final (container, _) = await pumpEditor(tester);
    container.read(editorDocProvider.notifier).replace(
          FloorPlan()
            ..name = 't'
            ..addRoom(at: const Vec2(1, 1), l: 4, w: 3),
        );
    await tester.pump();
    expect(container.read(editorDocProvider).plan.roomLoops(), hasLength(1));

    // 切「选择」→ 点房间内部 → 选中房间，底部出拆/合/删操作条
    await tester.tap(find.text('选择'));
    await tester.pump();
    const ppm = 90.0, panX = 80.0, panY = 80.0; // 相机初始值
    final inside = const Offset(3 * ppm + panX, 2.5 * ppm + panY);
    final tapGlobal =
        tester.getRect(find.byKey(const ValueKey('cv'))).topLeft + inside;
    await tester.tapAt(tapGlobal);
    await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口
    await tester.pump();
    expect(find.text('拆房'), findsOneWidget, reason: '选中房间应出房间操作条');

    // 房间消失（相当于删墙/拆房后 _sel 仍是 room）→ 重建底栏
    container.read(editorDocProvider.notifier).mutate((p) => p.walls.clear());
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: '空 roomLoops 不得再 RangeError');
    expect(container.read(editorDocProvider).plan.roomLoops(), isEmpty);
    expect(find.text('拆房'), findsNothing, reason: '房间没了，操作条应消失');
  });
}
