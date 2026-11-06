# General-mobile-application

面向 iOS / Android 的通用移动端应用（Flutter）。

## 仓库结构

| 路径 | 说明 |
| --- | --- |
| `native/com_host` | 子模块，指向 `com_host` 仓库的 `develop` 分支，提供底层通信能力（C 实现） |
| `tooling/` | 开发环境检查/安装脚本与版本锁 |
| `.tooling/` | 安装产物（git 忽略，卸载即删目录） |

## 开发环境（仓库内自包含）

不污染系统环境：Flutter、JDK、Android SDK/NDK 全部装在 `.tooling/` 下，
`PUB_CACHE` / `GRADLE_USER_HOME` / `ANDROID_USER_HOME` / `ANDROID_EMULATOR_HOME` 等
也一并重定向到仓库内。Windows 版 ADB 的授权密钥仍写入
`%USERPROFILE%\.android`，运行 ADB 的 Windows 用户需要能在此目录写入。

前置条件只有 **Python 3.9+** 与 **git**（脚本只依赖标准库）。

```bat
:: Windows
develop_env_install.bat check          :: 只检查
develop_env_install.bat install -y     :: 自动下载安装缺失项
develop_env_install.bat install --emulator :: 同时安装仓库内 Android 模拟器
develop_env_install.bat plan           :: 只打印下载地址/校验和
```

```bash
# macOS / Linux（zsh 或 bash）
./develop_env_install.sh check
./develop_env_install.sh install -y
./develop_env_install.sh plan
```

激活环境（仅影响当前终端）：

```powershell
. .\.tooling\env.ps1        # PowerShell
```

Windows 用户交互式运行 `install` 时可选择是否把 Android Emulator、Android 36
Google APIs x86_64 系统镜像和 `developer_app_api36` 虚拟设备安装到 `.tooling/`；
也可显式运行 `develop_env_install.bat install --emulator -y`。不选择模拟器时，
常规工具链安装不变。虚拟设备数据放在 `.tooling/cache/avd`，删除 `.tooling/` 即可卸载。

```bash
source .tooling/env.sh      # bash / zsh
```

版本锁在 [`tooling/versions.json`](tooling/versions.json)：Flutter `3.47.9`
（Dart 3.13.7）、Temurin JDK `21.0.13+9`、Android cmdline-tools `19.0`、
build-tools `36.0.0`、platform `android-36`、NDK `28.2.13676358`。
改版本后所有人执行一次 `install` 即可对齐；下载均做 sha256/sha1 校验。

> cmdline-tools 固定在 `19.0`：从 20 版起 `sdkmanager` 变成了转发到新 Android CLI
> 的空壳，在部分网络/代理环境下会直接报 “Failed to connect to remote repository”；
> `19.0` 仍带经典 Java 版 `sdkmanager`，能直接读取官方 repository XML。

说明：Windows 专属的 Visual Studio Build Tools 与 macOS 专属的 Xcode
**不在脚本范围内**，检查阶段只会标记为 INFO；iOS 构建仍需 macOS/CI。

### 几个实现细节

- **镜像**：默认 `--mirror cn`（`storage.flutter-io.cn` + `pub.flutter-io.cn`）；
  `pub.flutter-io.cn` 偶发限流时用 `--mirror global`（`pub.dev`，实测更稳）。
- **首次运行很慢**：Flutter SDK 3.47 的压缩包包含完整仓库，首次 `flutter`
  命令会 `pub upgrade` 并编译 `flutter_tools`（10~30 分钟，联网）；之后秒开。
  安装脚本会把这段输出直接透传到终端，别误以为卡死。
- **临时目录/配置目录**：`TEMP`/`TMP`/`TMPDIR` 以及（Windows 上的）`APPDATA`/`LOCALAPPDATA`
  在该开发终端内被重定向到 `.tooling/cache/`，避免污染用户目录，也绕开部分
  机器上 `%TEMP%`/`%APPDATA%` 不可写导致的 `pub upgrade` 失败。
- **长路径**：Windows 未开启 `LongPathsEnabled` 时，Flutter SDK 解压用系统自带
  `tar.exe`（支持 `\\?\` 长路径）；删除深层目录也做了长路径兼容。
- **模拟器目录**：选择安装模拟器后，系统镜像放在 `.tooling/android-sdk/system-images/`，
  虚拟设备及其数据放在 `.tooling/cache/avd/`；ADB 的授权密钥仍使用 Windows 用户目录下的
  `%USERPROFILE%\.android`。

## Windows 平台开发 Android

以下命令在仓库根目录的 PowerShell 中执行。每次打开新终端后，先激活仓库内工具链：

```powershell
. .\.tooling\env.ps1
```

### 获取依赖和构建

```powershell
flutter pub get
flutter analyze
flutter build apk --debug
```

`flutter run` 也会自动构建并部署 Debug 版本。Debug 构建适合开发和调试；APK
默认输出到 `build\app\outputs\flutter-apk\app-debug.apk`。

### 在 Android 模拟器运行和调试

安装工具链时选择安装模拟器（或执行 `.\develop_env_install.bat install --emulator -y`）后，
仓库会创建名为 `developer_app_api36` 的 AVD。启动模拟器并确认 Flutter 能发现它：

```powershell
emulator -avd developer_app_api36 -no-snapshot-load -no-metrics
# 另开一个已激活工具链的 PowerShell
adb devices
flutter devices
flutter run -d emulator-5554   # 设备 ID 以 flutter devices 的实际输出为准
```

首次冷启动可能需要一段时间。等待 `adb devices` 中模拟器状态变为 `device` 后再运行 Flutter；`offline` 表示 Android
尚未完成启动或 ADB 连接异常。也可直接运行 `flutter run`，让 Flutter 使用当前唯一的已连接设备。调试时保存 Dart
代码可触发热重载；终端按 `r` 手动热重载、按 `R` 热重启、按 `q` 结束运行。Android
Studio 或 VS Code 打开仓库后，也可选择该模拟器作为设备并启动调试。

### 使用 ADB 在 Android 实机运行和调试

在手机的开发者选项中启用 USB 调试，通过 USB 连接电脑；Windows 若未识别设备，需安装
对应厂商的 USB 驱动。手机出现 RSA 调试授权提示时选择允许，然后检查 ADB 连接：

```powershell
adb devices
flutter devices
flutter run -d <设备ID>
```

`adb devices` 中设备状态应为 `device`。如同时连接多个设备，使用 `-d <设备ID>` 指定目标。
运行期间可用 `flutter logs` 查看 Flutter 日志，也可用 `adb logcat` 查看 Android 系统日志；
结束调试可在 `flutter run` 终端按 `q`。

### 打包 APK

```powershell
flutter build apk --release
```

Release APK 输出到 `build\app\outputs\flutter-apk\app-release.apk`。当前 Android 工程
使用 Flutter 模板的 debug 签名配置，适合本地安装验证；分发或上架前应配置自己的 release
签名密钥。要按 CPU 架构分别生成较小的 APK，可运行：

```powershell
flutter build apk --release --split-per-abi
```

产物仍在 `build\app\outputs\flutter-apk\` 目录中。可通过 ADB 安装到已连接的实机或模拟器：

```powershell
adb install -r .\build\app\outputs\flutter-apk\app-release.apk
```

## 子模块

`com_host` 目前以**本机路径** `D:/underway/com_host` 临时挂载：

```bash
# 首次克隆本仓库后拉取子模块
git submodule update --init --recursive

# 跟随 develop 分支更新子模块
git submodule update --remote --merge native/com_host
```

待远端地址确定后，可改为 `https://gitee.com/Jay-MaYun_admin/com_host.git`：

```bash
git config -f .gitmodules submodule.native/com_host.url https://gitee.com/Jay-MaYun_admin/com_host.git
git submodule sync --recursive
```

## 当前状态

Flutter 工程已生成，包含 Android 和 iOS 平台目录；Windows/Linux/macOS/Web 目标不在本项目范围内。
