import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/furniture_tabs.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';

/// v0.1.38：模块页模型搬运入口 / 每个叶子菜单的导入按钮 /
/// 家具 sheet 无「模型库」tab / tile 用户角标。
void main() {
  const objTri = 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n';

  LibModel mk(String id, String name, String cat, {String? subCat}) => LibModel(
    id: id,
    name: name,
    cat: cat,
    subCat: subCat,
    wM: 1.0,
    dM: 0.6,
    hM: 1.0,
    color: 0xD9B28A,
    objText: objTri,
  );

  Future<(ProviderContainer, LibModelsStore)> pumpEditor(
    WidgetTester tester, {
    List<LibModel> seed = const [],
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    final store = _MemStore(seed);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FloorplanEditorPage(libStore: store)),
      ),
    );
    await tester.pump();
    return (container, store);
  }

  Future<void> openModule(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ActionChip, '模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  Future<void> openFurniture(WidgetTester tester) async {
    await openModule(tester);
    await tester.tap(
      find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  testWidgets('模块 sheet 含 全量导出/全量导入/用户素材 3 新入口', (tester) async {
    await pumpEditor(tester);
    await openModule(tester);
    expect(find.byKey(const ValueKey('module_full_export')), findsOneWidget);
    expect(find.byKey(const ValueKey('module_full_import')), findsOneWidget);
    expect(find.byKey(const ValueKey('module_user_assets')), findsOneWidget);
    expect(find.text('全量导出'), findsOneWidget);
    expect(find.text('全量导入'), findsOneWidget);
    expect(find.text('用户素材'), findsOneWidget);
  });

  testWidgets('每个叶子素材菜单都有「导入」按钮', (tester) async {
    await pumpEditor(tester);
    await openModule(tester);
    for (final cat in ['门', '窗', '梁柱', '楼梯', '特殊墙窗', '庭院']) {
      await tester.tap(find.text(cat));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        find.byKey(ValueKey('import_btn_$cat')),
        findsOneWidget,
        reason: '$cat 菜单缺导入按钮',
      );
      expect(find.text('导入'), findsOneWidget);
      // 网格首个 tile 也是导入入口
      expect(
        find.byKey(ValueKey('import_tile_${cat}_')),
        findsOneWidget,
        reason: '$cat 网格缺导入 tile',
      );
      await tester.tap(find.text('← 模块'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }
  });

  testWidgets('家具 sheet：无「模型库」tab、5 个 tab 都有导入 tile、用户 tile 带角标',
      (tester) async {
    await pumpEditor(
      tester,
      seed: [
        mk('u_furn_1', '我的书架', '家具', subCat: '卧室'),
        mk('u_old_1', '旧柜', '卧室'),
      ],
    );
    await openFurniture(tester);

    // 「模型库」不再是家具 sheet 的 tab/标题（旧版遗留分类已移到「用户素材」）
    expect(find.text('模型库'), findsNothing);

    // 默认「卧室」：系统 床/衣柜 + 用户「我的书架」
    expect(find.text('床'), findsOneWidget);
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('旧柜'), findsNothing); // 旧分类不混进家具 tab
    expect(find.text('用户'), findsOneWidget); // 只有用户 tile 有角标

    // 5 个分类 tab 都在，且每个都有导入 tile
    for (final cat in FurnitureTabs.cats) {
      await tester.tap(find.widgetWithText(ChoiceChip, cat));
      await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
      expect(
        find.byKey(const ValueKey('import_obj_tile')),
        findsOneWidget,
        reason: '$cat 缺导入入口',
      );
    }
    // 用户模型只属于 subCat=卧室：切走后角标消失
    await tester.tap(find.widgetWithText(ChoiceChip, '书房'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('我的书架'), findsNothing);
    expect(find.text('用户'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('用户素材菜单：旧条目（cat=卧室）+ cat=用户素材 都在，带用户角标',
      (tester) async {
    await pumpEditor(
      tester,
      seed: [
        mk('u_old_1', '旧柜', '卧室'),
        mk('u_ua_1', '无分类件', '用户素材'),
        mk('u_plain_1', '空分类件', ''),
        mk('u_furn_1', '我的书架', '家具', subCat: '卧室'),
      ],
    );
    await openModule(tester);
    await tester.tap(find.byKey(const ValueKey('module_user_assets')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('用户素材（3 件）'), findsOneWidget);
    expect(find.text('旧柜'), findsOneWidget);
    expect(find.text('无分类件'), findsOneWidget);
    expect(find.text('空分类件'), findsOneWidget);
    expect(find.text('我的书架'), findsNothing); // 有叶子分类 → 不进用户素材
    expect(find.byKey(const ValueKey('import_btn_用户素材')), findsOneWidget);
    expect(find.text('用户'), findsNWidgets(3));
  });

  testWidgets('用户素材 tile 点按 → kind=lib 放置路径不崩', (tester) async {
    await pumpEditor(tester, seed: [mk('u_old_1', '旧柜', '卧室')]);
    await openModule(tester);
    await tester.tap(find.byKey(const ValueKey('module_user_assets')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.text('旧柜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('库模型'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

/// 内存版模型库：widget 测试里不做真实文件 IO（fake async 下 createTemp 会挂）。
class _MemStore extends LibModelsStore {
  List<LibModel> models;

  _MemStore(List<LibModel> seed) : models = List.of(seed);

  @override
  Future<List<LibModel>> load() async => List.of(models);

  @override
  Future<void> save(List<LibModel> m) async {
    models = List.of(m);
  }
}

