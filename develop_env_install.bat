@echo off
rem ===========================================================================
rem  develop_env_install.bat - Windows 入口
rem  只负责：找到 Python(>=3.9) -> 调用 tooling\dev_env.py
rem  所有检查/下载/安装逻辑都在 Python 里实现，macOS/Linux 共用同一份。
rem
rem  用法:
rem    develop_env_install.bat                检查环境（默认）
rem    develop_env_install.bat check          检查环境
rem    develop_env_install.bat install -y     自动安装缺失工具链
rem    develop_env_install.bat install --emulator  同时安装仓库内模拟器
rem    develop_env_install.bat plan           只打印下载地址与校验和
rem    develop_env_install.bat env            生成 .tooling\env.ps1 / env.sh
rem ===========================================================================
setlocal EnableExtensions
chcp 65001 >nul 2>&1

set "REPO_ROOT=%~dp0"
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"
set "PY_SCRIPT=%REPO_ROOT%\tooling\dev_env.py"

if not exist "%PY_SCRIPT%" (
    echo [ERROR] 找不到 %PY_SCRIPT%
    exit /b 1
)

call :find_python
if not defined PY_CMD goto :no_python

%PY_CMD% "%PY_SCRIPT%" %*
exit /b %ERRORLEVEL%

rem ---------------------------------------------------------------------------
:find_python
set "PY_CMD="
py -3 -c "import sys; raise SystemExit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if not errorlevel 1 (
    set "PY_CMD=py -3"
    exit /b 0
)
python -c "import sys; raise SystemExit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if not errorlevel 1 (
    set "PY_CMD=python"
    exit /b 0
)
python3 -c "import sys; raise SystemExit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if not errorlevel 1 (
    set "PY_CMD=python3"
    exit /b 0
)
exit /b 1

:no_python
echo.
echo [ERROR] 未找到 Python 3.9+，无法启动环境安装器。
echo         推荐安装方式（任选其一）:
echo           winget install -e --id Python.Python.3.12
echo           https://www.python.org/downloads/windows/
echo         安装时勾选 "Add python.exe to PATH"，然后重新运行本脚本。
exit /b 1
