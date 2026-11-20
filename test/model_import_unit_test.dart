// v0.1.45：OBJ 导入「原文件单位换算 + 框内校验」。
//
// 真机背景：japaneseMaple.obj 坐标是厘米（7.9m 的树，bbox 790330/697160/699960
// 按米读），app 按米渲染 → 尺寸栏 790330mm 顶穿 50000 上限 → 点「入库」被
// `_mm()` 拦下，提示走底部 4 秒 snack 没人看见，用户空白关框 3 次。
//
// 本文件钉住四件事：
//   1) 预检：三边超 50000 时在 dm/cm/mm 里挑**最大**的能落回 [100, 50000] 的单位
//      （790330 → 0.1 档 79033 仍超 → cm；无解 → 默认米 + 框内错误 + 按钮置灰）；
//   2) 联动：切单位时三栏按原始 bbox 重填（790330 → cm → 7903/6971/6999）；
//   3) 换算：入库文本的 v 坐标 ×s（6 位小数去尾零），尺寸/剪影都用换算后的值；
//   4) 框内校验取代 snack：非法时红字常驻 + 「入库」置灰，永远看得见原因。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/diag/boot_log.dart';
import 'package:jiajia/features/floorplan/domain/import_unit.dart';
import 'package:jiajia/features/floorplan/domain/obj_parse.dart';
import 'package:jiajia/features/floorplan/presentation/floorplan_editor.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';
import 'package:jiajia/features/floorplan/state/model_transfer.dart';

/// 轴对齐盒子（12 三角面）：v1 = (w,0,0)、v2 = (w,0,d)、v6 = (w,h,d)，
/// 坐标按文件原始单位写（[scale] 只是让数值可读，不参与计算）。
String _boxObj(double w, double d, double h) {
  final v = [
    [0.0, 0.0, 0.0], [w, 0.0, 0.0], [w, 0.0, d], [0.0, 0.0, d],
    [0.0, h, 0.0], [w, h, 0.0], [w, h, d], [0.0, h, d],
  ];
  final faces = [
    [1, 4, 3, 2], [5, 6, 7, 8],
    [1, 2, 6, 5], [2, 3, 7, 6], [3, 4, 8, 7], [4, 1, 5, 8],
  ];
  final b = StringBuffer('# test box\n');
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
  // ---------------- 纯函数：预检规则 / 换算写出格式 ----------------

  group('ImportUnits.autoPick', () {
    test('厘米单位的 7.9m 树 → 选 cm（0.1 档 79033 仍超 50000）', () {
      final u = ImportUnits.autoPick(790330, 697160, 699960);
      expect(u, ImportUnits.centimeters);
      expect(ImportUnits.toMm(790330, u!.scale), 7903);
      expect(ImportUnits.toMm(697160, u.scale), 6971); // floor：6971.6 → 6971
      expect(ImportUnits.toMm(699960, u.scale), 6999);
    });

    test('三边都在 50000 内 → null（用米，不缩放）', () {
      expect(ImportUnits.autoPick(1200, 700, 750), isNull);
      expect(ImportUnits.autoPick(50000, 50000, 50000), isNull);
    });

    test('0.1 就够 → 选 dm（最大 s 优先，最保守）', () {
      final u = ImportUnits.autoPick(400000, 300000, 200000);
      expect(u, ImportUnits.decimeters);
      expect(ImportUnits.toMm(400000, u!.scale), 40000);
    });

    test('缩过头（任一边 <100mm）该档不选 → 无解回 null', () {
      // dm: 150000/150000/900 超；cm: 15000/15000/90 小于下限；mm 更小。
      expect(ImportUnits.autoPick(1500000, 1500000, 9000), isNull);
    });

    test('七亿毫米（超一切）→ null（对话框默认米 + 框内报错）', () {
      expect(ImportUnits.autoPick(790330000, 790330000, 790330000), isNull);
    });
  });

  group('ObjUnit.scaleVertexText', () {
    test('只缩 v 前三分量，其余行逐字节保留', () {
      const src = '# hi\nv 790330 0 0\nvt 0 0\nv 0 699960 0\n'
          'usemtl m\nf 1 2 3\n';
      final out = ObjUnit.scaleVertexText(src, 0.01);
      expect(out, '# hi\nv 7903.3 0 0\nvt 0 0\nv 0 6999.6 0\n'
          'usemtl m\nf 1 2 3\n');
    });

    test('6 位小数去尾零（与减面器写出同格式）', () {
      final out = ObjUnit.scaleVertexText(
        'v 790330 123456 1000\nf 1 1 1\n',
        0.001,
      );
      expect(out.split('\n').first, 'v 790.33 123.456 1');
    });

    test('第四分量（齐次 w）不是坐标 → 原样带着', () {
      final out = ObjUnit.scaleVertexText('v 100 0 0 1.0\n', 0.01);
      expect(out, 'v 1 0 0 1.0\n');
    });

    test('scale == 1.0 → 同一实例透传', () {
      const src = 'v 790330 0 0\nf 1 1 1\n';
      expect(identical(ObjUnit.scaleVertexText(src, 1.0), src), isTrue);
    });
  });

  // ---------------- 流程级（widget）：对话框预检 / 联动 / 入库换算 ----------------

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

  /// 走一遍「家具 → 导入 → 选文件 → 命名框」。
  Future<void> importFile(WidgetTester tester, String name, String body) async {
    await openFurnitureSheet(tester);
    picker.completer = Completer<PlatformFile?>();
    await tester.tap(find.byKey(const ValueKey('import_obj_tile')));
    await tester.pump();
    picker.completer!.complete(
      _FakePlatformFile(name, Uint8List.fromList(utf8.encode(body))),
    );
    await tester.pumpAndSettle();
  }

  String mmField(WidgetTester tester, String label) {
    final f = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      ),
    );
    return f.controller!.text;
  }

  bool chipSelected(WidgetTester tester, String label) =>
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
          .selected;

  bool submitEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '入库'))
          .onPressed !=
      null;

  testWidgets('厘米文件：预检 cm → 尺寸 7903/6971/6999 → 入库换算 ×0.01', (tester) async {
    final store = await pumpEditor(tester);
    // japaneseMaple 的缩比仿真：三边 790330/697160/699960（按米读 = 790m 的树）
    await importFile(
      tester,
      'japaneseMaple.obj',
      // 坐标按米约定读是 790.33/697.16/699.96 m；×1000 = wMm 790330/697160/699960
      _boxObj(790.33, 697.16, 699.96),
    );

    // 命名框弹出，单位行只出现在 OBJ 路径
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('原文件单位'), findsOneWidget);
    for (final l in ['m', 'cm', 'dm', 'mm']) {
      expect(find.widgetWithText(ChoiceChip, l), findsOneWidget);
    }
    // 预检落在 cm（0.1 档 79033 仍超 50000 → 不选它）
    expect(chipSelected(tester, 'cm'), isTrue);
    expect(chipSelected(tester, 'm'), isFalse);
    // 尺寸栏 = raw × 0.01（floor）
    expect(mmField(tester, 'W mm'), '7903');
    expect(mmField(tester, 'D mm'), '6971');
    expect(mmField(tester, 'H mm'), '6999');
    // 全部合法 → 「入库」可用，且没有红字行
    expect(submitEnabled(tester), isTrue);
    expect(find.byKey(const ValueKey('import_unit_error')), findsNothing);

    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(store.models, hasLength(1));
    final m = store.models.single;
    // 尺寸 = 换算后的 mm（米 7.903 / 6.971 / 6.999）
    expect(m.wM, closeTo(7.903, 0.001));
    expect(m.dM, closeTo(6.971, 0.001));
    expect(m.hM, closeTo(6.999, 0.001));
    // 入库 objText 的 v 坐标已 ×0.01（抽 v 行断言）
    final vLines = m.objText.split('\n').where((l) => l.startsWith('v ')).toList();
    expect(vLines.first, 'v 0 0 0');
    expect(m.objText, contains('v 7.9033 0 0'));
    expect(m.objText, contains('v 7.9033 6.9996 6.9716'));
    expect(m.objText, isNot(contains('790330')));
    // 剪影用换算后的文本算（不为 null），闸通过
    expect(m.sil, isNotNull);
    expect(() => ObjParser.gate(m.objText), returnsNormally);
    // bootLog 一行：scaled <file> by <s> (unit=cm)
    expect(
      bootLog.panelText(),
      contains('model-import(furniture): scaled japaneseMaple.obj by 0.01 '
          '(unit=cm)'),
    );
  });

  testWidgets('手选 mm（s=0.001）→ 790mm 过闸，入库坐标 ×0.001', (tester) async {
    final store = await pumpEditor(tester);
    await importFile(
      tester,
      'tree.obj',
      _boxObj(790.33, 697.16, 699.96),
    );
    expect(chipSelected(tester, 'cm'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'mm'));
    await tester.pump();

    // 三栏按原始 bbox 重填（用户可再手改）
    expect(chipSelected(tester, 'mm'), isTrue);
    expect(mmField(tester, 'W mm'), '790');
    expect(mmField(tester, 'D mm'), '697');
    expect(mmField(tester, 'H mm'), '699');
    expect(submitEnabled(tester), isTrue);

    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final m = store.models.single;
    expect(m.wM, closeTo(0.79, 0.001));
    expect(m.dM, closeTo(0.697, 0.001));
    expect(m.hM, closeTo(0.699, 0.001));
    expect(m.objText, contains('v 0.79033 0 0'));
    expect(m.sil, isNotNull);
    expect(
      bootLog.panelText(),
      contains('model-import(furniture): scaled tree.obj by 0.001 (unit=mm)'),
    );
  });

  testWidgets('无解（七亿毫米）：默认米 + 「入库」置灰 + 框内红字', (tester) async {
    final store = await pumpEditor(tester);
    await importFile(
      tester,
      'huge.obj',
      // 坐标 790330 m（按米读）→ wMm 790330000：dm/cm/mm 三档全部超 50000
      _boxObj(790330, 790330, 790330),
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    // 无单位能救 → 默认米，尺寸栏就是原始（超限）值
    expect(chipSelected(tester, 'm'), isTrue);
    expect(mmField(tester, 'W mm'), '790330000');
    // 按钮置灰：点不动，也不会悄悄吞进非法尺寸
    expect(submitEnabled(tester), isFalse);
    await tester.tap(find.text('入库'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget); // 没关框
    expect(store.models, isEmpty);
    // 红字行常驻（不是 4 秒就消失的 snack）：三边各一行
    expect(find.byKey(const ValueKey('import_unit_error')), findsOneWidget);
    expect(find.text('W 需在 1~50000mm，或改单位'), findsOneWidget);
    expect(find.text('D 需在 1~50000mm，或改单位'), findsOneWidget);
    expect(find.text('H 需在 1~50000mm，或改单位'), findsOneWidget);

    // 改成合法值 → 红字消失、按钮恢复
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'W mm',
      ),
      '7903',
    );
    await tester.pump();
    expect(find.text('W 需在 1~50000mm，或改单位'), findsNothing);
    expect(submitEnabled(tester), isFalse); // D/H 仍非法
    expect(find.text('D 需在 1~50000mm，或改单位'), findsOneWidget);
  });

  testWidgets('名称清空 → 「入库」置灰 + 名称红字（同样不走 snack）', (tester) async {
    await pumpEditor(tester);
    await importFile(tester, 'box.obj', _boxObj(1.2, 0.7, 0.75));
    expect(submitEnabled(tester), isTrue);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '名称',
      ),
      '  ',
    );
    await tester.pump();
    expect(submitEnabled(tester), isFalse);
    expect(find.text('名称不能为空'), findsOneWidget);
  });

  testWidgets('超闸 + 厘米单位：先减面再换算（顺序固定为 减面→换算→闸→剪影）',
      (tester) async {
    final store = await pumpEditor(tester);
    await importFile(tester, '庭院大树.obj', _bigWavyObj());

    // 200m 的网格（按米读）→ dm 档 20000mm 过闸；文本框 400KB 超闸 → 先减面
    expect(chipSelected(tester, 'dm'), isTrue);
    expect(mmField(tester, 'W mm'), '20000');
    expect(
      (tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('import_decimate_note')),
          matching: find.byType(Text),
        ),
      )).data,
      contains('已自动压缩'),
    );

    await tester.tap(find.text('入库'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final m = store.models.single;
    expect(m.wM, closeTo(20, 0.05));
    expect(m.dM, closeTo(20, 0.05));
    expect(m.hM, closeTo(4, 0.05));
    // 换算后的文本仍在闸内，且 3D/2D 同一份几何
    expect(m.objText.length, lessThanOrEqualTo(ObjParser.maxChars));
    expect(() => ObjParser.gate(m.objText), returnsNormally);
    expect(m.sil, isNotNull);
    final log = bootLog.panelText();
    expect(log, contains('model-import(furniture): decimated 庭院大树.obj'));
    expect(log, contains('scaled 庭院大树.obj by 0.1 (unit=dm)'));
  });

  testWidgets('单件 JSON 导入：不显示单位行、unitScale=1.0 文本原样', (tester) async {
    final store = await pumpEditor(tester);
    final obj = _boxObj(1.2, 0.7, 0.75);
    final json = ModelTransferItem(
      id: 'single_json_box',
      name: '桌面盒子',
      cat: 'furniture',
      wmm: 1200,
      dmm: 700,
      hmm: 750,
      color: 0x8FD3A8,
      objText: obj,
    ).encodeSingle();
    await importFile(tester, '桌面盒子.json', json);

    // JSON 路径直通入库：不弹命名框、没有单位行
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('原文件单位'), findsNothing);
    expect(store.models, hasLength(1));
    final m = store.models.single;
    expect(m.name, '桌面盒子');
    expect(m.objText, obj); // 一个字节都没改
    expect(m.wM, closeTo(1.2, 0.0005));
    expect(m.dM, closeTo(0.7, 0.0005));
    expect(m.hM, closeTo(0.75, 0.0005));
    // bootLog 是进程级累积日志（前面用例也写过 scaled 行）→ 只看这个文件
    expect(bootLog.panelText(), isNot(contains('scaled 桌面盒子.json')));
  });
}

/// 起伏网格 + 40 万字符注释（约 400KB / 3200 面）：面数没超但文本超闸
/// → 走「减面 → 单位换算」双流程（200×200×40 m，按米读超 50000mm）。
String _bigWavyObj() {
  const nx = 40, ny = 40;
  const w = 200.0, d = 200.0, h = 40.0;
  final b = StringBuffer('# ${'x' * 400000}\n');
  final cols = nx + 1;
  for (var j = 0; j <= ny; j++) {
    for (var i = 0; i <= nx; i++) {
      final x = w * i / nx;
      final z = d * j / ny;
      final y =
          h * (0.5 + 0.5 * math.sin(6.28318 * i / nx) * math.cos(6.28318 * j / ny));
      b.writeln('v ${x.toStringAsFixed(5)} ${y.toStringAsFixed(5)} '
          '${z.toStringAsFixed(5)}');
    }
  }
  int vid(int i, int j) => j * cols + i + 1;
  for (var j = 0; j < ny; j++) {
    for (var i = 0; i < nx; i++) {
      final a = vid(i, j), bb = vid(i + 1, j);
      final c = vid(i + 1, j + 1), dd = vid(i, j + 1);
      b.writeln('f $a $bb $c');
      b.writeln('f $a $c $dd');
    }
  }
  return b.toString();
}

/// file_picker 平台替身：pickFile 挂在 Completer 上，测试自己决定返回值。
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

final class _FakePlatformFile extends PlatformFile {
  @override
  final String name;

  final Uint8List bytes;

  _FakePlatformFile(this.name, this.bytes);

  @override
  Uri get uri => Uri.parse('file:///tmp/$name');

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

class _MemStore extends LibModelsStore {
  List<LibModel> models = [];

  @override
  Future<List<LibModel>> load() async => List.of(models);

  @override
  Future<void> save(List<LibModel> m) async {
    models = List.of(m);
  }
}
