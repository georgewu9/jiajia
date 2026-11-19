import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/floor_plan.dart';

/// 编辑器文档：当前户型 + 撤销/重做栈（存 JSON 快照，模型小，够用）。
class EditorDoc {
  FloorPlan plan;
  final List<String> undo;
  final List<String> redo;
  final int revision;

  EditorDoc(this.plan, this.undo, this.redo, this.revision);

  factory EditorDoc.fresh(FloorPlan plan) =>
      EditorDoc(plan, <String>[], <String>[], 0);

  String get currentJson => plan.toJsonString();

  EditorDoc _advance(FloorPlan next, {required bool record}) {
    final newUndo = record ? [...undo, currentJson] : undo;
    if (newUndo.length > 60) newUndo.removeAt(0);
    return EditorDoc(next, newUndo, <String>[], revision + 1);
  }

  EditorDoc _restore(String snapshot) {
    final plan = FloorPlan.fromJsonString(snapshot);
    final newUndo = undo.sublist(0, undo.length - 1);
    final newRedo = [...redo, currentJson];
    return EditorDoc(plan, newUndo, newRedo, revision + 1);
  }
}

class EditorDocNotifier extends Notifier<EditorDoc> {
  @override
  EditorDoc build() =>
      EditorDoc.fresh(FloorPlan()..name = '新建户型'); // 空白画布起步（示例走工具条）

  FloorPlan get plan => state.plan;
  bool get canUndo => state.undo.isNotEmpty;
  bool get canRedo => state.redo.isNotEmpty;

  /// 载入一份户型（打开已存方案 / 示例）：清掉旧撤销栈，从头开始。
  void replace(FloorPlan p) => state = EditorDoc.fresh(p);

  /// 对 [mutate] 直接改 plan（小模型，改完整体快照进 undo）。
  void mutate(void Function(FloorPlan p) mutate, {bool record = true}) {
    final p = state.plan;
    mutate(p);
    state = record ? state._advance(p, record: true) : state._advance(p, record: false);
    // 注意：_advance 基于旧 undo 栈；record=false 时不压栈
  }

  void undo() {
    if (!canUndo) return;
    state = state._restore(state.undo.last);
  }

  void redo() {
    if (!canRedo) return;
    state = state._restore(state.redo.last);
  }
}

final editorDocProvider =
    NotifierProvider<EditorDocNotifier, EditorDoc>(EditorDocNotifier.new);

/// 户型 JSON 存/读（app 目录下 plans/）。M4 换 drift 时只改这里。
///
/// 约定：一个户型 = plans/<名称>.json；名称做了清洗（去非法字符/限长），
/// 重名自动加 (1)(2)…，不会互相覆盖。
class PlanStore {
  /// 可选的根目录：默认 app 文档目录（path_provider）；单测传临时目录，
  /// 避免依赖平台通道。生产代码一律 `PlanStore()`。
  final Directory? root;

  PlanStore({this.root});

  /// 文件名清洗：去掉路径/分隔/危险字符，限长 40，空给默认。
  static String sanitizeName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) return '户型';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  Future<Directory> _base() async =>
      root ?? await getApplicationDocumentsDirectory();

  Future<Directory> _dir() async {
    final app = await _base();
    final dir = Directory('${app.path}/plans');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 导入来源/标签等辅助信息（`plans_meta.json`，与 plans/ 同级）。
  /// 结构：`{"<户型名>": {"sourcePath": "...", "label": "..."}}`。
  /// 文件缺失/损坏 → 空表（不能因为辅助信息挂了打不开户型列表）。
  File? _metaFileCache;

  Future<File> _metaFile() async =>
      _metaFileCache ??= File('${(await _base()).path}/plans_meta.json');

  Future<Map<String, Map<String, String>>> loadMeta() async {
    try {
      final f = await _metaFile();
      if (!await f.exists()) return <String, Map<String, String>>{};
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return <String, Map<String, String>>{};
      final out = <String, Map<String, String>>{};
      raw.forEach((k, v) {
        if (k is! String || v is! Map) return;
        final m = <String, String>{};
        v.forEach((kk, vv) {
          if (kk is String && vv is String) m[kk] = vv;
        });
        out[k] = m;
      });
      return out;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  Future<void> saveMeta(Map<String, Map<String, String>> meta) async {
    final f = await _metaFile();
    await f.writeAsString(jsonEncode(meta));
  }

  /// 保存：同名且内容就是它自己 → 覆盖更新；同名但属于别的户型 → 加后缀。
  Future<String> save(FloorPlan plan) async {
    final dir = await _dir();
    var name = sanitizeName(plan.name);
    var target = File('${dir.path}/$name.json');
    if (target.existsSync()) {
      final storedName = _storedName(target);
      if (storedName != null && storedName != plan.name) {
        var n = 1;
        while (true) {
          final cand = File('${dir.path}/$name($n).json');
          // 空位（不存在）或"我上次存的重名文件"（owner==本户型）→ 用它；
          // 别人的重名文件绝不覆盖，继续找下一个后缀
          if (!cand.existsSync() || _storedName(cand) == plan.name) {
            target = cand;
            break;
          }
          n++;
        }
      }
    }
    await target.writeAsString(plan.toJsonString());
    return target.path;
  }

  /// 读出已存 JSON 的 name 字段（读不出来 → null，当作"无主"文件）。
  String? _storedName(File f) {
    try {
      final m = RegExp('"name"\\s*:\\s*"([^"]*)"').firstMatch(f.readAsStringSync());
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// 已存户型列表（按保存时间新→旧）。环境不支持（如单测）→ 空表。
  Future<List<PlanEntry>> list() async {
    final out = <PlanEntry>[];
    try {
      final dir = await _dir();
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final j = FloorPlan.fromJsonString(f.readAsStringSync());
        final st = f.statSync();
        out.add(PlanEntry(
          name: j.name,
          path: f.path,
          sizeBytes: st.size,
          mtime: st.modified,
        ));
      }
      out.sort((a, b) => b.mtime.compareTo(a.mtime));
    } catch (_) {
      // path_provider 不可用（桌面单测）→ 视为没有已存户型
    }
    return out;
  }

  Future<void> delete(PlanEntry e) async {
    try {
      await File(e.path).delete();
    } catch (_) {}
    // 顺手清掉 meta：否则以后新建同名户型会被当成「导入来的」回写到旧路径
    try {
      final meta = await loadMeta();
      if (meta.remove(e.name) != null) await saveMeta(meta);
    } catch (_) {}
  }

  /// 改户型名（v0.1.33）：清洗 → 写 plans/<新名>.json（JSON 内 name 同步）→
  /// 删旧文件 → 迁移 plans_meta 里旧名键到新名键。
  ///
  /// 目标名已被**别的**户型占用 → 抛 [PlanRenameException]（调用方提示
  /// 「已有同名户型」），绝不覆盖别人的文件。同名改（只清洗/大小写变化）允许。
  Future<void> rename(PlanEntry e, String newName) async {
    final raw = newName.trim();
    if (raw.isEmpty) throw PlanRenameException('户型名不能为空');
    final clean = sanitizeName(raw);
    final dir = await _dir();
    final src = File(e.path);
    final target = File('${dir.path}/$clean.json');
    final sameFile = target.path == src.path;
    if (!sameFile && await target.exists()) {
      throw PlanRenameException('已有同名户型');
    }
    final plan = FloorPlan.fromJsonString(await src.readAsString());
    plan.name = clean;
    await target.writeAsString(plan.toJsonString());
    if (!sameFile) {
      try {
        await src.delete();
      } catch (_) {}
    }
    // 辅助信息跟着改名（源路径/label 保留）
    try {
      final meta = await loadMeta();
      if (meta.containsKey(e.name)) {
        final moved = meta.remove(e.name)!;
        meta[clean] = moved;
        await saveMeta(meta);
      }
    } catch (_) {}
  }

  Future<FloorPlan?> load(String name) async {
    final f = File('${(await _dir()).path}/$name.json');
    if (!await f.exists()) return null;
    return FloorPlan.fromJsonString(await f.readAsString());
  }

  Future<FloorPlan?> loadPath(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return FloorPlan.fromJsonString(await f.readAsString());
  }
}

/// 改名失败（重名/空名）：message 直接给 UI 当 SnackBar 文案。
class PlanRenameException implements Exception {
  final String message;
  const PlanRenameException(this.message);
  @override
  String toString() => message;
}

/// 一条已存户型（列表用）。
class PlanEntry {
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime mtime;
  PlanEntry({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.mtime,
  });
}
