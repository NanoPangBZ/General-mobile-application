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
`PUB_CACHE` / `GRADLE_USER_HOME` / `ANDROID_USER_HOME` 等也一并重定向到仓库内。

前置条件只有 **Python 3.9+** 与 **git**（脚本只依赖标准库）。

```bat
:: Windows
develop_env_install.bat check          :: 只检查
develop_env_install.bat install -y     :: 自动下载安装缺失项
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
. .\tooling\env.ps1        # PowerShell
```

```bash
source tooling/env.sh      # bash / zsh
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
- **临时目录/配置目录**：`TEMP`/`TMP`/`TMPDIR` 以及（Windows 上的）`APPDATA`
  在该开发终端内被重定向到 `.tooling/cache/`，避免污染用户目录，也绕开部分
  机器上 `%TEMP%`/`%APPDATA%` 不可写导致的 `pub upgrade` 失败。
- **长路径**：Windows 未开启 `LongPathsEnabled` 时，Flutter SDK 解压用系统自带
  `tar.exe`（支持 `\\?\` 长路径）；删除深层目录也做了长路径兼容。
- **仍会写用户目录的**：`adb`/模拟器固定使用 `%USERPROFILE%\.android`，脚本不接管。

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

仅完成仓库初始化与子模块接入，尚未生成 Flutter 工程骨架（`lib/`、`android/`、`ios/` 等）。
后续在安装好 Flutter SDK 的环境下执行 `flutter create .` 即可补齐。
