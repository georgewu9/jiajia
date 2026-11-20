// v0.1.42：修复「叶子菜单导入 .obj 选完文件后无任何反应」。
//
// 场景：系统文件选择器打开期间，sheet 被关掉（返回手势 / MIUI 后台回收后 UI 重建），
// sheet 的 State 已 dispose。旧实现把 sheet context 传进导入流程，选完文件后
// `context.mounted == false` → 静默 return null，用户看不到任何反馈。
//
// 现在导入流程锚在 root Navigator（开选择器之前捕获）：
//   · 页面还在 → 命名对话框弹在 root nav 上，正常入库；
//   · 整棵树都没了（root nav 也不 mounted）→ 跳过命名框，按默认值直接入库 + bootLog。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/diag/boot_log.dart';
import 'package:jiajia/features/floorplan/domain/model_leaves.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';

/// 1.2 × 0.7 × 0.75 米的盒子（真三维，能算出非空 2D 轮廓）。
String _boxObj() {
  const w = 1.2, d = 0.7, h = 0.75;
  final v = [
    [0.0, 0.0, 0.0], [w, 0.0, 0.0], [w, 0.0, d], [0.0, 0.0, d],
    [0.0, h, 0.0], [w, h, 0.0], [w, h, d], [0.0, h, d],
  ];
  final faces = [
    [1, 4, 3, 2], [5, 6, 7, 8],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 4, 8, 7], [4, 1, 5, 8],
  ];
  final b = StringBuffer();
  for (final p in v) {
    b.writeln('v ${p[0]} ${p[1]} ${p[2]}');
  }
  for (final f in faces) {
    b.writeln('f ${f[0]} ${f[1]} ${f[2]}');
    b.writeln('f ${f[0]} ${f[2]} ${f[3]}');
  }
  return b.toString();
}

void main() {
  late _FakeFilePicker picker;
  late FilePickerPlatform previous;

  setUp(() {
    previous = FilePickerPlatform.instance;
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() {
    FilePickerPlatform.instance = previous;
  });

  Future<_MemStore> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
    });
    final store = _MemStore();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FloorplanEditorPage(libStore: store)),
      ),
    );
    await tester.pump();
    return store;
  }

  Future<void> openFurnitureSheet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ActionChip, '模块'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.ancestor(of: find.text('家具'), matching: find.byType(InkWell)).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('选文件期间家具 sheet 被关掉 → 命名框弹在 root nav 上并正常入库',
      (tester) async {
    final store = await pumpEditor(tester);
    await openFurnitureSheet(tester);

    picker.completer = Completer<PlatformFile?>();
    await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
    await tester.pump(); // _importInto 进入 pickModelFile，挂起等系统选择器

    // 模拟系统文件选择器期间 sheet 被回收/关掉：sheet State 被 dispose。
    Navigator.of(tester.element(find.text('导入模型…'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('导入模型…'), findsNothing); // sheet 确实没了

    // 选择器这时才返回一个合法 .obj。
    picker.completer!.complete(
      _FakePlatformFile('我的桌子.obj', Uint8List.fromList(utf8.encode(_boxObj()))),
    );
    await tester.pumpAndSettle();

    // 页面还在 → 命名对话框应该出现在 root nav 上（旧实现这里什么都没有）。
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('导入模型'), findsOneWidget);
    expect(find.text('入库'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.models, hasLength(1));
    // 结果提示走 root messenger：sheet 已死，提示仍必须可见（v0.1.43）。
    expect(find.text('已导入「我的桌子」'), findsOneWidget);
    final m = store.models.single;
    expect(m.name, '我的桌子'); // 默认名 = 文件基名
    expect(m.cat, ModelLeaves.furniture);
    expect(m.subCat, '卧室'); // 菜单传入的二级分类
    expect(m.sil, isNotNull); // 导入即算 2D 轮廓并入库
    expect(m.objText, contains('v 1.2 0.0 0.0'));
    // 尺寸来自 OBJ bbox（1.2 × 0.7 × 0.75 m）
    expect(m.wM, closeTo(1.2, 0.001));
    expect(m.dM, closeTo(0.7, 0.001));
    expect(m.hM, closeTo(0.75, 0.001));
  });

  testWidgets('整棵 UI 在选择器期间销毁（root nav 也不 mounted）→ 自动按默认值入库',
      (tester) async {
    final store = await pumpEditor(tester);
    await openFurnitureSheet(tester);

    picker.completer = Completer<PlatformFile?>();
    await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
    await tester.pump();

    // 极端：编辑器连同 MaterialApp 整棵树被销毁 → root NavigatorState 不再 mounted。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    picker.completer!.complete(
      _FakePlatformFile('auto_box.obj', Uint8List.fromList(utf8.encode(_boxObj()))),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 没有命名框可弹：模型仍按默认值入库，不再「选完文件什么都没发生」。
    expect(store.models, hasLength(1));
    final m = store.models.single;
    expect(m.name, 'auto_box');
    expect(m.cat, ModelLeaves.furniture);
    expect(m.subCat, '卧室');
    expect(m.sil, isNotNull);
    // bootLog 留痕：nav 丢失 → 自动入库，两条都在（v0.1.43 统一前缀）。
    final log = bootLog.panelText();
    expect(log, contains('model-import(furniture): nav gone auto'));
    expect(log, contains('model-import(furniture): auto added (nav gone)'));
  });

  testWidgets('picker 返回 null（取消 / 通道丢结果）→ root 级「未选择文件」可见',
      (tester) async {
    await pumpEditor(tester);
    await openFurnitureSheet(tester);

    picker.completer = Completer<PlatformFile?>();
    await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
    await tester.pump();

    // 选择器期间 sheet 被关掉：旧实现 out/context 全丢，屏上什么都看不到。
    Navigator.of(tester.element(find.text('导入模型…'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('导入模型…'), findsNothing);

    picker.completer!.complete(null);
    await tester.pumpAndSettle();

    // 「用户取消」和「平台通道根本没回文件」在屏上必须可区分于「死寂」。
    expect(find.text('未选择文件（已取消）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(bootLog.panelText(),
        contains('model-import(furniture): picker null (user cancel / lost)'));
  });

  testWidgets('解析失败（OBJ 无面）且 sheet 已销毁 → 结果提示仍上屏 + 日志',
      (tester) async {
    await pumpEditor(tester);
    await openFurnitureSheet(tester);

    picker.completer = Completer<PlatformFile?>();
    await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
    await tester.pump();
    Navigator.of(tester.element(find.text('导入模型…'))).pop();
    await tester.pumpAndSettle();

    picker.completer!.complete(
      _FakePlatformFile('bad.obj', Uint8List.fromList(utf8.encode('v 0 0 0\n'))),
    );
    await tester.pumpAndSettle();

    // 旧实现 out != null 但 !mounted → 整条 rejected 结果被丢掉；现在照发。
    expect(find.textContaining('OBJ 没有面数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(bootLog.panelText(),
        contains('model-import(furniture): obj parse failed'));
  });
}

/// file_picker 平台接口替身：pickFile 挂在一个 Completer 上，
/// 让测试可以在「选择器还没返回」的窗口里把 sheet 关掉。
class _FakeFilePicker extends FilePickerPlatform {
  Completer<PlatformFile?>? completer;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    return completer?.future ?? Future<PlatformFile?>.value();
  }
}

/// 内存版 PlatformFile：读字节走内存，不碰磁盘。
final class _FakePlatformFile extends PlatformFile {
  @override
  final String name;

  final Uint8List bytes;

  _FakePlatformFile(this.name, this.bytes);

  @override
  Uri get uri => Uri.parse('file:///tmp/$name');

  // 本流程只读 bytes，xFile 不会被调用；Never 是合法 override 且免引 cross_file。
  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(bytes);
}

/// 内存版模型库：widget 测试里不做真实文件 IO。
class _MemStore extends LibModelsStore {
  List<LibModel> models = [];

  @override
  Future<List<LibModel>> load() async => List.of(models);

  @override
  Future<void> save(List<LibModel> m) async {
    models = List.of(m);
  }
}
