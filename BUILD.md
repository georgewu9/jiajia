# jiajia — 构建备忘

画户型 → 摆家具 → 3D 浏览。Flutter + Riverpod + drift(计划) + Three.js WebView(计划 M3)。

## 里程碑

| M | 内容 | 状态 |
|---|---|---|
| M1 | 2D 户型编辑器（画墙/开洞/家具/撤销重做/存读） | ✅ |
| M2 | 家具目录扩展 + glTF 资源接入 | ⏳ |
| M3 | Three.js WebView 3D 场景（顶视/轨道/第一视角） | ⏳ |
| M4 | drift 持久化 + 工程列表 + 真机调优 | ⏳ |

## 本宿主构建注意（aarch64 + Oracle 7.0 kernel）

- Flutter 3.47.9 在 /home/ubuntu/flutter；bin/cache/dart-sdk 已换官方 linux-arm64 构建（x86-64 Dart VM 在 qemu 下 47-bit cage 静默失败）。
- **本宿主 Dart 3.13 语言坑（实测）**：
  - 顶层 `floor`/`ceil`/`round` 既不在 dart:core 也不在 dart:math —— 一律用 num 实例方法 `(x).floor()`；
  - `Canvas.drawColor(color, BlendMode.src)` 需 2 参，且是 `BlendMode`（BlendingMode 已不存在）；
  - `Map.removeWhere` 是 `bool test(K key, V value)` 双参；
  - `NavigationDestination.label` 是 String 不是 Widget。
- 本机 `flutter build apk` 可跑（aarch64 工具链 + shim 的 x86 工具）；CI 在 GitHub ubuntu-latest 出包（.github/workflows/android-apk.yml，push 触发，release tag `apk-<run>`）。
- 交付 APK 要**先打 zip** 再发（Feishu 直传 .apk 在用户手机上显示"安装包损坏"）。

## 包名/仓库

- 应用包名 `com.georgewu.jiajia`；GitHub `georgewu9/jiajia`（私有）。
- 与 LUM（georgewu9/LUM）同技术栈，独立仓库，代码不混。
