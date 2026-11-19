// 模型文件的外部读写（单件导出/全量导出/导入选文件）。
//
// 复用现有的 file_picker（SAF「另存为」/「打开文件」），不新引依赖：
//   · save：优先弹系统保存框；平台通道不可用（桌面预览/单测）→ 落到
//     app 文档目录 exports/ 下并返回真实路径（不静默丢文件）；
//   · pick：只筛 .obj/.json，读文本由调用方做。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/floor_plan.dart' show FurnitureCatalog, FurnitureKind;
import '../domain/model_asset_text.dart';
import '../domain/model_items.dart';
import 'lib_models_store.dart';
import 'model_transfer.dart';
import 'plan_io.dart';

class ModelFiles {
  const ModelFiles._();

  /// 文件名清洗：去掉路径分隔符/系统非法字符，空 → fallback。
  static String safeFileName(String raw, {String fallback = '模型'}) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) s = fallback;
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  /// 导出 JSON 文本；返回用户可见的落点文案，用户取消 → null。
  /// [fileName] 会自动补 `.json`（已有则不动）。
  static Future<String?> saveJson({
    required String fileName,
    required String json,
    String dialogTitle = '导出模型',
  }) async {
    final name = fileName.toLowerCase().endsWith('.json')
        ? fileName
        : '$fileName.json';
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      if (uri == null) return null; // 用户取消
      return PlanIo.displayLocation(uri, name);
    } catch (_) {
      // 平台通道不可用（widget 测试/桌面无 SAF）→ 落 app 文档目录 exports/。
      // 抛错交给调用方提示（真正的写盘失败不能假装成功）。
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/exports');
      await dir.create(recursive: true);
      final f = File('${dir.path}/$name');
      await f.writeAsString(json);
      return f.path;
    }
  }

  /// 选一个 .obj / .json 文件；用户取消 → null；平台通道异常向上抛。
  static Future<PlatformFile?> pickModelFile({String dialogTitle = '导入模型'}) {
    return FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: const ['obj', 'json'],
    );
  }

  /// 读选中文件为文本（宽松 UTF-8：非 UTF-8/半截文件不崩）。
  static Future<String> readText(PlatformFile file) async {
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 长按导出单件：把「系统 ModelSpec / 家具 kind / 用户 LibModel」统一变成
/// [ModelTransferItem] 再落盘。
class ModelExport {
  const ModelExport._();

  /// 系统 ModelSpec：modelId 命中 models.js/models_ext.js → 带真 OBJ；
  /// 未命中（柱/楼梯等程序化件）→ 占位盒。
  static Future<ModelTransferItem> forSpec(
    ModelSpec m, {
    required String cat,
    String? subCat,
  }) async {
    AssetModel? asset;
    if (m.modelId != null) {
      await ModelAssetLibrary.ensureLoaded();
      asset = ModelAssetLibrary.byId(m.modelId);
    }
    return ModelTransferItem.fromSpec(
      m,
      cat: cat,
      subCat: subCat,
      asset: asset,
    );
  }

  /// 家具目录 kind（床/衣柜等无 OBJ）→ 按目录尺寸生成占位盒。
  static ModelTransferItem forKind(
    FurnitureKind k, {
    required String cat,
    String? subCat,
    required String name,
  }) {
    final s = FurnitureCatalog.spec[k]!;
    final w = (s.$1 * 1000).round();
    final d = (s.$2 * 1000).round();
    final h = (s.$3 * 1000).round();
    return ModelTransferItem(
      id: 'kind_${k.name}',
      name: name,
      cat: cat,
      subCat: subCat,
      wmm: w,
      dmm: d,
      hmm: h,
      color: s.$4,
      objText: ModelTransferItem.placeholderBox(
        wmm: w,
        dmm: d,
        hmm: h,
        name: name,
      ),
    );
  }

  /// 用户模型：LibModel 直接转。
  static ModelTransferItem forLib(LibModel m) =>
      ModelTransferItem.fromLibModel(m);

  /// 落盘（用户选目录；平台无保存框 → 文档目录 exports/）。
  /// 返回落点文案，用户取消 → null。
  static Future<String?> save(
    ModelTransferItem item, {
    String? fileName,
  }) {
    return ModelFiles.saveJson(
      fileName: fileName ?? ModelFiles.safeFileName(item.name),
      json: item.encodeSingle(),
      dialogTitle: '导出单件模型',
    );
  }

  /// 用户全量导出。
  static Future<String?> saveAll(List<LibModel> models) {
    return ModelFiles.saveJson(
      fileName: UserModelExportCodec.fileName,
      json: UserModelExportCodec.encodeAll(models),
      dialogTitle: '导出用户模型',
    );
  }
}
