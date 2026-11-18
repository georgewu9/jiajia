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

  /// 上次快照里是否含异常行 = 上次运行确实崩过（不是「上次日志非空」）。
  bool _prevHasError = false;

  /// 是否需要自动弹诊断面板：本次已记录异常，或上次运行崩溃过。
  ///
  /// 修 v0.1.23（「一开 app 就落到日志页」根因）：
  /// 旧实现是 `_prev != null` —— 只要上次启动写过任何一行日志就判为有异常，
  /// 而 main() 每次启动都会写 main-start/binding-init/first-frame 等里程碑，
  /// 所以从第二次冷启动起 hasErrors 永远为 true，日志页每次启动都盖屏，
  /// 与「上次是否崩」无关。现在只认异常行（ERR），正常启动不再弹。
  bool get hasErrors => _lines.any(_isErrorLine) || _prevHasError;

  /// 异常行判据：error() 落盘格式是 `[ISO时间] ERR ...`，行首是时间戳，
  /// 所以不能直接 startsWith('ERR')（旧写法的第二个笔误：本次会话的异常
  /// 永远判不到，只能靠 main() 里的 panel 赋值兜着）。
  static bool _isErrorLine(String l) {
    final t = l.trimLeft();
    return t.startsWith('ERR') || t.contains('] ERR ');
  }

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
      // 防异常风暴刷爆文件（上次刷到 4.7MB）：只保留尾部 8KB
      if (_rawBuf.length > 8192) {
        _rawBuf = _rawBuf.substring(_rawBuf.length - 8192);
      }
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
    // 读完立刻判一次「上次崩没崩」，随后 f 被清空重写，
    // 保证崩溃痕迹只触发一次自动弹面板（本次正常跑完 → 下次不再弹）。
    _prevHasError = _prev != null && _prev!.split('\n').any(_isErrorLine);
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
    if (_prevHasError) out.add('【上次运行崩溃（日志已留档；本次已重新开始记录）】');
    if (_prev != null) out.add('【上次启动记录】\n$_prev');
    if (liveError != null) out.add('【本次运行异常】\n$liveError');
    if (_lines.isNotEmpty) out.add('【启动记录】\n${_lines.join('\n')}');
    return out.isEmpty ? '（无记录）' : out.join('\n\n');
  }
}

/// 全局单例（各页面打点用）。
final bootLog = BootLog();
