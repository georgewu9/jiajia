import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jiajia/app/i18n.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/domain/furniture_tabs.dart';
import 'package:jiajia/features/floorplan/domain/model_items.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/main.dart';

/// v0.1.50 双语（B 方案）验收：默认 zh 的 241 处中文断言在其它测试里不动，
/// 这里只覆盖「切到 EN 后 UI 真的变英文 + 切回中文恢复 + 语言落盘」。
///
/// 视口压到 360×740（常见手机宽）：英文文案宽度是中文的 1.5~2.5 倍，
/// 任何溢出都会以 FlutterError 形式抛给 tester.takeException() → 用例变红。
void main() {
  setUp(() {
    // 静态语言是全局状态：每个用例从 zh 起跑，避免相互污染。
    AppI18n.lang = AppI18n.zh;
  });

  Future<void> pumpLanding(WidgetTester tester) async {
    final panel = ValueNotifier<String?>(null);
    await tester.pumpWidget(
      ErrorRoot(panel: panel, child: const ProviderScope(child: JiajiaApp())),
    );
    await tester.pump();
  }

  Future<ProviderContainer> pumpEditorAt360(WidgetTester tester) async {
    // 宽压到 360（溢出的高发宽度），高留足 1200 让底部面板按钮都在屏内
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FloorplanEditorPage()),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('封面：中 → EN 切英文（CTA/标语/我的户型），切回中恢复', (tester) async {
    await pumpLanding(tester);
    expect(find.text('开始画户型'), findsOneWidget);
    expect(find.text('画户型 · 摆家具 · 3D 浏览'), findsOneWidget);

    await tester.tap(find.text('EN'));
    await tester.pump();
    expect(AppI18n.lang, 'en');
    expect(find.text('Start Drawing'), findsOneWidget);
    expect(find.text('Draw plans · Place furniture · 3D view'), findsOneWidget);
    expect(find.text('My Plans'), findsOneWidget);
    expect(find.text('开始画户型'), findsNothing, reason: 'EN 态不应残留中文 CTA');

    await tester.tap(find.text('中'));
    await tester.pump();
    expect(AppI18n.lang, 'zh');
    expect(find.text('开始画户型'), findsOneWidget);
    expect(find.text('Start Drawing'), findsNothing);
    expect(tester.takeException(), isNull, reason: '360 宽切换不应溢出');
  });

  testWidgets('编辑器底栏：EN 下「选择/画墙/建房/模块」变 Select/Wall/Room/Modules', (tester) async {
    final container = await pumpEditorAt360(tester);
    await container.read(languageProvider.notifier).set('en');
    await tester.pump();
    await tester.pump();

    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Wall'), findsOneWidget);
    expect(find.text('Room'), findsOneWidget);
    expect(find.text('选择'), findsNothing);
    // 底栏是横向 ListView（懒构建）：滚到右端确认「模块 → Modules」也翻了
    await tester.drag(find.text('Room'), const Offset(-160, 0));
    await tester.pump();
    expect(find.text('Modules'), findsOneWidget);
    // 10~11px 说明小字（空画布引导）也必须是英文且不溢出
    expect(find.textContaining('Tap "Wall"'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '英文底栏/引导不应溢出');

    await container.read(languageProvider.notifier).set('zh');
    await tester.pump();
    expect(find.text('选择'), findsOneWidget);
    expect(find.text('Select'), findsNothing);
  });

  testWidgets('家具抽屉：EN 下分类/目录家具名变英文（Bedroom、Wardrobe…）', (tester) async {
    final container = await pumpEditorAt360(tester);
    await container.read(languageProvider.notifier).set('en');
    await tester.pump();
    await tester.pump();

    await tester.drag(find.text('Room'), const Offset(-160, 0));
    await tester.pump();
    await tester.tap(find.text('Modules'));
    await tester.pump(const Duration(milliseconds: 300));
    // 模块面板是半屏 DSS：英文入口块更宽 → 先确保「家具」入口可见
    await tester.ensureVisible(find.text('Furniture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Furniture'));
    await tester.pump(const Duration(milliseconds: 300));

    // 标题：家具 · 卧室（11 件）→ Furniture · Bedroom (11)
    expect(find.textContaining('Furniture · Bedroom'), findsOneWidget);
    // 分类 chips 全英文
    expect(find.text('Bedroom'), findsOneWidget);
    expect(find.text('Living & Dining'), findsOneWidget);
    // 目录家具名：kind:bed / kind:wardrobe 落成 Bed / Wardrobe
    expect(find.text('Bed'), findsWidgets);
    expect(find.text('Wardrobe'), findsWidgets);
    expect(find.text('卧室'), findsNothing);
    expect(tester.takeException(), isNull, reason: '英文家具抽屉不应溢出');

    // 领域层取值同样按语言走（tile 之外的 2D 标注/操作条共用同一 getter）
    expect(FurnitureCatalog.labelOf(FurnitureKind.sofa), 'Sofa');
    expect(ModelItems.byId('m_furn_desk')!.label, 'Desk');
    expect(FurnitureTabs.catLabel('厨卫'), 'Kitchen & Bath');
  });

  testWidgets('房间/墙体操作条 + 物品编辑框：EN 下短标签、360 宽不溢出', (tester) async {
    final container = await pumpEditorAt360(tester);
    await container.read(languageProvider.notifier).set('en');
    // 直接注入示例户型（5m×4m 一间房 + 若干家具），走相机 fit 省掉建房面板
    container.read(editorDocProvider.notifier).replace(samplePlan());
    await tester.pump();

    final cRect = tester.getRect(find.byKey(const ValueKey('cv')));
    // 编辑器初始相机：ppm = 90 px/m，pan = (80, 80)（CameraCtrl 默认值；
    // 注入户型不重置相机，故不需要 fit）。
    const ppm = 90.0;
    Offset at(Vec2 w) =>
        cRect.topLeft + Offset(w.dx * ppm + 80, w.dy * ppm + 80);

    // ① 房间操作条（空地点 → 选中房间）
    await tester.tapAt(at(const Vec2(2.5, 2.0)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.textContaining('Room '), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '英文房间操作条不应溢出');

    // ② 墙体操作条（点左墙）—— 三个英文按钮 + 11px 提示同排
    await tester.tapAt(at(const Vec2(0.0, 2.0)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Del wall'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '英文墙体操作条不应溢出');

    // ③ 物品操作条 → 物品编辑框（改尺寸/旋转）
    await tester.tapAt(at(const Vec2(1.0, 0.8))); // 示例户型里的电视柜
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Placed: '), findsOneWidget);
    // 英文操作条可横向滚动：先确保按钮在可视范围内再点
    await tester.ensureVisible(find.text('Size'));
    await tester.pump();
    await tester.tap(find.text('Size'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Resize / Rotate'), findsOneWidget);
    // _mmField 的 label 一律带单位后缀（与 zh 的「宽 (mm)」同款）
    expect(find.text('Width (mm)'), findsOneWidget);
    expect(find.text('Depth (mm)'), findsOneWidget);
    expect(find.text('Height (mm)'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '英文物品编辑框不应溢出');
  });

  testWidgets('语言落盘：切换后写入 shared_preferences，重启 load 能恢复', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(languageProvider.notifier).set('en');
    // 落盘是 fire-and-forget（不能卡住 UI）：等它写完再看
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < 20 && prefs.getString('jiajia.lang') != 'en'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(prefs.getString('jiajia.lang'), 'en', reason: '切换语言应持久化');

    // 模拟重启：内存归零 → load() 读回
    AppI18n.lang = AppI18n.zh;
    await AppI18n.load();
    expect(AppI18n.lang, 'en', reason: '重启后应记住上次语言');
  });
}
