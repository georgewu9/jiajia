// 轻量双语字符串表（B 方案）：零新依赖、零代码生成。
//
// 设计要点：
//   · 词表 = 一张 const Map<String, (String zh, String en)>，key 为语义化
//     小写 snake（'cta_start' / 'wall_thickness' / 'furn_sofa'）；
//   · 取值入口 [t]：按 [AppI18n.lang] 取当前语言，缺 key 回退 zh（再缺则
//     返回调用方给的 zh 兜底文案，最后才返回 key 本身 —— 数据驱动标签如
//     ModelSpec.label 用这种方式，不必把 90 条目录名硬编码进词表以外的地方）；
//   · 带参文案用 `{0}` `{1}` 占位：t('wall_bar_hint', args: [id, len, ...])；
//   · 当前语言存 [AppI18n.lang]（默认 'zh'），并用 Riverpod 的
//     [languageProvider] 驱动 UI 重建；切换后由 [AppI18n.save] 落盘
//     shared_preferences（pubspec 已有，不新增依赖），重启后 [load] 恢复。
//
// 约定：注释、bootLog/diag 日志正文、JSON 数据键（category / plan.name）
// 保持中文不动；只翻用户看得见的 UI 文案。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条词条：中文 + 英文。
typedef L10nEntry = ({String zh, String en});

class AppI18n {
  const AppI18n._();

  static const String zh = 'zh';
  static const String en = 'en';

  /// 当前语言（'zh' | 'en'）。默认中文：老用户/老测试的默认观感不变。
  static String lang = zh;

  static const String _prefKey = 'jiajia.lang';

  static bool get isEn => lang == en;

  /// 按当前语言取词；[lang] 可显式指定（测试/导出用）。
  /// 缺 key → 用 [zhText] 兜底 → 再缺返回 key 本身。
  static String t(
    String key, {
    String lang = '',
    String? zhText,
    List<Object?> args = const [],
  }) {
    final l = lang.isEmpty ? AppI18n.lang : lang;
    final e = kStrings[key];
    var s = e == null
        ? (zhText ?? key)
        : (l == AppI18n.en ? e.en : e.zh);
    for (var i = 0; i < args.length; i++) {
      s = s.replaceAll('{$i}', '${args[i]}');
    }
    return s;
  }

  /// 从本地偏好恢复语言（main 启动时调用；测试/无插件环境静默失败）。
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      final v = p.getString(_prefKey);
      if (v == zh || v == en) lang = v!;
    } catch (_) {
      // 无 shared_preferences 插件（widget 测试）→ 保持默认 zh
    }
  }

  /// 记住语言（切换时调用；失败不阻塞 UI）。
  static Future<void> save(String l) async {
    lang = (l == en) ? en : zh;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, lang);
    } catch (_) {
      // 同上：持久化不可用时仅本次会话生效
    }
  }
}

/// 全局取词别名（UI 里写 t('key') 最省字）。
String t(
  String key, {
  String lang = '',
  String? zhText,
  List<Object?> args = const [],
}) => AppI18n.t(key, lang: lang, zhText: zhText, args: args);

/// 当前语言 provider：切语言 → state 变 → 监听它的页面整体重建。
final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);

class LanguageNotifier extends Notifier<String> {
  @override
  String build() => AppI18n.lang;

  /// 切语言：先改静态值（domain 层 getter 立刻取到新语言），再通知 UI 重建。
  /// 落盘是 fire-and-forget：偏好插件异常/缺失（widget 测试）不能卡住切语言。
  Future<void> set(String l) async {
    AppI18n.lang = l == AppI18n.en ? AppI18n.en : AppI18n.zh;
    state = AppI18n.lang;
    unawaited(AppI18n.save(state));
  }

  Future<void> toggle() => set(state == AppI18n.en ? AppI18n.zh : AppI18n.en);
}

/// 词表。命名：<域>_<语义>；目录/家具名用 `furn_<kind>`、`model_<id>`、
/// `cat_<leaf>`，与数据层 id 一一对应。
const Map<String, L10nEntry> kStrings = {
  // ---------------- 通用 ----------------
  'cancel': (zh: '取消', en: 'Cancel'),
  'ok': (zh: '确定', en: 'OK'),
  'apply': (zh: '应用', en: 'Apply'),
  'save': (zh: '保存', en: 'Save'),
  'delete': (zh: '删除', en: 'Delete'),
  'import': (zh: '导入', en: 'Import'),
  'export': (zh: '导出', en: 'Export'),
  'close': (zh: '关闭', en: 'Close'),
  'back_to_module': (zh: '← 模块', en: '← Modules'),
  'module': (zh: '模块', en: 'Modules'),
  'wall_word': (zh: '墙', en: 'wall'),
  'canvas_word': (zh: '画布', en: 'canvas'),
  'door_word': (zh: '门', en: 'door'),
  'window_word': (zh: '窗', en: 'window'),

  // ---------------- 封面 / 落地页 ----------------
  'app_tagline': (zh: '画户型 · 摆家具 · 3D 浏览', en: 'Draw plans · Place furniture · 3D view'),
  'cta_start': (zh: '开始画户型', en: 'Start Drawing'),
  'cta_3d': (zh: '3D 浏览', en: '3D View'),
  'my_plans': (zh: '我的户型', en: 'My Plans'),
  'loading_plans': (zh: '读取已存户型…', en: 'Loading plans…'),
  'plans_empty': (
    zh: '还没有保存的户型。画完点编辑器右上角「保存」就会出现在这里。',
    en: 'No saved plans yet. Draw a plan, tap Save in the editor, and it will show up here.',
  ),
  'rename': (zh: '重命名', en: 'Rename'),
  'export_to_file': (zh: '导出到文件', en: 'Export to file'),
  'delete_plan_title': (zh: '删除「{0}」？', en: 'Delete "{0}"?'),
  'delete_plan_body': (
    zh: '户型、门窗洞和家具摆放都会一并删除，不可恢复。',
    en: 'The plan, its openings and furniture will all be deleted. This cannot be undone.',
  ),
  'exported_to': (zh: '已导出到 {0}', en: 'Exported to {0}'),
  'export_failed': (zh: '导出失败', en: 'Export failed'),
  'export_failed_reason': (zh: '导出失败：{0}', en: 'Export failed: {0}'),
  'imported_named': (zh: '已导入 {0}', en: 'Imported {0}'),
  'imported_named_quoted': (zh: '已导入「{0}」', en: 'Imported "{0}"'),
  'import_failed_invalid': (
    zh: '导入失败：文件不是有效户型',
    en: 'Import failed: the file is not a valid plan',
  ),
  // v0.1.51：导入失败带具体原因（阶段 + 异常类型），不再一律「不是有效户型」。
  // 外层文案复用已有的 import_failed_reason（'导入失败：{0}'）。
  'import_fail_json': (zh: 'JSON 解析失败', en: 'JSON parse error'),
  'import_fail_json_at': (
    zh: 'JSON 解析失败（位置 {0}）',
    en: 'JSON parse error (position {0})',
  ),
  'import_fail_encoding': (
    zh: '文件不是 UTF-8 文本',
    en: 'the file is not UTF-8 text',
  ),
  'import_fail_structure': (
    zh: '文件结构不是有效户型（字段缺失或类型不符）',
    en: 'the file is not a plan structure (missing field or wrong type)',
  ),
  'import_fail_io': (zh: '读写文件失败', en: 'file read/write error'),
  'import_fail_unknown': (zh: '原因未知', en: 'unknown reason'),
  // 尾部旧数据被自动截断修复（MIUI SAF 不截断覆盖的现场）
  'imported_named_repaired': (
    zh: '已导入 {0}（文件尾部含旧数据，已自动修复，丢弃 {1} 字符）',
    en: 'Imported {0} (stale tail data trimmed automatically, {1} chars dropped)',
  ),
  'rename_plan_title': (zh: '重命名户型', en: 'Rename Plan'),
  'plan_name_label': (zh: '户型名', en: 'Plan name'),
  'renamed': (zh: '已重命名', en: 'Renamed'),
  'renamed_clean': (
    zh: '已重命名为 {0}（已清洗非法字符）',
    en: 'Renamed to {0} (invalid characters removed)',
  ),
  'rename_failed': (zh: '重命名失败', en: 'Rename failed'),

  // ---------------- 诊断面板（开发者向日志正文不翻，面板 UI 翻） ----------------
  'diag_error_title': (
    zh: '⚠ 运行异常 / 启动记录（截图发我即可定位）',
    en: '⚠ Runtime error / boot log (send me a screenshot)',
  ),
  'diag_start_title': (
    zh: '启动诊断（长按文本可复制；截图发我）',
    en: 'Startup diagnostics (long-press the text to copy; send me a screenshot)',
  ),
  'diag_close_hint': (
    zh: '点空白处或右上角 ✕ 也可关闭',
    en: 'Tap a blank area or the ✕ to close',
  ),

  // ---------------- 3D 浏览 ----------------
  'viewer3d_title': (zh: '3D 浏览', en: '3D View'),
  'resource_load_failed': (zh: '资源加载失败：{0}{1}', en: 'Failed to load resources: {0}{1}'),
  'resource_missing': (zh: '（资源缺失）', en: ' (asset missing)'),
  'loading_3d': (zh: '加载 3D 场景…', en: 'Loading 3D scene…'),
  'ready_syncing': (zh: '就绪 · 同步中', en: 'Ready · syncing'),
  'loaded_summary': (zh: '已加载 {0} 面墙 · {1} 件家具', en: 'Loaded {0} walls · {1} items'),
  'engine_unavailable': (
    zh: '3D 引擎不可用（测试环境）\n墙 {0} · 家具 {1}',
    en: '3D engine unavailable (test environment)\nWalls {0} · Items {1}',
  ),
  'mode_top': (zh: '俯视', en: 'Top'),
  'mode_orbit': (zh: '轨道', en: 'Orbit'),
  'mode_first': (zh: '第一视角', en: 'First-person'),
  'sync_2d': (zh: '同步 2D 编辑', en: 'Sync 2D edits'),

  // ---------------- 编辑器顶栏 ----------------
  'new_plan': (zh: '新建户型', en: 'New Plan'),
  'load_sample': (zh: '载入示例户型', en: 'Load sample plan'),
  'undo': (zh: '撤销', en: 'Undo'),
  'redo': (zh: '重做', en: 'Redo'),
  'rotate_plan': (zh: '旋转户型', en: 'Rotate Plan'),
  'view_3d': (zh: '3D 浏览', en: '3D View'),

  // ---------------- 画布引导 ----------------
  'wall_hint': (
    zh: '点「画墙」后单指拖拽画墙（直线）· 端点自动吸附 · 45°角锁定\n双击墙体：设尺寸 mm / 加门洞',
    en: 'Tap "Wall", then drag with one finger to draw a straight wall · auto-snap to endpoints · 45° lock\nDouble-tap a wall: set size in mm / add an opening',
  ),
  'room_quick_entry': (zh: '输入尺寸 一键建房间 →', en: 'Enter size · one-tap room →'),

  // ---------------- 底栏工具 ----------------
  'tool_select': (zh: '选择', en: 'Select'),
  'tool_wall': (zh: '画墙', en: 'Wall'),
  'tool_room': (zh: '建房', en: 'Room'),
  'placing_model': (zh: '放：{0} → 点{1}（放下后自动回选择）', en: 'Place: {0} → tap the {1} (returns to Select)'),
  'placing_canvas': (zh: '放：{0} → 点画布（放下后自动回选择）', en: 'Place: {0} → tap the canvas (returns to Select)'),

  // ---------------- 模块一级菜单 ----------------
  'renovate': (zh: '拆改', en: 'Renovate'),
  'export_all': (zh: '全量导出', en: 'Export All'),
  'import_all': (zh: '全量导入', en: 'Import All'),

  // ---------------- 用户模型全量搬运 ----------------
  'dlg_export_user_models': (zh: '导出用户模型', en: 'Export User Models'),
  'export_user_empty': (
    zh: '用户模型为空：已导出 0 件（可导入到其他设备累积）→ {0}',
    en: 'No user models: exported 0 items (import on another device to accumulate) → {0}',
  ),
  'export_user_count': (zh: '已导出 {0} 件用户模型 → {1}', en: 'Exported {0} user models → {1}'),
  'dlg_import_user_models': (zh: '导入用户模型全量', en: 'Import All User Models'),
  'picker_failed': (zh: '打不开文件选择器：{0}', en: 'Could not open the file picker: {0}'),
  'read_user_models_failed': (zh: '读取用户模型失败：{0}', en: 'Failed to read user models: {0}'),
  'import_failed_reason': (zh: '导入失败：{0}', en: 'Import failed: {0}'),
  'import_count': (zh: '导入 {0} 件，跳过 {1} 件', en: 'Imported {0}, skipped {1}'),

  // ---------------- 放置提示（SnackBar） ----------------
  'tap_canvas_place': (
    zh: '放置「{0}」：点画布摆放（放下后自动回选择）',
    en: 'Place "{0}": tap the canvas (returns to Select)',
  ),
  'place_lib': (
    zh: '放置「{0}」（库模型）：点画布摆放（放下后自动回选择）',
    en: 'Place "{0}" (library model): tap the canvas (returns to Select)',
  ),
  'place_model_wall': (
    zh: '放置「{0}」：点一面墙开洞（放下后自动回选择）',
    en: 'Place "{0}": tap a wall to cut an opening (returns to Select)',
  ),
  'split_need_room': (
    zh: '先点选一个房间，再走 模块 → 拆改 → 分房间',
    en: 'Select a room first, then Modules → Renovate → Split Room',
  ),
  'no_wall_for_opening': (
    zh: '点不到墙：门窗要贴着墙放，先点一面墙',
    en: 'No wall there: doors and windows need a wall — tap one first',
  ),
  'opened_item': (zh: '已开 {0}', en: 'Opened {0}'),
  'cut_opening_item': (zh: '开洞 {0}', en: 'Opening {0}'),
  'placed_item': (
    zh: '已放「{0}」（已回选择，点中后可拖动位置）',
    en: 'Placed "{0}" (back to Select; tap it to drag)',
  ),
  'deleted_item': (zh: '已删除该件', en: 'Item deleted'),
  'nothing_hit': (zh: '没点到对象', en: 'Nothing selected'),
  'no_wall_draw_first': (
    zh: '点不到墙：先画一段墙，再点墙开洞',
    en: 'No wall there: draw a wall first, then tap it to add an opening',
  ),

  // ---------------- 旋转 / 保存 / 新建 ----------------
  'rotated': (zh: '已旋转 {0}°', en: 'Rotated {0}°'),
  'no_walls_to_rotate': (zh: '没有可旋转的墙', en: 'No walls to rotate'),
  'current_angle': (zh: '当前 {0}°（绕户型中心）', en: 'Current {0}° (around the plan center)'),
  'apply_rotate': (zh: '应用旋转', en: 'Apply Rotation'),
  'save_plan_title': (zh: '保存户型', en: 'Save Plan'),
  'file_name': (zh: '文件名', en: 'File name'),
  'save_helper': (zh: '将存入本机「我的户型」', en: 'Saved to "My Plans" on this device'),
  'save_as_external': (zh: '另存到外部…', en: 'Save As External…'),
  'save_failed': (zh: '保存失败', en: 'Save failed'),
  'clear_canvas_q': (zh: '清空当前画布？（可撤销）', en: 'Clear the current canvas? (Undoable)'),
  'create_new': (zh: '新建', en: 'New'),

  // ---------------- 拆改 / 房间操作 ----------------
  'renovate_title': (zh: '拆改', en: 'Renovate'),
  'split_room_option': (zh: '分房间', en: 'Split room'),
  'split_room_hint': (
    zh: '一个房间一分为二（加隔墙，可带门）',
    en: 'Split one room into two (adds a wall, door optional)',
  ),
  'merge_room_option': (zh: '合并房间', en: 'Merge rooms'),
  'merge_room_hint': (zh: '两间合一（待上线）', en: 'Merge two rooms (coming soon)'),
  'merge_pick_neighbor': (
    zh: '点一个与它相邻的房间 → 合并（删共用隔墙）',
    en: 'Tap an adjacent room → merge (removes the shared wall)',
  ),
  'not_adjacent': (
    zh: '两个房间不相邻（没有共用隔墙），不能合并',
    en: 'These rooms are not adjacent (no shared wall) — cannot merge',
  ),
  'merge_title': (zh: '合并房间', en: 'Merge Rooms'),
  'merge_body': (
    zh: '合并将删除两房间之间的隔墙（含该墙上的门窗开洞）？',
    en: 'Merge deletes the wall between the two rooms (including its openings)?',
  ),
  'merged': (zh: '已合并：隔墙已删除', en: 'Merged: shared wall removed'),
  'merge_action': (zh: '合并', en: 'Merge'),
  'room_changed': (zh: '房间已变化，请重新点选', en: 'Rooms changed — please select again'),
  'remove_room_title': (zh: '删除房间', en: 'Delete Room'),
  'remove_room_body': (
    zh: '删除该房间的隔墙（与其他房间/外部共用的外墙会保留）？',
    en: 'Delete this room\'s walls (walls shared with other rooms or outside are kept)?',
  ),
  'removed_walls': (zh: '已删除 {0} 面隔墙', en: 'Deleted {0} walls'),
  'room_all_shared': (
    zh: '该房间全为共用墙，未删除',
    en: 'All walls are shared — nothing deleted',
  ),

  // ---------------- 选中对象操作条 ----------------
  'item_bar_hint': (
    zh: '已放 {0} · 拖动可移位置 · 双击改尺寸/旋转',
    en: 'Placed: {0} · drag to move · double-tap to resize/rotate',
  ),
  'opening_bar_hint': (zh: '{0} · 拖动可沿墙改位置', en: '{0} · drag along the wall to move'),
  'wall_bar_hint': (
    zh: '墙 {0} · 长 {1}mm · 厚 {2} · 开洞 {3}',
    en: 'Wall {0} · L {1}mm · T {2} · openings {3}',
  ),
  'room_bar_hint': (zh: '房间 {0}㎡ · 拖动可移动位置', en: 'Room {0}㎡ · drag to move'),
  'act_size': (zh: '改尺寸', en: 'Size'),
  'act_delete': (zh: '删除', en: 'Delete'),
  'act_cancel': (zh: '取消', en: 'Cancel'),
  'act_remove_opening': (zh: '删开洞', en: 'Del'),
  'act_add_opening': (zh: '加开洞', en: 'Add'),
  'act_delete_wall': (zh: '删墙', en: 'Del wall'),
  'act_split': (zh: '拆房', en: 'Split'),

  // ---------------- 拆房面板 ----------------
  'split_title': (zh: '拆房（房间 {0}）', en: 'Split Room ({0})'),
  'split_axis_lr': (zh: '左右分（竖直墙）', en: 'Left / Right (vertical wall)'),
  'split_axis_tb': (zh: '上下分（水平墙）', en: 'Top / Bottom (horizontal wall)'),
  'split_position': (zh: '位置 {0}%', en: 'Position {0}%'),
  'split_with_door': (zh: '隔墙加门（900）', en: 'Add door to new wall (900)'),
  'split_done': (zh: '已拆房：隔墙 + {0}', en: 'Room split: new wall + {0}'),
  'split_failed': (
    zh: '该房间太小或非轴对齐，拆不了',
    en: 'Room is too small or not axis-aligned — cannot split',
  ),
  'split_action': (zh: '拆分', en: 'Split'),

  // ---------------- 墙编辑面板 ----------------
  'mm_size_int_required': (zh: '尺寸需 ≥1 mm 的整数（单位 mm）', en: 'Size must be an integer ≥1 mm'),
  'wall_dims_updated': (zh: '墙尺寸已更新', en: 'Wall size updated'),
  'opening_ints_required': (
    zh: '开洞参数需 ≥0 的整数（单位 mm）',
    en: 'Opening values must be integers ≥0 (in mm)',
  ),
  'opening_added': (zh: '已加开洞', en: 'Opening added'),
  'wall_missing': (zh: '墙已不存在', en: 'Wall no longer exists'),
  'wall_info': (
    zh: '墙 {0} · 当前 长 {1}mm · 厚 {2}mm · 高 {3}mm',
    en: 'Wall {0} · length {1}mm · thickness {2}mm · height {3}mm',
  ),
  'wall_size': (zh: '墙尺寸', en: 'Wall Size'),
  'field_size': (zh: '尺寸', en: 'Length'),
  'wall_height': (zh: '墙高', en: 'Height'),
  'wall_thickness': (zh: '墙厚', en: 'Thickness'),
  'apply_wall_dims': (
    zh: '应用墙尺寸（固定起点缩放）',
    en: 'Apply wall size (anchored at start point)',
  ),
  'openings_section': (zh: '开洞（门 / 窗）', en: 'Openings (door / window)'),
  'offset_from_wall': (zh: '离墙距离', en: 'Offset'),
  'width': (zh: '宽', en: 'Width'),
  'field_width_full': (zh: '宽度', en: 'Width'),
  'window_height': (zh: '窗高', en: 'Window height'),
  'door_height': (zh: '门高', en: 'Door height'),
  'sill_height': (zh: '窗台高', en: 'Sill height'),
  'swing_direction': (zh: '开门方向', en: 'Swing'),
  'swing_in': (zh: '内开', en: 'Inward'),
  'swing_out': (zh: '外开', en: 'Outward'),
  'hinge': (zh: '铰链', en: 'Hinge'),
  'hinge_left': (zh: '左开', en: 'Left'),
  'hinge_right': (zh: '右开', en: 'Right'),
  'add_window': (zh: '加窗', en: 'Add window'),
  'add_door': (zh: '加门', en: 'Add door'),
  'delete_this_wall': (zh: '删除此墙', en: 'Delete this wall'),

  // ---------------- 开洞面板 ----------------
  'opening_missing': (zh: '该开洞已不存在', en: 'Opening no longer exists'),
  'opening_wall_missing': (
    zh: '所属墙已不存在，无法修改',
    en: 'Parent wall no longer exists — cannot edit',
  ),
  'opening_params_invalid': (
    zh: '参数需为 ≥0 的整数（单位 mm），宽度/洞高 ≥1',
    en: 'Values must be integers ≥0 (mm); width / height ≥1',
  ),
  'opening_updated': (zh: '开洞参数已更新', en: 'Opening updated'),
  'opening_gone': (zh: '开洞已不存在', en: 'Opening does not exist'),
  'label_door_zero': (zh: '（门=0）', en: ' (door = 0)'),
  'opening_info': (zh: '开洞 {0} · {1} · 宽 {2}mm', en: 'Opening {0} · {1} · width {2}mm'),
  'margin_wall_end': (zh: '边距(墙端)', en: 'Margin (wall end)'),
  'height_from_floor': (zh: '离地高度', en: 'Height above floor'),
  'opening_height': (zh: '洞高', en: 'Opening height'),
  'delete_this_opening': (zh: '删除该开洞', en: 'Delete this opening'),

  // ---------------- 物品面板 ----------------
  'item_size_int_required': (
    zh: '尺寸需 ≥10mm 的整数（单位 mm）',
    en: 'Size must be an integer ≥10mm',
  ),
  'lift_int_required': (
    zh: '离地高度需 ≥0 的整数（单位 mm）',
    en: 'Height above floor must be an integer ≥0mm',
  ),
  'lift_range': (
    zh: '离地高度需在 0..{0} mm 之间',
    en: 'Height above floor must be within 0..{0} mm',
  ),
  'item_updated': (zh: '尺寸/旋转已更新', en: 'Size / rotation updated'),
  'item_missing': (zh: '该件已不存在', en: 'Item no longer exists'),
  'item_title': (zh: '{0} · 改尺寸/旋转', en: '{0} · Resize / Rotate'),
  'field_depth': (zh: '深', en: 'Depth'),
  'field_high': (zh: '高', en: 'Height'),
  'stair_lift_hint': (
    zh: '楼梯整体底部离地（mm），二楼/错层场景用；默认 0',
    en: 'Stair base above the floor (mm); for upper floors / split levels. Default 0',
  ),
  'beam_lift_hint': (
    zh: '梁底相对本层地面（mm，0..6000，±50 步进）；梁高在上方「高」里改，2D 占地不变',
    en: 'Beam underside above this floor (mm, 0..6000, ±50 steps); edit beam height in "Height" above; 2D footprint unchanged',
  ),
  'platform_lift_hint': (
    zh: '台底相对地面（mm，0..3000，±50 步进）；台面标高 = 离地 + 高，2D 占地不变',
    en: 'Platform underside above the floor (mm, 0..3000, ±50 steps); top = lift + height; 2D footprint unchanged',
  ),
  'asset_lift_hint': (
    zh: '实模底部离地（mm，0..3000，±50 步进）：遮阳棚等吊装件用；默认取素材规格（遮阳棚 1500），2D 占地不变',
    en: 'Model bottom above the floor (mm, 0..3000, ±50 steps): for hung items such as awnings; defaults to the asset spec (awning 1500); 2D footprint unchanged',
  ),
  'delete_this_item': (zh: '删除该件', en: 'Delete this item'),

  // ---------------- 一键建房间 ----------------
  'room_dims_invalid': (
    zh: '长/宽 ≥500mm，高 ≥1000mm，门宽 ≥400mm（单位 mm，整数）',
    en: 'Length / width ≥500mm, height ≥1000mm, door width ≥400mm (mm, integers)',
  ),
  'room_created_note': (
    zh: '已建房间 {0}×{1} mm{2}，相机已适配',
    en: 'Room created {0}×{1} mm{2}; camera fitted',
  ),
  'with_door_suffix': (zh: '（含门）', en: ' (with door)'),
  'room_dialog_title': (zh: '一键建房间', en: 'One-tap Room'),
  'preset_bedroom': (zh: '卧室 3000×4000', en: 'Bedroom 3000×4000'),
  'preset_living': (zh: '客厅 4500×6000', en: 'Living room 4500×6000'),
  'preset_bath': (zh: '卫生间 2500×3000', en: 'Bathroom 2500×3000'),
  'preset_kitchen': (zh: '厨房 2400×2100', en: 'Kitchen 2400×2100'),
  'room_dims_hint': (
    zh: '尺寸（mm，房间生成在视口中央）',
    en: 'Size (mm; the room is created at the viewport center)',
  ),
  'field_length': (zh: '长', en: 'Length'),
  'bottom_door': (zh: '底墙加门', en: 'Door on bottom wall'),
  'door_width': (zh: '门宽', en: 'Door width'),
  'create_room': (zh: '创建房间', en: 'Create Room'),

  // ---------------- 家具抽屉 / 模型库 ----------------
  'furniture_header': (zh: '家具 · {0}（{1} 件）', en: 'Furniture · {0} ({1})'),
  'export_lib': (zh: '导出模型库', en: 'Export Library'),
  'import_lib': (zh: '导入模型库', en: 'Import Library'),
  'import_model_ellipsis': (zh: '导入模型…', en: 'Import Model…'),
  'dlg_import_model': (zh: '导入模型', en: 'Import Model'),
  'no_file_selected': (zh: '未选择文件（已取消）', en: 'No file selected (cancelled)'),
  'dlg_export_lib': (zh: '导出模型库', en: 'Export Library'),
  'lib_empty': (
    zh: '模型库为空：已导出 0 条（可导入到其他设备累积）→ {0}',
    en: 'Library is empty: exported 0 entries (import on another device to accumulate) → {0}',
  ),
  'lib_exported': (zh: '已导出 {0} 条模型 → {1}', en: 'Exported {0} models → {1}'),
  'dlg_import_lib': (zh: '导入模型库', en: 'Import Library'),
  'lib_read_failed': (zh: '读取模型库失败：{0}', en: 'Failed to read the library: {0}'),
  'lib_invalid_suffix': (zh: '，{0} 条无效', en: ', {0} invalid'),
  'lib_imported': (
    zh: '导入 {0} 条，跳过 {1} 条重复{2}',
    en: 'Imported {0}, skipped {1} duplicates{2}',
  ),
  'single_exported': (zh: '已导出「{0}」单件模型 → {1}', en: 'Exported "{0}" → {1}'),
  'single_exported_box': (
    zh: '已导出「{0}」单件模型（占位盒）→ {1}',
    en: 'Exported "{0}" (placeholder box) → {1}',
  ),

  // ---------------- 模型导入命名框 ----------------
  'name_required': (zh: '名称不能为空', en: 'Name is required'),
  'dim_range': (zh: '{0} 需在 1~50000mm，或改单位', en: '{0} must be 1–50000mm, or change the unit'),
  'field_name': (zh: '名称', en: 'Name'),
  'faces_from_obj': (
    zh: '{0} 个面 · 尺寸取自 OBJ 包围盒（可改）',
    en: '{0} faces · size taken from the OBJ bounding box (editable)',
  ),
  'faces_scaled': (
    zh: '{0} 个面 · 尺寸 = 包围盒 × 原文件单位（可改）',
    en: '{0} faces · size = bounding box × source unit (editable)',
  ),
  'furniture_category': (zh: '家具分类（{0}）', en: 'Furniture category ({0})'),
  'source_unit': (zh: '原文件单位', en: 'Source unit'),
  'stock_in': (zh: '入库', en: 'Add to Library'),
  'lib_model': (zh: '库模型', en: 'Library model'),
  'already_in_lib': (
    zh: '已在库中：{0}（id 重复，已跳过）',
    en: 'Already in the library: {0} (duplicate id skipped)',
  ),
  'import_failed': (zh: '导入失败', en: 'Import failed'),
  'importing_file': (zh: '正在导入「{0}」…', en: 'Importing "{0}"…'),
  'read_file_failed': (zh: '读取文件失败：{0}', en: 'Failed to read the file: {0}'),
  'single_json_parse_failed': (
    zh: '单模型 JSON 解析失败：{0}',
    en: 'Failed to parse the single-model JSON: {0}',
  ),
  'store_failed': (zh: '入库失败：{0}', en: 'Failed to store: {0}'),
  'obj_parse_failed': (zh: 'OBJ 解析失败：{0}', en: 'Failed to parse the OBJ: {0}'),
  'decimate_failed': (zh: '自动压缩失败：{0}', en: 'Auto-decimation failed: {0}'),
  'decimate_degenerate': (
    zh: '压缩后模型退化（0 面），请先在电脑上减面',
    en: 'Model degenerated after decimation (0 faces); reduce faces on a computer first',
  ),
  'decimate_over_limit': (
    zh: '压缩后仍超限（{0} 面/{1} KB），请先在电脑上减面',
    en: 'Still over the limit after decimation ({0} faces / {1} KB); reduce faces on a computer first',
  ),
  'decimate_note': (
    zh: '面数较大，已自动压缩 {0} → {1}',
    en: 'High face count — auto-decimated {0} → {1}',
  ),
  'import_cancelled': (zh: '已取消导入', en: 'Import cancelled'),
  'scaled_over_limit': (
    zh: '换算后仍超限（{0} KB），请先在电脑上减面',
    en: 'Still over the limit after unit conversion ({0} KB); reduce faces on a computer first',
  ),

  // ---------------- 素材网格 / 用户素材 ----------------
  'cat_assets_header': (zh: '{0} · 素材（{1} 件）', en: '{0} · Assets ({1})'),
  'user_assets_header': (zh: '用户素材（{0} 件）', en: 'User Assets ({0})'),
  'credit_line': (zh: '3D 素材署名：{0}', en: '3D asset credits: {0}'),
  'dlg_import_user_assets': (zh: '导入用户素材', en: 'Import User Assets'),
  'user_badge': (zh: '用户', en: 'User'),

  // ---------------- 分类 / 叶子名 ----------------
  'leaf_door': (zh: '门', en: 'Doors'),
  'leaf_window': (zh: '窗', en: 'Windows'),
  'leaf_column_beam': (zh: '梁柱', en: 'Columns & Beams'),
  'leaf_stair': (zh: '楼梯', en: 'Stairs'),
  'leaf_special': (zh: '特殊墙窗', en: 'Special Walls'),
  'leaf_furniture': (zh: '家具', en: 'Furniture'),
  'leaf_courtyard': (zh: '庭院', en: 'Courtyard'),
  'leaf_user_assets': (zh: '用户素材', en: 'User Assets'),
  'cat_door': (zh: '门', en: 'Doors'),
  'cat_window': (zh: '窗', en: 'Windows'),
  'cat_pillar': (zh: '柱', en: 'Columns'),
  'cat_beam': (zh: '梁', en: 'Beams'),
  'cat_stair': (zh: '楼梯', en: 'Stairs'),
  'cat_counter': (zh: '台面/五金', en: 'Countertops & Hardware'),
  'cat_special': (zh: '特殊墙窗', en: 'Special Walls'),
  'cat_courtyard': (zh: '庭院', en: 'Courtyard'),
  'cat_furniture': (zh: '家具', en: 'Furniture'),
  'cat_bedroom': (zh: '卧室', en: 'Bedroom'),
  'cat_living': (zh: '客餐厅', en: 'Living & Dining'),
  'cat_study': (zh: '书房', en: 'Study'),
  'cat_kitchen_bath': (zh: '厨卫', en: 'Kitchen & Bath'),
  'cat_other': (zh: '其他', en: 'Other'),

  // ---------------- 门型 / 开洞标签 ----------------
  'door_type_doorway': (zh: '门洞', en: 'Doorway'),
  'door_type_single': (zh: '单开门', en: 'Single Door'),
  'door_type_double': (zh: '双开门', en: 'Double Door'),
  'door_type_sliding': (zh: '移门', en: 'Sliding Door'),
  'spec_doorway': (zh: '洞口', en: 'Opening'),
  'spec_window': (zh: '窗', en: 'Window'),
  'spec_sill': (zh: ' 台{0}', en: ' sill {0}'),
  'window_label_sill': (zh: '窗 {0}×{1}(台{2})', en: 'Window {0}×{1} (sill {2})'),
  'window_label': (zh: '窗 {0}×{1}', en: 'Window {0}×{1}'),
  'swing_suffix_in': (zh: '内开', en: ' inward'),
  'swing_suffix_out': (zh: '外开', en: ' outward'),
  'hinge_suffix_left': (zh: '·左开', en: ' · left'),
  'hinge_suffix_right': (zh: '·右开', en: ' · right'),

  // ---------------- 户型保存写回提示 ----------------
  'saved': (zh: '已保存', en: 'Saved'),
  'saved_synced': (zh: '已保存并同步到原路径', en: 'Saved and synced to the original path'),
  'saved_local_saf': (
    zh: '已保存本地；外部原文件需重新导出（SAF 无持久写权限）',
    en: 'Saved locally; re-export the external file (no persistent SAF write access)',
  ),
  'saved_local_writeback_failed': (
    zh: '已保存本地，原路径写回失败（权限？）',
    en: 'Saved locally; write-back to the original path failed (permissions?)',
  ),
  'dlg_export_plan': (zh: '导出户型', en: 'Export Plan'),
  'dlg_export_model': (zh: '导出模型', en: 'Export Model'),
  'dlg_export_single': (zh: '导出单件模型', en: 'Export Model'),
  'dlg_import_plan': (zh: '导入户型', en: 'Import Plan'),

  // ---------------- 领域层异常（会被 toast/对话框展示） ----------------
  'plan_name_empty': (zh: '户型名不能为空', en: 'Plan name cannot be empty'),
  'plan_name_duplicate': (zh: '已有同名户型', en: 'A plan with that name already exists'),
  'not_single_model_file': (
    zh: '不是单模型文件：顶层应为 JSON 对象',
    en: 'Not a single-model file: the top level must be a JSON object',
  ),
  'is_full_model_file': (
    zh: '这是全量模型文件，请用「全量导入」',
    en: 'This is a full model export — use "Import All"',
  ),
  'single_model_missing_fields': (
    zh: '单模型文件缺少 id / objText',
    en: 'Single-model file is missing id / objText',
  ),
  'not_user_model_file': (
    zh: '不是用户模型全量文件：顶层应为 JSON 对象',
    en: 'Not a user-model export: the top level must be a JSON object',
  ),
  'bad_user_model_type': (
    zh: '不是用户模型全量文件：type 应为 userModels',
    en: 'Not a user-model export: type must be userModels',
  ),
  'user_model_missing_models': (
    zh: '用户模型全量文件缺少 models 数组',
    en: 'User-model export is missing the models array',
  ),
  'obj_too_large': (
    zh: 'OBJ 文件过大：{0} 字符，上限 {1}MB 文本',
    en: 'OBJ file too large: {0} characters, limit {1}MB of text',
  ),
  'obj_face_limit': (
    zh: '面数超出解析上限：{0} 面，上限 {1} 面（请先在电脑上减面）',
    en: 'Face count over the parse limit: {0} faces, limit {1} (reduce faces on a computer first)',
  ),
  'obj_no_vertices': (zh: 'OBJ 没有顶点数据（缺少 v 行）', en: 'OBJ has no vertex data (missing v lines)'),
  'obj_no_faces': (zh: 'OBJ 没有面数据（缺少 f 行）', en: 'OBJ has no face data (missing f lines)'),
  'obj_empty_bbox': (
    zh: 'OBJ 包围盒为空（所有顶点重合）',
    en: 'OBJ bounding box is empty (all vertices coincide)',
  ),
  'obj_too_large_chars': (
    zh: 'OBJ 文件过大：{0} 字符，上限 {1} 字符',
    en: 'OBJ file too large: {0} characters, limit {1}',
  ),
  'obj_face_limit_short': (zh: '面数超限：{0} 面，上限 {1} 面', en: 'Face count over limit: {0} faces, limit {1}'),

  // ---------------- 家具目录（FurnitureKind） ----------------
  'furn_sofa': (zh: '沙发', en: 'Sofa'),
  'furn_bed': (zh: '床', en: 'Bed'),
  'furn_table': (zh: '餐桌', en: 'Dining Table'),
  'furn_chair': (zh: '椅', en: 'Chair'),
  'furn_wardrobe': (zh: '衣柜', en: 'Wardrobe'),
  'furn_tv': (zh: '电视柜', en: 'TV Cabinet'),
  'furn_plant': (zh: '绿植', en: 'Plant'),
  'furn_desk': (zh: '书桌', en: 'Desk'),
  'furn_stool': (zh: '凳子', en: 'Stool'),
  'furn_fridge': (zh: '冰箱', en: 'Fridge'),
  'furn_washer': (zh: '洗衣机', en: 'Washer'),
  'furn_heater': (zh: '热水器', en: 'Water Heater'),
  'furn_stove': (zh: '燃气灶', en: 'Cooktop'),
  'furn_hood': (zh: '烟机', en: 'Range Hood'),
  'furn_sink': (zh: '水槽', en: 'Sink'),
  'furn_microwave': (zh: '微波炉', en: 'Microwave'),
  'furn_oven': (zh: '烤箱', en: 'Oven'),
  'furn_coffee': (zh: '茶几', en: 'Coffee Table'),
  'furn_shoe': (zh: '鞋柜', en: 'Shoe Cabinet'),
  'furn_shelf': (zh: '置物架', en: 'Shelf'),
  'furn_asset': (zh: '素材', en: 'Asset'),
  'furn_pillar': (zh: '方柱', en: 'Square Column'),
  'furn_roundPillar': (zh: '圆柱', en: 'Round Column'),
  'furn_stair': (zh: '直楼梯', en: 'Straight Stair'),
  'furn_stairL': (zh: '左拐楼梯', en: 'Left Stair'),
  'furn_stairR': (zh: '右拐楼梯', en: 'Right Stair'),
  'furn_vanity': (zh: '梳妆台', en: 'Vanity'),
  'furn_gasStove': (zh: '燃气灶', en: 'Gas Cooktop'),
  'furn_gasCupboard': (zh: '燃气柜', en: 'Gas Cabinet'),
  'furn_drain': (zh: '下水口', en: 'Drain'),
  'furn_pipe': (zh: '落管', en: 'Pipe'),
  'furn_meterBox': (zh: '电表箱', en: 'Meter Box'),
  'furn_waterMeter': (zh: '水表', en: 'Water Meter'),
  'furn_radiator': (zh: '暖气片', en: 'Radiator'),
  'furn_acSlot': (zh: '空调洞', en: 'AC Hole'),
  'furn_socketWall': (zh: '墙插', en: 'Wall Socket'),
  'furn_socketFloor': (zh: '地插', en: 'Floor Socket'),
  'furn_switchPanel': (zh: '开关', en: 'Switch'),
  'furn_landing': (zh: '平台', en: 'Landing'),
  'furn_arcWall': (zh: '弧形墙', en: 'Arc Wall'),
  'furn_beam': (zh: '梁', en: 'Beam'),
  'furn_duct': (zh: '风管', en: 'Duct'),
  'furn_pipeCase': (zh: '包管道', en: 'Pipe Box'),
  'furn_barePipe': (zh: '裸管', en: 'Bare Pipe'),
  'furn_platform': (zh: '地台', en: 'Platform'),
  'furn_lib': (zh: '库模型', en: 'Library Model'),

  // ---------------- 模型目录（ModelSpec.id） ----------------
  'model_menjin': (zh: '进户门', en: 'Entry Door'),
  'model_yimen': (zh: '单开门', en: 'Single Door'),
  'model_shuangkaimen': (zh: '双开门', en: 'Double Door'),
  'model_mendong': (zh: '门洞', en: 'Doorway'),
  'model_yakou': (zh: '垭口', en: 'Cased Opening'),
  'model_yimen_huadong': (zh: '移门', en: 'Sliding Door'),
  'model_m_door1': (zh: '标准单门', en: 'Standard Door'),
  'model_m_frontDoorDark': (zh: '入户大门', en: 'Front Door'),
  'model_m_frenchDoors': (zh: '法式门', en: 'French Doors'),
  'model_m_thick_double_2x4': (zh: '厚框双移门', en: 'Double Sliding Door'),
  'model_m_doorGlassPanels': (zh: '玻璃门', en: 'Glass Door'),
  'model_luodichuang': (zh: '落地窗', en: 'Floor Window'),
  'model_piaochuang': (zh: '飘窗', en: 'Bay Window'),
  'model_chuang': (zh: '普通窗', en: 'Window'),
  'model_huxingchuang': (zh: '凸窗', en: 'Projecting Window'),
  'model_zhichuang': (zh: '高窗', en: 'High Window'),
  'model_wangkou': (zh: '窗口', en: 'Window Opening'),
  'model_m_window_deep': (zh: '深窗框', en: 'Deep Frame Window'),
  'model_m_window_double_sill': (zh: '双框窗台', en: 'Double Sill Window'),
  'model_fangzhu': (zh: '方柱', en: 'Square Column'),
  'model_yuanzhu': (zh: '圆柱', en: 'Round Column'),
  'model_liang': (zh: '梁', en: 'Beam'),
  'model_fengguan': (zh: '风管', en: 'Duct'),
  'model_baoguandao': (zh: '包管道', en: 'Pipe Box'),
  'model_laoguan': (zh: '裸管', en: 'Bare Pipe'),
  'model_ditai': (zh: '地台', en: 'Platform'),
  'model_zhilouti': (zh: '直楼梯', en: 'Straight Stair'),
  'model_youzhuanjiaolouti': (zh: '右拐楼梯', en: 'Right Stair'),
  'model_zuozhuanjiaolouti': (zh: '左拐楼梯', en: 'Left Stair'),
  'model_shuzhuangtai': (zh: '梳妆台', en: 'Vanity'),
  'model_ranqizao': (zh: '燃气灶', en: 'Gas Cooktop'),
  'model_ranqigui': (zh: '燃气柜', en: 'Gas Cabinet'),
  'model_xiashuikou': (zh: '下水口', en: 'Drain'),
  'model_luoguan': (zh: '落管', en: 'Pipe'),
  'model_meiqibiao': (zh: '电表箱', en: 'Meter Box'),
  'model_shuibiao': (zh: '水表', en: 'Water Meter'),
  'model_nuanqipian': (zh: '暖气片', en: 'Radiator'),
  'model_kongtiaodong': (zh: '空调洞', en: 'AC Hole'),
  'model_qiangdianxiang': (zh: '墙插', en: 'Wall Socket'),
  'model_ruodianxiang': (zh: '地插', en: 'Floor Socket'),
  'model_kaiguan': (zh: '开关', en: 'Switch'),
  'model_pingtai': (zh: '平台', en: 'Landing'),
  'model_huxiangqiang': (zh: '弧形墙', en: 'Arc Wall'),
  'model_huxiangchuang': (zh: '弧形窗', en: 'Arc Window'),
  'model_m_courtyard_awning': (zh: '遮阳棚支架', en: 'Awning Frame'),
  'model_m_courtyard_birch': (zh: '白桦', en: 'Birch'),
  'model_m_courtyard_chair': (zh: '黑色露台椅', en: 'Black Patio Chair'),
  'model_m_courtyard_table': (zh: '黑色露台桌', en: 'Black Patio Table'),
  'model_m_courtyard_palm': (zh: '扇叶棕榈', en: 'Fan Palm'),
  'model_m_courtyard_fountain': (zh: '庭院喷泉', en: 'Courtyard Fountain'),
  'model_m_courtyard_greenhouse': (zh: '温室', en: 'Greenhouse'),
  'model_m_courtyard_pine': (zh: '松树', en: 'Pine'),
  'model_m_courtyard_railing': (zh: '栏杆', en: 'Railing'),
  'model_m_courtyard_sassafras': (zh: '马桑树', en: 'Sassafras'),
  'model_m_courtyard_tree': (zh: '庭院树', en: 'Courtyard Tree'),
  'model_m_furn_armoire': (zh: '衣柜', en: 'Wardrobe'),
  'model_m_furn_office_chair': (zh: '办公椅', en: 'Office Chair'),
  'model_m_furn_desk': (zh: '书桌', en: 'Desk'),
  'model_m_furn_stool': (zh: '坐凳', en: 'Stool'),
  'model_m_furn_cappa': (zh: '烟罩（cappa，待认）', en: 'Range Hood (cappa, unconfirmed)'),
  'model_m_furn_flowers': (zh: '插花', en: 'Flowers'),
  'model_m_furn_fridge_2': (zh: '冰箱', en: 'Fridge'),
  'model_m_furn_piano': (zh: '立式钢琴', en: 'Upright Piano'),
  'model_m_furn_potplant': (zh: '盆栽', en: 'Potted Plant'),
  'model_m_furn_refrigerator': (zh: '冰箱', en: 'Refrigerator'),
  'model_m_furn_piano_stool': (zh: '钢琴凳', en: 'Piano Stool'),
  'model_m_furn_frame_vatican': (zh: '画框', en: 'Picture Frame'),
  'model_m_furn_frame_yosemite': (zh: '画框', en: 'Picture Frame'),
  'model_m_furn_washer_dryer': (zh: '洗烘一体', en: 'Washer-Dryer'),
  'model_m_furn_upper_cab_2d': (zh: '双门吊柜', en: 'Double Wall Cabinet'),
  'model_m_furn_dresser': (zh: '斗柜', en: 'Dresser'),
  'model_m_furn_bed': (zh: '双人床', en: 'Double Bed'),
  'model_m_furn_pantry': (zh: '食品柜', en: 'Pantry'),
  'model_m_furn_lower_cab_1d': (zh: '单门地柜', en: 'Single Base Cabinet'),
  'model_m_furn_upper_cab_1d': (zh: '单门吊柜', en: 'Single Wall Cabinet'),
  'model_m_furn_lower_cab_2d': (zh: '双门地柜', en: 'Double Base Cabinet'),
  'model_m_furn_cab_3draw': (zh: '三抽柜', en: '3-Drawer Cabinet'),
  'model_m_furn_shower_tray': (zh: '淋浴底盘', en: 'Shower Tray'),
  'model_m_furn_vanity': (zh: '浴室柜', en: 'Bathroom Vanity'),
  'model_m_furn_jacuzzi': (zh: '按摩浴缸', en: 'Jacuzzi'),
  'model_m_furn_corner_cab': (zh: '转角柜', en: 'Corner Cabinet'),
  'model_m_furn_shower_room': (zh: '淋浴房', en: 'Shower Room'),
  'model_m_furn_hob': (zh: '燃气灶', en: 'Cooktop'),
  'model_m_furn_island': (zh: '中岛', en: 'Kitchen Island'),
  'model_m_furn_marble_sink': (zh: '大理石水槽柜', en: 'Marble Sink Cabinet'),
  'model_m_furn_mirror': (zh: '镜子', en: 'Mirror'),
  'model_m_furn_shower_cabin': (zh: '淋浴间', en: 'Shower Cabin'),
  'model_m_furn_toilet': (zh: '壁挂马桶', en: 'Wall-hung Toilet'),
  'model_m_furn_basin': (zh: 'water（卫浴小件）', en: 'Basin (small fixture)'),
  'model_m_furn_sofa_cherry': (zh: '樱桃沙发', en: 'Cherry Sofa'),
  'model_m_furn_sofa_cushion': (zh: '抱枕沙发', en: 'Cushion Sofa'),
  'model_m_furn_coffee_table': (zh: '茶几', en: 'Coffee Table'),
  'model_m_furn_sofa_large': (zh: '大沙发', en: 'Large Sofa'),
  'model_m_furn_chest_tall': (zh: '高柜', en: 'Tall Cabinet'),
  'model_m_furn_table_round': (zh: '圆桌', en: 'Round Table'),
  'model_m_furn_armchair': (zh: '单人沙发椅', en: 'Armchair'),
  'model_m_furn_table_low': (zh: '矮桌', en: 'Low Table'),

  // ---------------- 原 app 内置素材（ModelAsset.id） ----------------
  'asset_1001': (zh: '白色门板', en: 'White Door Panel'),
  'asset_1003': (zh: '黑色移门', en: 'Black Sliding Door'),
  'asset_1006': (zh: '黑色移门 B', en: 'Black Sliding Door B'),
  'asset_1004': (zh: '银色拉手', en: 'Silver Handle'),
  'asset_1005': (zh: '柜板', en: 'Cabinet Panel'),
  'asset_1007': (zh: '大衣柜', en: 'Large Wardrobe'),
  'asset_1009': (zh: '现代栏杆', en: 'Modern Railing'),
  'asset_5004': (zh: '柜体方块', en: 'Cabinet Block'),
  'asset_5005': (zh: '柜体', en: 'Cabinet Body'),
  'asset_5006': (zh: '柜体 B', en: 'Cabinet Body B'),
  'asset_7001': (zh: '小五金 A', en: 'Hardware A'),
  'asset_7002': (zh: '小五金 B', en: 'Hardware B'),
  'asset_7003': (zh: '小五金 C', en: 'Hardware C'),
  'asset_7004': (zh: '五金件 D', en: 'Hardware D'),
  'asset_7005': (zh: '五金件 E', en: 'Hardware E'),
  'asset_7006': (zh: '小五金 F', en: 'Hardware F'),
  'asset_7007': (zh: '小五金 G', en: 'Hardware G'),
  'asset_7008': (zh: '小五金 H', en: 'Hardware H'),
  'asset_7009': (zh: '小五金 I', en: 'Hardware I'),
  'asset_7101': (zh: '小五金 J', en: 'Hardware J'),
  'asset_7102': (zh: '小五金 K', en: 'Hardware K'),
  'asset_7104': (zh: '小五金 L', en: 'Hardware L'),
  'asset_7105': (zh: '小五金 M', en: 'Hardware M'),
  'asset_arcwall': (zh: '弧形墙', en: 'Arc Wall'),
  'asset_column': (zh: '方柱', en: 'Square Column'),
  'asset_cube': (zh: '立方体', en: 'Cube'),
};
