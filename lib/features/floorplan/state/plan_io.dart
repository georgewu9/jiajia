import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/floor_plan.dart';
import 'editor_doc.dart';
import '../../../app/i18n.dart';

/// 回写原文件的结果（编辑器保存时用）。
enum WriteBack { synced, skaf, failed }

/// 一次「导入」拿到的内容：文本 + 来源位置（file:// 或 content:// URI 串，
/// 回写原路径要用）+ 已解出的文件名（解不出 → null）。
class PickedJson {
  final String text;
  final String sourcePath;
  final String? fileName;
  const PickedJson(this.text, this.sourcePath, this.fileName);
}

/// 户型 JSON 的外部导出/导入（Android SAF，无需存储权限）。
///
/// 导出：`saveFile` 直接把字节交给系统「另存为」对话框，用户选中的目录
/// 由 SAF 写入（重装 app 不会被清掉）；导入：`pickFile` 走系统的打开文件
/// 对话框，读 bytes 后交给 `FloorPlan.fromJsonString` 解析。
///
/// 这里只做「文件↔字符串」的搬运，不认识户型结构；解析/校验由调用方做，
/// 出错抛异常让调用方统一提示。
class PlanIo {
  const PlanIo._();

  /// 弹出「另存为」，把 [json] 写成 [fileName]。
  /// 返回保存到的位置（file:// 为本地路径，Android 为 content:// URI）；
  /// 用户取消 → null。
  static Future<Uri?> exportJson({
    required String fileName,
    required String json,
  }) {
    return FilePicker.saveFile(
      dialogTitle: t('dlg_export_plan'),
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    );
  }

  /// 弹出「打开文件」（只筛 .json），返回文件文本 + 来源 URI；用户取消 → null。
  /// 保留来源位置是为了「保存时回写原路径」（v0.1.33）。
  static Future<PickedJson?> pickJsonMeta() async {
    final file = await FilePicker.pickFile(
      dialogTitle: t('dlg_import_plan'),
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final location = file.uri.toString();
    // 不信任扩展名之外的编码：非 UTF-8 会直接抛异常 → 调用方提示导入失败
    return PickedJson(
      utf8.decode(await file.readAsBytes()),
      location,
      pickedFileNameOf(location),
    );
  }

  /// 只要文本（旧入口，保留兼容；实现委托 [pickJsonMeta]）。
  static Future<String?> pickJsonText() async =>
      (await pickJsonMeta())?.text;

  /// 从 File 解出「导入文件名」（含扩展名），列表/SnackBar 用。
  static String? pickedFileName(File f) => pickedFileNameOf(f.path);

  /// [pickedFileName] 的字符串版（来源可以是 path 或 URI 串）。
  ///
  /// 三种来源：
  ///  · `file:///…/客厅.json`（桌面/部分 ROM）→ pathSegments.last
  ///  · `content://com.android.externalstorage.documents/document/primary%3ADownload%2F客厅.json`
  ///    （MIUI SAF）→ 末段解码后形如 `primary:Download/客厅.json`，冒号后取 basename
  ///  · 解不出（空路径/无末段/奇怪 scheme）→ null，调用方回退 JSON 内的 name
  static String? pickedFileNameOf(String location) {
    final uri = Uri.tryParse(location);
    if (uri == null) return null;
    final scheme = uri.scheme;
    if (scheme == 'file' || scheme.isEmpty) {
      // 普通文件系统路径（含 file:// URI）
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) return null;
      return _basename(_decode(segs.last));
    }
    if (scheme != 'content') return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    var last = _decode(segs.last);
    // SAF 文档 ID：`primary:Download/a.json` / `primary:%2Fstorage%2F…`
    final colon = last.lastIndexOf(':');
    if (colon >= 0) last = last.substring(colon + 1);
    return _basename(_decode(last));
  }

  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  /// 取末段文件名（兼容 `\` 分隔），空 → null。
  static String? _basename(String p) {
    final parts = p.replaceAll('\\', '/').split('/');
    final last = parts.isEmpty ? '' : parts.last.trim();
    return last.isEmpty ? null : last;
  }

  /// 保存后回写导入时的原文件（v0.1.33）。
  ///
  /// 返回：
  ///  · [WriteBack.synced] 真实文件系统路径，字节已写入；
  ///  · [WriteBack.skaf] `content://` — SAF 无持久写权限，需用户重新导出；
  ///  · [WriteBack.failed] 真实路径但写失败（权限/文件被删/目录不存在）。
  ///
  /// 不抛异常（保存本身已成功，回写失败只提示），便于单测。
  static WriteBack writeBack(Uint8List jsonBytes, String sourcePath) {
    if (sourcePath.startsWith('content://')) return WriteBack.skaf;
    String? path;
    if (sourcePath.startsWith('file://')) {
      try {
        path = Uri.parse(sourcePath).toFilePath();
      } catch (_) {
        return WriteBack.failed;
      }
    } else if (sourcePath.startsWith('/')) {
      path = sourcePath;
    } else {
      return WriteBack.failed;
    }
    try {
      File(path).writeAsBytesSync(jsonBytes, flush: true);
      return WriteBack.synced;
    } catch (_) {
      return WriteBack.failed;
    }
  }

  /// 保存到私有 `plans/`，并在「该户型是导入来的」时回写原文件（v0.1.33）。
  /// 返回给用户看的提示文案（编辑器直接显示）。
  ///
  /// 保存本身失败会抛异常（调用方提示「保存失败」）；回写失败只改文案，
  /// 不影响私有目录里的那份。
  static Future<String> saveAndSync(PlanStore store, FloorPlan plan) async {
    final json = plan.toJsonString();
    await store.save(plan);
    String? sourcePath;
    try {
      sourcePath = (await store.loadMeta())[plan.name]?['sourcePath'];
    } catch (_) {}
    if (sourcePath == null || sourcePath.isEmpty) return t('saved');
    return switch (writeBack(Uint8List.fromList(utf8.encode(json)), sourcePath)) {
      WriteBack.synced => t('saved_synced'),
      WriteBack.skaf => t('saved_local_saf'),
      WriteBack.failed => t('saved_local_writeback_failed'),
    };
  }

  /// 给 SnackBar 用的「导出到 …」文案：
  /// file:// 显示真实路径；SAF 的 content:// 取末段（去掉 primary: 前缀），
  /// 拿不到就退回文件名。
  static String displayLocation(Uri? saved, String fallback) {
    if (saved == null) return fallback;
    if (saved.scheme == 'file') return saved.toFilePath();
    if (saved.pathSegments.isEmpty) return fallback;
    final last = Uri.decodeComponent(saved.pathSegments.last);
    final colon = last.indexOf(':');
    return colon >= 0 ? last.substring(colon + 1) : last;
  }
}
