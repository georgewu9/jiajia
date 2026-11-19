import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/floor_plan.dart';
import 'package:jiajia/features/floorplan/state/editor_doc.dart';
import 'package:jiajia/features/floorplan/state/plan_io.dart';

/// v0.1.33 T1：导入文件名解析 + plans_meta sidecar + 保存回写原路径。
void main() {
  group('pickedFileName：三种导入来源', () {
    test('file:// URI → 末段文件名', () {
      expect(
        PlanIo.pickedFileName(File('file:///storage/emulated/0/Download/客厅.json')),
        '客厅.json',
      );
      // 桌面上 file_picker 给的普通绝对路径（无 scheme）同样解得出
      expect(PlanIo.pickedFileName(File('/home/u/Download/主卧.json')),
          '主卧.json');
    });

    test('content:// SAF（primary: 前缀）→ 冒号后 basename', () {
      const uri = 'content://com.android.externalstorage.documents/document/'
          'primary%3ADownload%2F客厅.json';
      expect(PlanIo.pickedFileName(File(uri)), '客厅.json');

      // MIUI documentsui 风格：末段里带 %2F 的绝对路径
      const miui = 'content://com.miui.fileprovider/document/'
          'primary:%2Fstorage%2Femulated%2F0%2FDownload%2Fa.json';
      expect(PlanIo.pickedFileName(File(miui)), 'a.json');
    });

    test('乱串 / 无末段 → null（调用方回退 JSON 里的 name）', () {
      expect(PlanIo.pickedFileName(File('')), isNull);
      expect(PlanIo.pickedFileName(File('content://com.foo/')), isNull);
      expect(PlanIo.pickedFileName(File('ftp://host/dir')), isNull);
    });
  });

  group('PlanStore.plans_meta.json', () {
    late Directory dir;
    late PlanStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jj_meta_');
      store = PlanStore(root: dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('存 → 读 round-trip（键=户型名，值 sourcePath/label）', () async {
      await store.saveMeta({
        '客厅': {'sourcePath': '/tmp/客厅.json', 'label': '客厅.json'},
      });
      final meta = await store.loadMeta();
      expect(meta['客厅']?['sourcePath'], '/tmp/客厅.json');
      expect(meta['客厅']?['label'], '客厅.json');
      // 落在 PlanStore 根下，不在 plans/ 里（list() 不应把它当户型）
      expect(File('${dir.path}/plans_meta.json').existsSync(), isTrue);
      final plans = await store.list();
      expect(plans.where((e) => e.name.contains('plans_meta')), isEmpty);
    });

    test('文件缺失 → 空表', () async {
      expect(await store.loadMeta(), isEmpty);
    });

    test('文件损坏（非 JSON / 结构不对）→ 空表不崩', () async {
      File('${dir.path}/plans_meta.json').writeAsStringSync('{not json');
      expect(await store.loadMeta(), isEmpty);
      File('${dir.path}/plans_meta.json').writeAsStringSync('[1,2,3]');
      expect(await store.loadMeta(), isEmpty);
    });
  });

  group('writeBack：保存后回写原文件', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jj_wb_');
    });
    tearDown(() => dir.delete(recursive: true));

    test('真实路径 → synced，字节与本次保存一致', () async {
      final src = File('${dir.path}/外部户型.json');
      src.writeAsStringSync('{"name":"旧"}');
      final bytes = Uint8List.fromList(
          utf8.encode((FloorPlan()..name = '改过的').toJsonString()));

      expect(PlanIo.writeBack(bytes, src.path), WriteBack.synced);
      final back = src.readAsBytesSync();
      expect(back, bytes);
      expect(FloorPlan.fromJsonString(utf8.decode(back)).name, '改过的');
    });

    test('file:// URI → 同样回写', () async {
      final src = File('${dir.path}/b.json');
      src.writeAsStringSync('x');
      expect(PlanIo.writeBack(Uint8List.fromList([1, 2, 3]), src.uri.toString()),
          WriteBack.synced);
      expect(src.readAsBytesSync(), [1, 2, 3]);
    });

    test('content:// → skaf（SAF 无持久写权限，要求用户重新导出）', () {
      expect(
        PlanIo.writeBack(
          Uint8List.fromList([1]),
          'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fa.json',
        ),
        WriteBack.skaf,
      );
    });

    test('真实路径但写不进去 → failed', () {
      expect(
        PlanIo.writeBack(
            Uint8List.fromList([1]), '${dir.path}/不存在目录/x.json'),
        WriteBack.failed,
      );
    });
  });
  group('saveAndSync：保存 → 读 meta → 回写（编辑器保存用的整条链）', () {
    late Directory dir;
    late PlanStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('jj_save_sync_');
      store = PlanStore(root: dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('无 meta → 「已保存」，只写私有 plans/', () async {
      final p = FloorPlan()..name = '普通户型';
      expect(await PlanIo.saveAndSync(store, p), '已保存');
      expect(File('${dir.path}/plans/普通户型.json').existsSync(), isTrue);
    });

    test('有真实 sourcePath → 「已保存并同步到原路径」+ 原文件被改写', () async {
      final src = File('${dir.path}/导入源.json');
      src.writeAsStringSync('{"name":"旧内容"}');
      await store.saveMeta({
        '导入的': {'sourcePath': src.path},
      });

      final p = FloorPlan()..name = '导入的';
      p.addRoom(at: const Vec2(0, 0), l: 2, w: 2, withDoor: false);
      expect(await PlanIo.saveAndSync(store, p), '已保存并同步到原路径');

      final back = FloorPlan.fromJsonString(src.readAsStringSync());
      expect(back.name, '导入的');
      expect(back.walls, hasLength(4));
      // 私有目录那份与原文件字节一致
      expect(src.readAsStringSync(),
          File('${dir.path}/plans/导入的.json').readAsStringSync());
    });

    test('content:// sourcePath → skaf 文案，原文件不动', () async {
      await store.saveMeta({
        'SAF 来的': {
          'sourcePath':
              'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fa.json'
        },
      });
      final p = FloorPlan()..name = 'SAF 来的';
      expect(await PlanIo.saveAndSync(store, p),
          '已保存本地；外部原文件需重新导出（SAF 无持久写权限）');
      expect(File('${dir.path}/plans/SAF 来的.json').existsSync(), isTrue);
    });
  });
}
