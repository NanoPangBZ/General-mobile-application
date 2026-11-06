# 置顶规则

没有用户明确允许，禁止修改本 Markdown 文件（`AGENTS.md`）。

# 开发环境规则

- 本仓库的 Flutter、JDK、Android SDK/NDK 开发环境由仓库本地脚本管理，安装目录为仓库根目录下的 `.tooling/`。
- AI 助手不得扫描、搜索或使用系统中已安装的 Flutter、Dart、JDK、Android SDK/NDK，也不得从系统环境变量、PATH、常见安装目录或用户目录中寻找替代工具链。
- 需要检查或安装环境时，只能调用仓库根目录的 `develop_env_install.bat`（Windows）或 `develop_env_install.sh`（macOS/Linux）；底层实现为 `tooling/dev_env.py`，版本来源为 `tooling/versions.json`。
- 每次开始开发命令前，使用仓库本地生成的激活脚本：PowerShell 执行 `. .\\.tooling\\env.ps1`，bash/zsh 执行 `source .tooling/env.sh`。若脚本或工具链缺失，先用上述仓库脚本安装或生成，不得回退到系统环境。
- 运行命令时确认工作目录为本仓库根目录；不得通过 PATH 或系统目录中的工具绕过本地环境。
