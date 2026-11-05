#!/usr/bin/env sh
# ===========================================================================
#  develop_env_install.sh - macOS (zsh/bash) 与 Linux 入口
#  只负责：找到 Python3(>=3.9) -> 调用 tooling/dev_env.py
#  检查/下载/安装逻辑全部在 Python 里，与 Windows 共用同一份实现。
#
#  用法:
#    ./develop_env_install.sh                 检查环境（默认）
#    ./develop_env_install.sh check           检查环境
#    ./develop_env_install.sh install -y      自动安装缺失工具链
#    ./develop_env_install.sh plan            只打印下载地址与校验和
#    ./develop_env_install.sh env             生成 .tooling/env.sh / env.ps1
# ===========================================================================
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PY_SCRIPT="$SCRIPT_DIR/tooling/dev_env.py"

if [ ! -f "$PY_SCRIPT" ]; then
    echo "[ERROR] 找不到 $PY_SCRIPT" >&2
    exit 1
fi

find_python() {
    for candidate in python3 python python3.13 python3.12 python3.11 python3.10; do
        if command -v "$candidate" >/dev/null 2>&1; then
            if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info>=(3,9) else 1)' >/dev/null 2>&1; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

PY_BIN=$(find_python || true)
if [ -z "${PY_BIN:-}" ]; then
    echo "" >&2
    echo "[ERROR] 未找到 Python 3.9+，无法启动环境安装器。" >&2
    echo "        推荐安装方式（任选其一）:" >&2
    echo "          xcode-select --install                       # 自带 python3" >&2
    echo "          brew install python@3.13" >&2
    echo "          https://www.python.org/downloads/macos/" >&2
    exit 1
fi

exec "$PY_BIN" "$PY_SCRIPT" "$@"
