import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

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
      dialogTitle: '导出户型',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
    );
  }

  /// 弹出「打开文件」（只筛 .json），返回文件文本内容；用户取消 → null。
  static Future<String?> pickJsonText() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '导入户型',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    // 不信任扩展名之外的编码：非 UTF-8 会直接抛异常 → 调用方提示导入失败
    return utf8.decode(await file.readAsBytes());
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
