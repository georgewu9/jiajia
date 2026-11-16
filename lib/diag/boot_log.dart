import 'dart:io';

/// 启动诊断日志：内存缓冲 + 落盘（app documents/jiajia_boot.log）。
/// 用途：release 白屏时，下一次启动把上次的里程碑/异常显示在面板上，
/// 直接定位死在哪一步（main 之前 / 首帧 / provider / webview）。
class BootLog {
  static const file = 'jiajia_boot.log';
  static const keep = 60;

  final List<String> _lines = [];
  File? _file;
  String? _prev; // 上次启动的快照（面板优先展示）
  bool get hasErrors => _lines.any((l) => l.startsWith('ERR')) || _prev != null;

  // ---------- 原始外部文件探针（/sdcard/Android/data/<pkg>/files/） ----------
  // 系统在进程启动时就建好该目录，无需权限、不依赖 path_provider ——
  // main() 第一行就能写；与 Kotlin Application.onCreate 写同一文件，
  // 可精确切分：NATIVE 有 / DART 无 = isolate 没起来（引擎层）。
  File? _rawFile;
  String _rawBuf = '';

  void attachRaw(File f) {
    _rawFile = f;
    try {
      _rawBuf = f.existsSync() ? f.readAsStringSync() : '';
    } catch (_) {}
  }

  void _mirrorRaw() {
    try {
      _rawFile?.writeAsStringSync(_rawBuf);
    } catch (_) {}
  }

  /// 原生侧（Kotlin）打点：把标记合并进同一个文件。
  static void noteNative(File f, String marker) {
    try {
      f.writeAsStringSync(
          '${f.existsSync() ? f.readAsStringSync() : ''}[${DateTime.now()}] $marker\n');
    } catch (_) {}
  }

  /// 读上次留下的日志（面板用）。返回非 null 表示有历史内容。
  String? loadPrevious(File f) {
    try {
      if (!f.existsSync()) return null;
      final lines = f.readAsLinesSync().take(keep).toList();
      if (lines.isEmpty) return null;
      return lines.join('\n');
    } catch (_) {
      return null;
    }
  }

  void attach(File f) {
    _prev = loadPrevious(f);
    _file = f;
    try {
      f.writeAsStringSync('');
    } catch (_) {}
  }

  void line(String m) {
    final ts = DateTime.now().toIso8601String();
    final l = '[$ts] $m';
    _lines.add(l);
    if (_lines.length > keep) _lines.removeAt(0);
    try {
      _file?.writeAsStringSync(_lines.join('\n'));
    } catch (_) {}
    _rawBuf += '[DART] $l\n';
    _mirrorRaw();
  }

  void error(String m) => line('ERR $m');

  /// 面板正文：上次快照 + 当前错误 + 最近里程碑。
  String panelText({String? liveError}) {
    final out = <String>[];
    if (_prev != null) out.add('【上次启动记录】\n$_prev');
    if (liveError != null) out.add('【本次运行异常】\n$liveError');
    if (_lines.isNotEmpty) out.add('【启动记录】\n${_lines.join('\n')}');
    return out.isEmpty ? '（无记录）' : out.join('\n\n');
  }
}

/// 全局单例（各页面打点用）。
final bootLog = BootLog();
