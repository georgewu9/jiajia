package com.georgewu.jiajia

import android.app.Application
import java.io.File

/**
 * 启动诊断（原生层探针）：
 * 与 Dart 侧写同一个文件 externalFilesDir/jiajia_diag.txt。
 * 判读：
 *   - 文件有 [NATIVE] 行、无 [DART] 行 → Dart isolate 没起来（引擎/AOT 层问题）
 *   - [DART] 行停在哪一里程碑 → main 内哪一步之前死的
 *   - 文件整个不存在 → 进程没起来 / 系统没给外部文件目录
 */
class DiagApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            val dir: File? = getExternalFilesDir(null)
            if (dir == null || !dir.exists()) return
            val f = File(dir, "jiajia_diag.txt")
            val prev = if (f.exists()) f.readText() else ""
            f.writeText(
                prev + "[NATIVE] " + java.time.LocalDateTime.now() +
                    " process-start pid=" + android.os.Process.myPid() + "\n"
            )
        } catch (_: Exception) {
        }
    }
}
