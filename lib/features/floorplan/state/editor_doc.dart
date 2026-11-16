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
  EditorDoc build() => EditorDoc.fresh(samplePlan());

  FloorPlan get plan => state.plan;
  bool get canUndo => state.undo.isNotEmpty;
  bool get canRedo => state.redo.isNotEmpty;

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
class PlanStore {
  Future<Directory> _dir() async {
    final app = await getApplicationDocumentsDirectory();
    final dir = Directory('${app.path}/plans');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> save(FloorPlan plan) async {
    final f = File('${(await _dir()).path}/${plan.name}.json');
    await f.writeAsString(plan.toJsonString());
    return f.path;
  }

  Future<FloorPlan?> load(String name) async {
    final f = File('${(await _dir()).path}/$name.json');
    if (!await f.exists()) return null;
    return FloorPlan.fromJsonString(await f.readAsString());
  }
}
