import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/app/i18n.dart';
import 'package:jiajia/app/theme.dart';
import 'package:jiajia/features/viewer3d/viewer3d_page.dart';

/// 3D 视图页「横屏顶栏紧凑化」：横屏可视高度矮（横屏 600 逻辑高、竖屏 800+），
/// 顶栏 + 底部视角 chips 条吃掉的可视区比例更大 —— 横屏下 toolbar 压到 36、
/// 标题/状态字号缩小、视角条内边距收紧；竖屏必须与原行为逐项一致（防回归）。
///
/// 断言口径：
///   · AppBar 渲染高度 = toolbarHeight + 状态栏 padding（Scaffold 的 AppBar
///     走 primary:true → SafeArea top），所以带 MIUI 式 top=24 inset 一起测。
///   · 字号直接读 Text/ActionChip 的 style（主题默认标题 16、状态 11、chips 13）。
///   · 底部视角条高度 = 上下 padding + chips 高度 + SafeArea bottom。
void main() {
  // 复刻真机横/竖屏视口：横屏 1200×600、竖屏 600×800（dpr=1，逻辑像素）。
  // 另加 top=24 / bottom=16 的模拟系统栏 inset（MIUI 状态栏 + 手势条）。
  const landscapeSize = Size(1200, 600);
  const portraitSize = Size(600, 800);
  const topInset = 24.0;
  const bottomInset = 16.0;

  Future<void> pumpViewer(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding =
        const FakeViewPadding(top: topInset, bottom: bottomInset);
    tester.view.viewPadding =
        const FakeViewPadding(top: topInset, bottom: bottomInset);
    addTearDown(() {
      tester.view.reset();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      // 真机外壳：JiajiaTheme.light（主题 AppBar 标题 16px）
      child: MaterialApp(theme: JiajiaTheme.light, home: const Viewer3dPage()),
    ));
    await tester.pump();
  }

  double appBarHeight(WidgetTester tester) =>
      tester.getSize(find.byType(AppBar)).height;

  double titleFontSize(WidgetTester tester) {
    final text = tester.widget<Text>(find.text(t('viewer3d_title')));
    final explicit = text.style?.fontSize;
    if (explicit != null) return explicit;
    // 竖屏不覆盖 style → 落到 AppBar 的 DefaultTextStyle（主题 titleTextStyle 16）
    final ctx = tester.element(find.text(t('viewer3d_title')));
    return DefaultTextStyle.of(ctx).style.fontSize ?? -1;
  }

  double statusFontSize(WidgetTester tester) => tester
      .widget<Text>(find.text(t('loading_3d')))
      .style
      ?.fontSize ??
      -1;

  double chipFontSize(WidgetTester tester) =>
      tester.widget<ActionChip>(find.byType(ActionChip).first)
          .labelStyle
          ?.fontSize ??
      -1;

  double modeBarHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('viewer3d_mode_bar'))).height;

  testWidgets('横屏：顶栏压到 36、字号缩小、视角条收紧，画布从状态栏下开始',
      (tester) async {
    await pumpViewer(tester, landscapeSize);

    // 顶栏 = 36（toolbar）+ 24（状态栏）＝ 60，比竖屏的 80 矮 20px。
    expect(appBarHeight(tester), 60);
    // 竖屏主题标题 16 → 横屏 13；状态 11 → 10；chips 13 → 12。
    expect(titleFontSize(tester), 13);
    expect(statusFontSize(tester), 10);
    expect(chipFontSize(tester), 12);
    // 视角条：上下 padding 各 4（原 8）→ 比竖屏矮 8px；底部 SafeArea 仍在。
    // 16（手势条）+ 4 + 48（chips）+ 4 = 72，竖屏同口径 80。
    expect(modeBarHeight(tester), 72);
    debugPrint('landscape: appbar=60 (36+24)  modeBar=72');
    debugPrint('portrait : appbar=80 (56+24)  modeBar=80');

    // 画布（此处降级占位）起点必须落在顶栏之下 = 状态栏之下，没被系统栏吃掉。
    final bodyTop = tester.getTopLeft(find.byType(Stack).first).dy;
    expect(bodyTop, 60);

    // 横屏 AppBar 只有一行、且没有溢出（超长标题/状态文字不撑破 36）。
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖屏：顶栏/字号/视角条与改造前逐项一致', (tester) async {
    await pumpViewer(tester, portraitSize);

    // 56（kToolbarHeight）+ 24（状态栏）＝ 80。
    expect(appBarHeight(tester), 80);
    expect(titleFontSize(tester), 16); // 主题 titleTextStyle
    expect(statusFontSize(tester), 11);
    expect(chipFontSize(tester), 13);
    // 视角条 = 16（手势条）+ 8 + 48（chips）+ 8 = 80；横屏同口径 72。
    expect(modeBarHeight(tester), 80);
    expect(tester.takeException(), isNull);
  });
}
