import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/diag/boot_log.dart';
import 'package:jiajia/main.dart';

/// 启动诊断页回归测试。
/// 1) 「上次崩过 → 本次自动弹日志页」的判据（不能被普通启动误触发）。
/// 2) 日志页「关闭」按钮必须可点，且抬到系统导航栏（SafeArea）之上。
void main() {
  group('BootLog.hasErrors（自动弹面板判据）', () {
    late Directory dir;
    late File logFile;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jj_bootlog_test');
      logFile = File('${dir.path}/jiajia_boot.log');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('上次启动干净（只有里程碑）→ 不弹日志页', () {
      // 模拟上一次运行：attach 后写了几条里程碑，正常退出（无 ERR）
      final prevRun = BootLog()
        ..line('main-start')
        ..line('binding-init');
      prevRun.attach(logFile);
      prevRun
        ..line('bootlog-attached')
        ..line('first-frame');

      // 本次运行：照 main() 的顺序，先写里程碑再 attach
      final thisRun = BootLog()
        ..line('main-start')
        ..line('binding-init');
      thisRun.attach(logFile);

      expect(thisRun.hasErrors, isFalse);
    });

    test('上次运行崩过（日志里有 RangeError）→ 弹日志页', () {
      final prevRun = BootLog()..line('main-start');
      prevRun.attach(logFile);
      prevRun.error(
        'zone-async: RangeError (index): Invalid value: 3\n#0 _RoomActionBar',
      );

      final thisRun = BootLog()..line('main-start');
      thisRun.attach(logFile);

      expect(thisRun.hasErrors, isTrue);
      // 面板必须带上上次的崩溃堆栈（用户就靠这个截图定位）
      expect(thisRun.panelText(), contains('RangeError'));
    });

    test('本次会话刚写异常 → 判定为需要弹面板', () {
      final b = BootLog()..line('main-start');
      b.attach(logFile);
      expect(b.hasErrors, isFalse);
      b.error('main-crash: Foo');
      expect(b.hasErrors, isTrue);
    });
  });

  group('诊断页 UI（关闭按钮可点）', () {
    const btnKey = ValueKey('diag_close_btn');
    const xKey = ValueKey('diag_close_x');

    Future<ValueNotifier<String?>> pumpDiag(
      WidgetTester tester, {
      EdgeInsets padding = EdgeInsets.zero,
    }) async {
      final panel = ValueNotifier<String?>('【启动记录】\n[time] main-start');
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: const Size(800, 600), padding: padding),
          child: ErrorRoot(panel: panel, child: const SizedBox.shrink()),
        ),
      );
      await tester.pump();
      return panel;
    }

    testWidgets('点右下角「关闭」→ 面板清空、诊断页消失', (tester) async {
      final panel = await pumpDiag(tester);
      expect(find.byType(SelectableText), findsOneWidget);

      // v0.1.48：accent 实心底按钮统一白字前景（诊断屏「关闭」也是 accent 底）
      final close = tester.widget<FilledButton>(find
          .ancestor(
            of: find.text('关闭'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          )
          .first);
      expect(
        close.style?.foregroundColor?.resolve(const <WidgetState>{}),
        Colors.white,
      );

      await tester.tap(find.byKey(btnKey));
      await tester.pump();

      expect(panel.value, isNull);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('关闭按钮落在系统导航栏之上（SafeArea 生效）', (tester) async {
      // 模拟 Android 手势条/三键导航栏占底部 48dp
      final panel = await pumpDiag(
        tester,
        padding: const EdgeInsets.only(bottom: 48),
      );
      expect(panel.value, isNotNull);

      final rect = tester.getRect(find.byKey(btnKey));
      // 旧版无 SafeArea：按钮底边 ≈ 592（压在 552~600 的导航栏里）→ 点不到
      expect(rect.bottom, lessThanOrEqualTo(600 - 48));
      // 热区要够大（旧 TextButton 只有 ~36 高）
      expect(rect.height, greaterThanOrEqualTo(48));
    });

    testWidgets('右上角 ✕ 也能关', (tester) async {
      final panel = await pumpDiag(tester);
      await tester.tap(find.byKey(xKey));
      await tester.pump();
      expect(panel.value, isNull);
    });

    testWidgets('点空白处也能关（兜底退出路径）', (tester) async {
      final panel = await pumpDiag(tester);
      await tester.tapAt(const Offset(400, 4));
      await tester.pump();
      expect(panel.value, isNull);
    });

    testWidgets('长按复制能力仍在：SelectableText 未被替换', (tester) async {
      await pumpDiag(tester);
      final st = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(st.data, contains('main-start'));
    });

    testWidgets('长按可选文本/复制（旧版因缺 Overlay 长按即崩）', (tester) async {
      final panel = await pumpDiag(tester);
      await tester.longPress(find.byType(SelectableText));
      await tester.pump(const Duration(milliseconds: 300));
      // 诊断屏自带 Overlay → 选择手柄/复制菜单能挂上去，不再抛
      // "No Overlay widget found"
      expect(tester.takeException(), isNull);
      // 长按是选择手势，不应被「点空白关闭」误伤
      expect(panel.value, isNotNull);
    });

    testWidgets('小屏 360×640 + 超长日志：不溢出、关闭仍可点', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final panel = ValueNotifier<String?>(
        List.generate(120, (i) => '[t] 第 $i 行 RangeError (index)').join('\n'),
      );
      await tester.pumpWidget(
        ErrorRoot(panel: panel, child: const SizedBox.shrink()),
      );
      await tester.pump();

      // 任何 RenderFlex 溢出都会被 flutter_test 记为失败，这里额外确认按钮在屏内
      expect(panel.value, isNotNull);
      final rect = tester.getRect(find.byKey(btnKey));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.width, greaterThan(100));

      await tester.tap(find.byKey(btnKey));
      await tester.pump();
      expect(panel.value, isNull);
    });
  });
}
