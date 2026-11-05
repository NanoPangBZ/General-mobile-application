#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""仓库内自包含的 Flutter 移动端开发环境：环境检查 + 自动安装。

设计约束
--------
* 所有工具安装在 <repo>/.tooling 下，不写系统 PATH，不动 ~/.gradle、~/.android、
  ~/.pub-cache，删除该目录即完成卸载。
* 版本全部锁定在 tooling/versions.json，任何设备装出来的版本一致。
* 只安装移动端构建必需项：Flutter(Dart) / JDK / Android SDK + NDK。
  Windows 专属（VS Build Tools）与 macOS 专属（Xcode）不在本脚本范围内，
  脚本只提示、不安装。
* 只使用 CPython 标准库，要求 Python >= 3.9。

用法
----
    python tooling/dev_env.py check      # 只检查，不改动任何东西
    python tooling/dev_env.py install    # 检查 + 自动下载安装缺失项
    python tooling/dev_env.py env        # 只生成 .tooling/env.ps1 与 .tooling/env.sh
    python tooling/dev_env.py plan       # 解析并打印将要下载的 URL / 校验和

常用选项：--mirror cn|global  --force  --yes  --dry-run  --only flutter,jdk,android
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

MIN_PY = (3, 9)
IS_WINDOWS = os.name == "nt"
USER_AGENT = "general-mobile-application/dev-env (+python)"

HERE = Path(__file__).resolve().parent
MANIFEST_PATH = HERE / "versions.json"
REPO_ROOT = HERE.parent

TOOLING = REPO_ROOT / ".tooling"
FLUTTER_DIR = TOOLING / "flutter"
JDK_DIR = TOOLING / "jdk"
SDK_DIR = TOOLING / "android-sdk"
CACHE_DIR = TOOLING / "cache"
DOWNLOAD_DIR = CACHE_DIR / "downloads"
TMP_DIR = CACHE_DIR / "tmp"
STATE_PATH = TOOLING / "state.json"
ENV_SH = TOOLING / "env.sh"
ENV_PS1 = TOOLING / "env.ps1"

FLUTTER_STORAGE = "https://storage.googleapis.com"
GOOGLE_REPO = "https://dl.google.com/android/repository"
REPO_XML = GOOGLE_REPO + "/repository2-3.xml"
ADOPTIUM_API = "https://api.adoptium.net/v3"

DISK_REQUIRED_GB = 12

# --------------------------------------------------------------------------- #
# 终端输出
# --------------------------------------------------------------------------- #

_TTY = sys.stdout.isatty()


def _c(code: str, text: str) -> str:
    return "\033[%sm%s\033[0m" % (code, text) if _TTY else text


def say(text: str = "") -> None:
    print(text, flush=True)


def step(text: str) -> None:
    print(_c("36", "==> ") + text, flush=True)


def ok(text: str) -> None:
    print("  " + _c("32", "[ OK ] ") + text, flush=True)


def bad(text: str) -> None:
    print("  " + _c("31", "[FAIL] ") + text, flush=True)


def warn(text: str) -> None:
    print("  " + _c("33", "[WARN] ") + text, flush=True)


def note(text: str) -> None:
    print("  " + _c("90", "[ .. ] ") + text, flush=True)


def die(text: str, code: int = 1) -> "None":
    bad(text)
    sys.exit(code)


# --------------------------------------------------------------------------- #
# 平台与路径
# --------------------------------------------------------------------------- #


def host_os() -> str:
    return {
        "Windows": "windows",
        "Darwin": "macos",
        "Linux": "linux",
    }.get(platform.system(), platform.system().lower())


def host_arch() -> str:
    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        return "aarch64"
    return "x64"


def android_host() -> Tuple[str, Optional[str]]:
    """返回 Google SDK 仓库里的 host-os / host-arch。"""
    os_name = host_os()
    if os_name == "macos":
        return "macosx", host_arch()
    if os_name == "windows":
        return "windows", None
    return "linux", None


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def jdk_home() -> Path:
    """macOS 的 JDK 在 Contents/Home，其余平台就是解压根目录。"""
    mac_home = JDK_DIR / "Contents" / "Home"
    return mac_home if mac_home.is_dir() else JDK_DIR


def exe(name: str) -> str:
    return name + ".exe" if IS_WINDOWS else name


def tool_cmd(path: Path, *args: str) -> List[str]:
    """Windows 上 .bat/.cmd 必须经 cmd.exe 才能执行。"""
    if IS_WINDOWS and path.suffix.lower() in (".bat", ".cmd"):
        return [os.environ.get("COMSPEC", "cmd.exe"), "/c", str(path), *args]
    return [str(path), *args]


def sdkmanager_path(manifest: dict) -> Path:
    rev = str(manifest["android"]["cmdlineTools"]["revision"])
    base = SDK_DIR / "cmdline-tools" / rev / "bin" / "sdkmanager"
    if IS_WINDOWS:
        return Path(str(base) + ".bat")
    return base


def flutter_bin() -> Path:
    return FLUTTER_DIR / "bin" / ("flutter.bat" if IS_WINDOWS else "flutter")


# --------------------------------------------------------------------------- #
# 清单
# --------------------------------------------------------------------------- #


def load_manifest() -> dict:
    if not MANIFEST_PATH.is_file():
        die("缺少清单文件 %s" % rel(MANIFEST_PATH))
    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        die("清单文件解析失败：%s" % exc)
    for key in ("flutter", "jdk", "android", "mirrors"):
        if key not in manifest:
            die("清单文件缺少 '%s' 字段" % key)
    return manifest


def mirror_conf(manifest: dict, name: str) -> dict:
    mirrors = manifest.get("mirrors", {})
    if name not in mirrors:
        die("未知镜像 %r，可选：%s" % (name, ", ".join(mirrors)))
    return mirrors[name]


# --------------------------------------------------------------------------- #
# 网络
# --------------------------------------------------------------------------- #


def _open(url: str, timeout: int = 60, headers: Optional[dict] = None):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    return urllib.request.urlopen(req, timeout=timeout)


def http_json(url: str, timeout: int = 60):
    try:
        with _open(url, timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise RuntimeError("请求失败 HTTP %s：%s" % (exc.code, url)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError("网络不可达：%s（%s）" % (url, exc.reason)) from exc


def http_text(url: str, timeout: int = 120) -> str:
    try:
        with _open(url, timeout) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        raise RuntimeError("请求失败 HTTP %s：%s" % (exc.code, url)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError("网络不可达：%s（%s）" % (url, exc.reason)) from exc


def head_size(url: str) -> Optional[int]:
    """尽力获取远端文件大小，用于进度条与容量预估；失败不影响安装。"""
    try:
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=30) as resp:
            value = resp.headers.get("Content-Length")
            return int(value) if value else None
    except Exception:  # noqa: BLE001 - 仅用于展示
        return None


def file_hash(path: Path, algo: str) -> str:
    digest = hashlib.new(algo)
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fmt_mb(num: float) -> str:
    return "%.1f MB" % (num / 1024 / 1024)


class Downloader:
    """带断点续传、重试与校验的下载器。"""

    def __init__(self, retries: int = 3, verbose: bool = False) -> None:
        self.retries = retries
        self.verbose = verbose

    def fetch(
        self,
        url: str,
        dest: Path,
        sha256: Optional[str] = None,
        sha1: Optional[str] = None,
        size: Optional[int] = None,
        label: str = "",
    ) -> Path:
        dest.parent.mkdir(parents=True, exist_ok=True)
        part = dest.with_name(dest.name + ".part")
        label = label or dest.name

        if dest.is_file() and (sha256 or sha1):
            algo = "sha256" if sha256 else "sha1"
            expected = sha256 or sha1
            if file_hash(dest, algo).lower() == str(expected).lower():
                note("%s 已存在且校验通过，跳过下载" % label)
                return dest

        for attempt in range(1, self.retries + 1):
            try:
                self._download(url, part, size, label)
                break
            except Exception as exc:  # noqa: BLE001 - 网络错误种类多，统一重试
                if attempt >= self.retries:
                    raise RuntimeError("下载失败：%s（%s）" % (url, exc))
                warn("第 %d 次下载失败（%s），重试中…" % (attempt, exc))
                time.sleep(2 * attempt)

        if sha256:
            actual = file_hash(part, "sha256")
            if actual.lower() != sha256.lower():
                part.unlink(missing_ok=True)
                raise RuntimeError("sha256 校验失败（%s）：期望 %s，实际 %s" % (label, sha256, actual))
            note("%s 校验通过（sha256）" % label)
        elif sha1:
            actual = file_hash(part, "sha1")
            if actual.lower() != sha1.lower():
                part.unlink(missing_ok=True)
                raise RuntimeError("sha1 校验失败（%s）：期望 %s，实际 %s" % (label, sha1, actual))
            note("%s 校验通过（sha1）" % label)

        part.replace(dest)
        return dest

    def _download(self, url: str, part: Path, size: Optional[int], label: str) -> None:
        start = part.stat().st_size if part.exists() else 0
        headers = {"Range": "bytes=%d-" % start} if start else {}
        if start and size and start >= size:
            part.unlink()
            start = 0
            headers = {}

        started = time.time()
        try:
            resp = _open(url, 60, headers)
        except urllib.error.HTTPError as exc:
            if exc.code == 416 and part.exists():  # 已经下完
                return
            raise

        with resp:
            if start and resp.status != 206:  # 服务器不支持续传
                start = 0
            total = int(resp.headers.get("Content-Length") or 0) + start
            total = total or (size or 0)
            done = start
            mode = "ab" if start else "wb"
            with part.open(mode) as fh:
                while True:
                    chunk = resp.read(256 * 1024)
                    if not chunk:
                        break
                    fh.write(chunk)
                    done += len(chunk)
                    self._progress(label, done, total, started)

            if total and done < total:
                raise IOError("连接提前中断（%s / %s）" % (_fmt_mb(done), _fmt_mb(total)))
        if _TTY:
            sys.stdout.write("\n")
            sys.stdout.flush()

    def _progress(self, label: str, done: int, total: int, started: float) -> None:
        if not _TTY:
            return
        elapsed = max(time.time() - started, 0.001)
        speed = done / elapsed / 1024 / 1024
        pct = (done / total * 100) if total else 0.0
        text = "  %-34s %6.1f%%  %s / %s  %5.1f MB/s" % (
            label[:34],
            pct,
            _fmt_mb(done),
            _fmt_mb(total) if total else "?",
            speed,
        )
        sys.stdout.write("\r" + text)
        sys.stdout.flush()


# --------------------------------------------------------------------------- #
# 下载项解析（版本来自清单，URL/校验和来自官方元数据）
# --------------------------------------------------------------------------- #


def resolve_flutter(manifest: dict, mirror: str) -> dict:
    conf = mirror_conf(manifest, mirror)
    base = conf["flutterStorage"].rstrip("/")
    os_name = host_os()
    arch = host_arch()
    index_url = "%s/flutter_infra_release/releases/releases_%s.json" % (base, os_name)
    data = http_json(index_url)

    version = str(manifest["flutter"]["version"])
    channel = manifest["flutter"].get("channel", "stable")
    expected_arch = "arm64" if arch == "aarch64" else None

    candidates = [
        item
        for item in data.get("releases", [])
        if item.get("version") == version and item.get("channel") == channel
    ]
    if expected_arch:
        candidates = [c for c in candidates if expected_arch in c["archive"]]
    else:
        candidates = [c for c in candidates if "arm64" not in c["archive"]]
    if not candidates:
        raise RuntimeError(
            "在 %s 中找不到 Flutter %s（%s/%s）" % (index_url, version, os_name, arch)
        )

    release = candidates[0]
    archive = release["archive"].lstrip("/")
    url = "%s/flutter_infra_release/releases/%s" % (base, archive)
    return {
        "version": version,
        "name": Path(archive).name,
        "url": url,
        "sha256": release["sha256"],
        "size": head_size(url),
        "dart": release.get("dart_sdk_version", ""),
    }


def resolve_jdk(manifest: dict, _mirror: str) -> dict:
    jdk = manifest["jdk"]
    version = str(jdk["version"])
    overrides = jdk.get("overrides", {})
    key = "%s-%s" % (host_os(), host_arch())
    if key in overrides:
        item = overrides[key]
        name = item["url"].rstrip("/").rsplit("/", 1)[-1].split("?")[0]
        return {
            "version": version,
            "name": name,
            "url": item["url"],
            "sha256": item.get("sha256"),
            "size": item.get("size"),
        }

    api_os = {"windows": "windows", "macos": "mac", "linux": "linux"}[host_os()]
    url = "%s/assets/feature_releases/%s/ga?architecture=%s&image_type=jdk&os=%s&vendor=%s&page_size=50&sort_order=DESC" % (
        ADOPTIUM_API,
        jdk["feature"],
        host_arch(),
        api_os,
        jdk.get("vendor", "eclipse"),
    )
    releases = http_json(url)
    for release in releases:
        if release.get("version_data", {}).get("semver") != version:
            continue
        for binary in release.get("binaries", []):
            if binary.get("image_type") != "jdk":
                continue
            package = binary["package"]
            return {
                "version": version,
                "name": package["name"],
                "url": package["link"],
                "sha256": package.get("checksum"),
                "size": package.get("size"),
            }
    raise RuntimeError(
        "Adoptium 上找不到 JDK %s（%s/%s），可在 versions.json 的 jdk.overrides 里写死 URL"
        % (version, host_os(), host_arch())
    )


def _localname(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def resolve_cmdline_tools(manifest: dict, _mirror: str) -> dict:
    revision = str(manifest["android"]["cmdlineTools"]["revision"])
    want_os, want_arch = android_host()
    xml_text = http_text(REPO_XML)

    package = None
    for element in ET.fromstring(xml_text).iter():
        if _localname(element.tag) == "remotePackage" and element.get("path") == "cmdline-tools;%s" % revision:
            package = element
            break
    if package is None:
        raise RuntimeError("Android 仓库中找不到 cmdline-tools;%s" % revision)

    for archive in package.iter():
        if _localname(archive.tag) != "archive":
            continue
        item: Dict[str, object] = {"sha1": None, "size": None, "url": None, "host_arch": None}
        for child in archive.iter():
            name = _localname(child.tag)
            text = (child.text or "").strip()
            if name == "host-os":
                item["host_os"] = text
            elif name == "host-arch":
                item["host_arch"] = text
            elif name == "url":
                item["url"] = text
            elif name == "checksum":
                item["sha1"] = text
            elif name == "size":
                item["size"] = int(text or 0)
        if item.get("host_os") != want_os:
            continue
        if want_arch and item.get("host_arch") not in (None, want_arch):
            continue
        if not item.get("url"):
            continue
        return {
            "version": revision,
            "name": str(item["url"]).rsplit("/", 1)[-1],
            "url": "%s/%s" % (GOOGLE_REPO, item["url"]),
            "sha1": item["sha1"],
            "size": item["size"],
        }
    raise RuntimeError("cmdline-tools;%s 没有适配 %s/%s 的包" % (revision, want_os, want_arch))


RESOLVERS = {
    "flutter": resolve_flutter,
    "jdk": resolve_jdk,
    "android": resolve_cmdline_tools,
}


# --------------------------------------------------------------------------- #
# 解压
# --------------------------------------------------------------------------- #


def _wlong(path: Path) -> str:
    """Windows 上超过 260 字符的路径需要 \\\\?\\ 前缀。"""
    text = str(path.resolve())
    if text.startswith("\\\\?\\"):
        return text
    return "\\\\?\\" + text


def rmtree_any(path: Path) -> None:
    """删除目录，Windows 上兼容超过 MAX_PATH 的深层目录树。"""
    if not path.exists():
        return
    if IS_WINDOWS:
        try:
            shutil.rmtree(_wlong(path))
            return
        except OSError:
            pass
        subprocess.run(
            [os.environ.get("COMSPEC", "cmd.exe"), "/c", "rmdir", "/s", "/q", str(path)],
            capture_output=True,
        )
        return
    shutil.rmtree(path, ignore_errors=True)


def _bsdtar() -> Optional[str]:
    """bsdtar 支持 zip，且能处理长路径与符号链接，比纯 Python 解压更可靠。

    Windows 用自带 System32/tar.exe；macOS 的 /usr/bin/tar 也是 bsdtar；
    Linux 的 GNU tar 不认 zip，返回 None，走 Python 实现。
    """
    if not IS_WINDOWS:
        return shutil.which("tar") if host_os() == "macos" else None
    system_tar = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32" / "tar.exe"
    if system_tar.is_file():
        return str(system_tar)
    return shutil.which("tar")


def _extract_with_tar(archive: Path, dest: Path) -> bool:
    tar = _bsdtar()
    if not tar:
        return False
    try:
        proc = subprocess.run(
            [tar, "-xf", str(archive), "-C", str(dest)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=3600,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if proc.returncode != 0 and proc.stderr:
        warn("tar 解压失败，回退到 Python：%s" % proc.stderr.strip()[:300])
    return proc.returncode == 0


def _extract_zip_python(archive: Path, dest: Path) -> None:
    """纯 Python 解压；Windows 上逐条目写入 \\\\?\\ 路径以绕过 MAX_PATH。"""
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            target = dest / info.filename
            if info.is_dir():
                Path(_wlong(target) if IS_WINDOWS else target).mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            raw = _wlong(target) if IS_WINDOWS else str(target)
            with zf.open(info) as src, open(raw, "wb") as out:
                shutil.copyfileobj(src, out)


def extract(archive: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    used_tar = _bsdtar() is not None and _extract_with_tar(archive, dest)
    if not used_tar:
        if archive.name.lower().endswith(".zip"):
            _extract_zip_python(archive, dest)
        else:
            with tarfile.open(archive) as tf:
                try:
                    tf.extractall(dest, filter="data")
                except TypeError:  # Python < 3.12 没有 filter 参数
                    tf.extractall(dest)

    if not IS_WINDOWS:
        for path in dest.rglob("*"):
            if path.is_file() and path.parent.name == "bin":
                path.chmod(path.stat().st_mode | 0o755)


def top_dir(dest: Path) -> Path:
    entries = [entry for entry in dest.iterdir() if not entry.name.startswith(".")]
    return entries[0] if len(entries) == 1 else dest


def fresh_tmp(name: str) -> Path:
    target = TMP_DIR / name
    rmtree_any(target)
    target.mkdir(parents=True, exist_ok=True)
    return target


def _replace_dir(src: Path, dest: Path) -> None:
    rmtree_any(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dest))


# --------------------------------------------------------------------------- #
# 环境变量
# --------------------------------------------------------------------------- #


def env_map(manifest: dict, mirror: str) -> Dict[str, Optional[str]]:
    conf = mirror_conf(manifest, mirror)
    packages = manifest["android"].get("packages", [])
    ndk = next((p.split(";", 1)[1] for p in packages if p.startswith("ndk;")), None)
    rev = str(manifest["android"]["cmdlineTools"]["revision"])

    env: Dict[str, Optional[str]] = {
        "FLUTTER_ROOT": str(FLUTTER_DIR),
        "JAVA_HOME": str(jdk_home()),
        "ANDROID_HOME": str(SDK_DIR),
        "ANDROID_SDK_ROOT": str(SDK_DIR),
        "ANDROID_USER_HOME": str(CACHE_DIR / "android"),
        "ANDROID_AVD_HOME": str(CACHE_DIR / "avd"),
        "ANDROID_NDK_HOME": str(SDK_DIR / "ndk" / ndk) if ndk else None,
        "PUB_CACHE": str(CACHE_DIR / "pub"),
        "GRADLE_USER_HOME": str(CACHE_DIR / "gradle"),
        # dart 的 pub 需要可写的临时目录；部分机器上 %TEMP% 权限异常，这里统一收敛到仓库内
        "TEMP": str(CACHE_DIR / "tmp"),
        "TMP": str(CACHE_DIR / "tmp"),
        "TMPDIR": str(CACHE_DIR / "tmp"),
        "KONAN_DATA_DIR": str(CACHE_DIR / "konan"),
        "PUB_HOSTED_URL": conf.get("pubHosted"),
        "FLUTTER_STORAGE_BASE_URL": conf.get("flutterStorage"),
    }
    if IS_WINDOWS:
        # flutter_tools 会把 .flutter_tool_state / .flutter_settings 写到 %APPDATA%，
        # 部分机器上该目录不可写，这里一并收敛进仓库
        env["APPDATA"] = str(CACHE_DIR / "appdata")
    return env


def path_entries(manifest: dict) -> List[str]:
    rev = str(manifest["android"]["cmdlineTools"]["revision"])
    return [
        str(FLUTTER_DIR / "bin"),
        str(jdk_home() / "bin"),
        str(SDK_DIR / "cmdline-tools" / rev / "bin"),
        str(SDK_DIR / "platform-tools"),
    ]


def process_env(manifest: dict, mirror: str) -> dict:
    env = os.environ.copy()
    for key, value in env_map(manifest, mirror).items():
        if value:
            env[key] = value
    env["PATH"] = os.pathsep.join(path_entries(manifest) + [env.get("PATH", "")])
    return env


def write_env_scripts(manifest: dict, mirror: str) -> None:
    env = env_map(manifest, mirror)
    lines_ps1 = [
        "# 由 tooling/dev_env.py 生成，请勿手工编辑。用法： . .\\tooling\\env.ps1",
        "$_repo = Split-Path -Parent $PSScriptRoot",
        "$_tool = Join-Path $_repo '.tooling'",
        "",
    ]
    for key, value in env.items():
        if not value:
            continue
        if key in ("PUB_HOSTED_URL", "FLUTTER_STORAGE_BASE_URL"):
            lines_ps1.append('$env:%s = "%s"' % (key, value))
        else:
            suffix = value[len(str(TOOLING)) :].replace("\\", "/") if value.startswith(str(TOOLING)) else None
            if suffix is not None:
                lines_ps1.append('$env:%s = Join-Path $_tool "%s"' % (key, suffix.strip("/")))
            else:
                lines_ps1.append('$env:%s = "%s"' % (key, value))
    lines_ps1 += [
        "",
        "$_paths = @(",
        '  (Join-Path $_tool "flutter/bin"),',
        '  (Join-Path $_tool "jdk/bin"),',
        '  (Join-Path $_tool "android-sdk/cmdline-tools/%s/bin"),'
        % str(manifest["android"]["cmdlineTools"]["revision"]),
        '  (Join-Path $_tool "android-sdk/platform-tools")',
        ")",
        '$env:PATH = ($_paths -join ";") + ";" + $env:PATH',
        'Write-Host "dev env ready: $_tool"',
        "",
    ]
    ENV_PS1.write_text("\r\n".join(lines_ps1), encoding="utf-8")

    sh = [
        "# 由 tooling/dev_env.py 生成，请勿手工编辑。用法： source tooling/env.sh",
        '_dev_env_repo="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"',
        '_dev_env_tool="$_dev_env_repo/.tooling"',
        "",
    ]
    for key, value in env.items():
        if not value:
            continue
        if key in ("PUB_HOSTED_URL", "FLUTTER_STORAGE_BASE_URL"):
            sh.append('export %s="%s"' % (key, value))
        elif value.startswith(str(TOOLING)):
            suffix = value[len(str(TOOLING)) :].replace("\\", "/").strip("/")
            sh.append('export %s="$_dev_env_tool/%s"' % (key, suffix))
        else:
            sh.append('export %s="%s"' % (key, value))
    revision = str(manifest["android"]["cmdlineTools"]["revision"])
    sh += [
        "",
        'export PATH="$_dev_env_tool/flutter/bin:'
        '$_dev_env_tool/jdk/bin:'
        '$_dev_env_tool/android-sdk/cmdline-tools/%s/bin:'
        '$_dev_env_tool/android-sdk/platform-tools:$PATH"' % revision,
        "unset _dev_env_repo _dev_env_tool",
        "",
    ]
    ENV_SH.write_text("\n".join(sh), encoding="utf-8")
    ENV_SH.chmod(0o755)


def save_state(manifest: dict) -> None:
    state = {
        "updated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "platform": "%s-%s" % (host_os(), host_arch()),
        "flutter": manifest["flutter"]["version"],
        "jdk": manifest["jdk"]["version"],
        "android": manifest["android"]["packages"],
    }
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")


# --------------------------------------------------------------------------- #
# 检查
# --------------------------------------------------------------------------- #

STATUS_OK, STATUS_FAIL, STATUS_WARN, STATUS_INFO = "OK", "FAIL", "WARN", "INFO"


FLUTTER_MARKER = FLUTTER_DIR / ".dev-env-version"


def _flutter_version_cheap() -> Optional[str]:
    """优先读安装标记/版本文件，避免每次都启动 flutter（首次启动会下载产物）。"""
    if not FLUTTER_DIR.is_dir():
        return None
    for candidate in (FLUTTER_MARKER, FLUTTER_DIR / "version"):
        if candidate.is_file():
            text = candidate.read_text(encoding="utf-8", errors="replace").strip()
            if text:
                return text.split()[0]
    version_json = FLUTTER_DIR / "bin" / "cache" / "flutter.version.json"
    if version_json.is_file():
        try:
            return json.loads(version_json.read_text(encoding="utf-8")).get("frameworkVersion")
        except (json.JSONDecodeError, OSError):
            return None
    return None


def _flutter_version(_env: Optional[dict] = None) -> Optional[str]:
    """只读缓存里的版本信息，不启动 flutter —— 首次启动会编译 flutter_tools，耗时很长。"""
    return _flutter_version_cheap()


def _jdk_version() -> Optional[str]:
    release = jdk_home() / "release"
    if not release.is_file():
        return None
    match = re.search(r'JAVA_VERSION="([^"]+)"', release.read_text(encoding="utf-8", errors="replace"))
    return match.group(1) if match else None


def collect_checks(manifest: dict, mirror: str) -> List[Tuple[str, str, str]]:
    rows: List[Tuple[str, str, str]] = []
    env = process_env(manifest, mirror)

    py = "%d.%d.%d" % sys.version_info[:3]
    rows.append(("python", STATUS_OK if sys.version_info[:2] >= MIN_PY else STATUS_FAIL,
                 "%s (需要 >= %d.%d)" % (py, *MIN_PY)))

    git = shutil.which("git")
    if git:
        try:
            out = subprocess.run([git, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            out = git
        rows.append(("git", STATUS_OK, out))
    else:
        rows.append(("git", STATUS_FAIL, "未找到 git（Flutter 依赖它）"))

    rows.append(("host", STATUS_INFO, "%s-%s, .tooling -> %s" % (host_os(), host_arch(), rel(TOOLING))))

    want_flutter = str(manifest["flutter"]["version"])
    actual_flutter = _flutter_version(env)
    if not flutter_bin().is_file():
        rows.append(("flutter", STATUS_FAIL, "未安装（期望 %s）" % want_flutter))
    elif actual_flutter is None:
        rows.append(("flutter", STATUS_WARN, "目录存在但未初始化，运行 install 完成首次启动"))
    elif actual_flutter != want_flutter:
        rows.append(("flutter", STATUS_FAIL, "版本 %s，清单要求 %s" % (actual_flutter, want_flutter)))
    else:
        rows.append(("dart/flutter", STATUS_OK, "flutter %s (dart %s)" % (
            actual_flutter, manifest["flutter"].get("dart", "") or "?")))

    want_jdk = str(manifest["jdk"]["version"])
    actual_jdk = _jdk_version()
    if not jdk_home().is_dir():
        rows.append(("jdk", STATUS_FAIL, "未安装（期望 %s）" % want_jdk))
    elif actual_jdk is None:
        rows.append(("jdk", STATUS_FAIL, "缺少 release 文件，安装可能损坏"))
    else:
        expected_major = want_jdk.split(".")[1] if "." in want_jdk else want_jdk
        status = STATUS_OK if actual_jdk.split(".")[1] == expected_major else STATUS_FAIL
        rows.append(("jdk", status, actual_jdk))

    sdkmanager = sdkmanager_path(manifest)
    rows.append(("cmdline-tools", STATUS_OK if sdkmanager.is_file() else STATUS_FAIL,
                 sdkmanager.name if sdkmanager.is_file() else "未安装"))

    for package in manifest["android"].get("packages", []):
        present = android_package_present(package)
        rows.append((package, STATUS_OK if present else STATUS_FAIL,
                     "已安装" if present else "未安装"))

    license_dirs = [CACHE_DIR / "android" / "licenses", SDK_DIR / "licenses"]
    license_dir = next(
        (d for d in license_dirs if d.is_dir() and any(d.iterdir())), None
    )
    rows.append(("android licenses", STATUS_OK if license_dir else STATUS_FAIL,
                 ("已接受（%s）" % rel(license_dir)) if license_dir else "未接受（install 会自动接受）"))

    rows.append(("env scripts", STATUS_OK if ENV_SH.is_file() and ENV_PS1.is_file() else STATUS_WARN,
                 "tooling 已生成" if ENV_SH.is_file() and ENV_PS1.is_file() else "未生成，运行 env"))

    rows.append(("VS Build Tools", STATUS_INFO, "跳过：Windows 桌面构建不在本脚本范围"))
    rows.append(("Xcode", STATUS_INFO, "跳过：iOS 构建需要 macOS，本脚本不处理"))
    return rows


def print_report(rows: List[Tuple[str, str, str]], manifest: dict, mirror: str) -> bool:
    width = max(len(name) for name, _, _ in rows)
    for name, status, detail in rows:
        tag = {
            STATUS_OK: _c("32", "[ OK ]"),
            STATUS_FAIL: _c("31", "[FAIL]"),
            STATUS_WARN: _c("33", "[WARN]"),
            STATUS_INFO: _c("90", "[INFO]"),
        }[status]
        say("%s %-*s  %s" % (tag, width, name, detail))

    failures = [row for row in rows if row[1] == STATUS_FAIL]
    say("")
    if failures:
        say(_c("31", "环境不完整：%d 项缺失/不匹配。" % len(failures)))
        say("运行  python tooling/dev_env.py install  自动补全（镜像：%s）。" % mirror)
        return False
    say(_c("32", "环境检查通过。") + " 激活方式：")
    say("  PowerShell : . .\\tooling\\env.ps1")
    say("  bash/zsh   : source tooling/env.sh")
    return True


# --------------------------------------------------------------------------- #
# 安装
# --------------------------------------------------------------------------- #


def _ensure_dirs() -> None:
    for path in (TOOLING, CACHE_DIR, DOWNLOAD_DIR, TMP_DIR, CACHE_DIR / "appdata", CACHE_DIR / "gradle", CACHE_DIR / "pub"):
        path.mkdir(parents=True, exist_ok=True)


def _long_paths_enabled() -> bool:
    try:
        import winreg

        with winreg.OpenKey(
            winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\FileSystem"
        ) as key:
            value, _ = winreg.QueryValueEx(key, "LongPathsEnabled")
        return bool(value)
    except OSError:
        return False


def preflight(manifest: dict) -> None:
    step("预检")
    if sys.version_info[:2] < MIN_PY:
        die("需要 Python >= %d.%d，当前 %s" % (*MIN_PY, platform.python_version()))
    ok("Python %s" % platform.python_version())

    if not shutil.which("git"):
        die("未找到 git：Flutter 依赖 git，请先安装（Windows: winget install Git.Git）")
    ok("git %s" % subprocess.run(
        ["git", "--version"], capture_output=True, text=True, timeout=30
    ).stdout.strip())

    free_gb = shutil.disk_usage(REPO_ROOT).free / 1024 ** 3
    if free_gb < DISK_REQUIRED_GB:
        warn("磁盘剩余 %.1f GB，建议至少 %d GB" % (free_gb, DISK_REQUIRED_GB))
    else:
        ok("磁盘剩余 %.1f GB" % free_gb)

    if IS_WINDOWS and not _long_paths_enabled():
        warn("Windows 长路径未启用：Flutter SDK 内含超长路径，已用 tar 解压规避；"
             "若后续 flutter/git 命令报路径错误，请启用 LongPathsEnabled 或把仓库放到更短路径下")

    if IS_WINDOWS:
        probe = (
            REPO_ROOT / ".tooling" / "android-sdk" / "ndk" / "28.2.13676358"
            / "toolchains" / "llvm" / "prebuilt" / "windows-x86_64" / "bin" / "clang.exe"
        )
        if len(str(probe)) > 250:
            warn("工具链路径较深，可能触及 Windows 260 字符限制；建议开启长路径支持或以短盘符映射")


def install_flutter(manifest: dict, mirror: str, dl: Downloader) -> None:
    info = resolve_flutter(manifest, mirror)
    step("安装 Flutter %s（%s）" % (info["version"], info["name"]))
    archive = DOWNLOAD_DIR / info["name"]
    dl.fetch(info["url"], archive, sha256=info["sha256"], size=info["size"], label=info["name"])

    tmp = fresh_tmp("flutter")
    extract(archive, tmp)
    _replace_dir(top_dir(tmp), FLUTTER_DIR)
    FLUTTER_MARKER.write_text(str(info["version"]) + "\n", encoding="utf-8")
    ok("Flutter -> %s" % rel(FLUTTER_DIR))


def install_jdk(manifest: dict, mirror: str, dl: Downloader) -> None:
    info = resolve_jdk(manifest, mirror)
    step("安装 JDK %s（%s）" % (info["version"], info["name"]))
    archive = DOWNLOAD_DIR / info["name"]
    dl.fetch(info["url"], archive, sha256=info["sha256"], size=info["size"], label=info["name"])

    tmp = fresh_tmp("jdk")
    extract(archive, tmp)
    _replace_dir(top_dir(tmp), JDK_DIR)
    ok("JDK -> %s（JAVA_HOME=%s）" % (rel(JDK_DIR), rel(jdk_home())))


def install_cmdline_tools(manifest: dict, mirror: str, dl: Downloader) -> None:
    info = resolve_cmdline_tools(manifest, mirror)
    revision = str(manifest["android"]["cmdlineTools"]["revision"])
    step("安装 Android cmdline-tools %s（%s）" % (revision, info["name"]))
    archive = DOWNLOAD_DIR / info["name"]
    dl.fetch(info["url"], archive, sha1=info["sha1"], size=info["size"], label=info["name"])

    tmp = fresh_tmp("cmdline-tools")
    extract(archive, tmp)
    target = SDK_DIR / "cmdline-tools" / revision
    rmtree_any(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(top_dir(tmp)), str(target))
    # 清掉其它版本的 cmdline-tools，避免 sdkmanager 解析到废弃版本
    for sibling in list(target.parent.iterdir()):
        if sibling.name != revision:
            rmtree_any(sibling)
    if not IS_WINDOWS:
        for path in (target / "bin").glob("*"):
            path.chmod(path.stat().st_mode | 0o755)
    ok("cmdline-tools -> %s" % rel(target))


def _run_streamed(
    cmd: List[str], env: dict, verbose: bool, timeout: int = 3600, stdin_text: Optional[str] = None
) -> subprocess.CompletedProcess:
    if verbose:
        return subprocess.run(cmd, env=env, timeout=timeout, input=stdin_text, text=True)
    return subprocess.run(
        cmd,
        env=env,
        input=stdin_text,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def android_package_present(package: str) -> bool:
    kind, _, spec = package.partition(";")
    if kind == "platform-tools":
        return (SDK_DIR / "platform-tools" / exe("adb")).is_file()
    if kind == "build-tools":
        return (SDK_DIR / "build-tools" / spec / "source.properties").is_file()
    if kind == "platforms":
        return (SDK_DIR / "platforms" / spec / "android.jar").is_file()
    if kind == "ndk":
        return (SDK_DIR / "ndk" / spec / "source.properties").is_file()
    return True


def install_android_packages(manifest: dict, mirror: str, verbose: bool) -> None:
    sdkmanager = sdkmanager_path(manifest)
    if not sdkmanager.is_file():
        die("sdkmanager 不存在，请先安装 cmdline-tools")
    env = process_env(manifest, mirror)
    packages = list(manifest["android"].get("packages", []))
    missing = [p for p in packages if not android_package_present(p)]
    if not missing:
        note("Android SDK 组件均已安装：%s" % ", ".join(packages))
        return

    step("安装 Android SDK 组件：%s" % ", ".join(missing))
    cmd = tool_cmd(sdkmanager, "--sdk_root=%s" % SDK_DIR, *missing)
    last_output = ""
    for attempt in (1, 2):
        # sdkmanager 的许可提问走 stdin，一次性喂 y，避免无人值守时挂起
        proc = _run_streamed(cmd, env, verbose, stdin_text="y\n" * 40)
        if proc.returncode == 0:
            ok("Android SDK 组件就绪")
            return
        last_output = (proc.stdout or "") + (proc.stderr or "" if isinstance(proc.stderr, str) else "")
        still = [p for p in missing if not android_package_present(p)]
        if not still:
            warn("sdkmanager 返回非 0，但所需组件已就位（多为仓库元数据拉取抖动）")
            return
        if attempt == 1:
            warn("sdkmanager 失败，重试一次…")
    die("sdkmanager 执行失败：\n%s" % last_output.strip()[-2000:])


def accept_licenses(manifest: dict, mirror: str) -> None:
    sdkmanager = sdkmanager_path(manifest)
    if not sdkmanager.is_file():
        return
    step("接受 Android SDK 许可协议")
    env = process_env(manifest, mirror)
    cmd = tool_cmd(sdkmanager, "--sdk_root=%s" % SDK_DIR, "--licenses")
    try:
        subprocess.run(
            cmd, env=env, input="y\n" * 60, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=600,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        warn("接受许可时出错：%s" % exc)
    for candidate in (SDK_DIR / "licenses", CACHE_DIR / "android" / "licenses"):
        if candidate.is_dir() and any(candidate.iterdir()):
            ok("许可已写入 %s" % rel(candidate))
            return
    warn("未检测到许可文件，Android 构建可能被拒绝；可手工执行 sdkmanager --licenses")


def bootstrap_flutter(manifest: dict, mirror: str) -> None:
    binary = flutter_bin()
    if not binary.is_file():
        return
    step("首次启动 Flutter（会下载 Dart SDK / 引擎产物并编译 flutter_tools，可能耗时 10~30 分钟）")
    note("这一步只在首次安装/升级 Flutter 版本后发生，后续都是秒开")
    env = process_env(manifest, mirror)
    try:
        # 直接继承终端输出，让 pub get / 编译进度可见（超时 1 小时）
        proc = subprocess.run(tool_cmd(binary, "--version"), env=env, timeout=3600)
        if proc.returncode != 0:
            warn("flutter --version 返回 %d，可稍后手工执行 flutter --version 观察" % proc.returncode)
            return
        subprocess.run(
            tool_cmd(binary, "config", "--no-analytics"), env=env, capture_output=True, timeout=120
        )
        ok("Flutter 缓存就绪")
    except (OSError, subprocess.TimeoutExpired) as exc:
        warn("初始化 Flutter 失败：%s（可稍后手工执行 flutter --version）" % exc)


def cmd_install(manifest: dict, mirror: str, args) -> int:
    preflight(manifest)
    _ensure_dirs()
    dl = Downloader(verbose=args.verbose)
    only = {part.strip() for part in args.only.split(",") if part.strip()} or {"flutter", "jdk", "android"}

    todo = []
    want_flutter = str(manifest["flutter"]["version"])
    installed_flutter = _flutter_version_cheap()
    need_flutter = (
        args.force
        or not flutter_bin().is_file()
        or (installed_flutter is not None and installed_flutter != want_flutter)
    )
    if "flutter" in only and need_flutter:
        todo.append(("flutter", install_flutter))
    want_jdk = str(manifest["jdk"]["version"])
    want_jdk_major = want_jdk.split(".")[1] if "." in want_jdk else want_jdk
    actual_jdk = _jdk_version()
    actual_jdk_major = actual_jdk.split(".")[1] if actual_jdk and "." in actual_jdk else actual_jdk
    if "jdk" in only and (args.force or actual_jdk_major != want_jdk_major):
        todo.append(("jdk", install_jdk))
    if "android" in only and (args.force or not sdkmanager_path(manifest).is_file()):
        todo.append(("android", install_cmdline_tools))

    if args.dry_run:
        step("演练模式：仅解析下载项")
        for name in ("flutter", "jdk", "android"):
            if name not in only:
                continue
            info = RESOLVERS[name](manifest, mirror)
            say("  %-8s %s" % (name, info["url"]))
            say("  %-8s 校验和 %s" % ("", info.get("sha256") or info.get("sha1") or "（无）"))
        return 0

    if not todo and not args.force:
        note("Flutter / JDK / cmdline-tools 均已就绪，跳过下载，仅校验 Android 组件与许可")
    for name, func in todo:
        func(manifest, mirror, dl)

    if "android" in only:
        accept_licenses(manifest, mirror)
        install_android_packages(manifest, mirror, args.verbose)
    if "flutter" in only:
        bootstrap_flutter(manifest, mirror)
    write_env_scripts(manifest, mirror)
    save_state(manifest)

    say("")
    ok("安装完成，激活环境：")
    say("  PowerShell : . .\\tooling\\env.ps1")
    say("  bash/zsh   : source tooling/env.sh")
    return 0 if cmd_check(manifest, mirror) else 1


def cmd_plan(manifest: dict, mirror: str) -> int:
    step("解析下载项（镜像：%s，平台：%s-%s）" % (mirror, host_os(), host_arch()))
    total = 0
    for name in ("flutter", "jdk", "android"):
        info = RESOLVERS[name](manifest, mirror)
        size = info.get("size") or 0
        total += size
        say("  %-8s %s" % (name, info["url"]))
        say("  %-8s 版本 %s  大小 %s  校验 %s" % (
            "", info.get("version", ""),
            _fmt_mb(size) if size else "（未知）",
            (info.get("sha256") or info.get("sha1") or "无")[:16] + "…",
        ))
    say("")
    say("  预计下载 %s，解压后约 8~10 GB。" % (_fmt_mb(total) if total else "（未知）"))
    say("  Android SDK 组件：%s" % ", ".join(manifest["android"]["packages"]))
    return 0


def cmd_check(manifest: dict, mirror: str) -> bool:
    rows = collect_checks(manifest, mirror)
    return print_report(rows, manifest, mirror)


def cmd_env(manifest: dict, mirror: str) -> int:
    _ensure_dirs()
    write_env_scripts(manifest, mirror)
    ok("已生成 %s 与 %s" % (rel(ENV_PS1), rel(ENV_SH)))
    return 0


# --------------------------------------------------------------------------- #
# 入口
# --------------------------------------------------------------------------- #


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="dev_env.py",
        description="仓库内自包含的 Flutter 移动端开发环境（检查 / 安装）",
    )
    sub = parser.add_subparsers(dest="command")

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--mirror", choices=["cn", "global"], default="cn", help="下载镜像（默认 cn）")
        p.add_argument("--force", action="store_true", help="忽略已安装状态，强制重装")
        p.add_argument("--yes", "-y", action="store_true", help="跳过确认")
        p.add_argument("--dry-run", action="store_true", help="只解析下载项，不执行")
        p.add_argument("--verbose", "-v", action="store_true", help="输出子进程日志")
        p.add_argument("--only", default="", help="只处理指定组件，逗号分隔：flutter,jdk,android")

    for name, help_text in (
        ("check", "检查工具链（默认）"),
        ("install", "检查并自动安装缺失项"),
        ("env", "生成 .tooling/env.ps1 与 env.sh"),
        ("plan", "打印将要下载的 URL 与校验和"),
    ):
        common(sub.add_parser(name, help=help_text))
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:  # noqa: BLE001 - 老终端不支持时忽略
        pass

    parser = build_parser()
    raw = list(sys.argv[1:] if argv is None else argv)
    if not any(token in ("check", "install", "env", "plan") for token in raw):
        raw = ["check", *raw]  # 不写子命令时默认执行 check，同时允许传 --mirror 等选项
    args = parser.parse_args(raw)

    manifest = load_manifest()
    mirror = args.mirror

    try:
        if args.command == "check":
            return 0 if cmd_check(manifest, mirror) else 1
        if args.command == "plan":
            return cmd_plan(manifest, mirror)
        if args.command == "env":
            return cmd_env(manifest, mirror)
        if args.command == "install":
            say("仓库：%s" % REPO_ROOT)
            say("工具链目录：%s" % TOOLING)
            say("清单：%s" % rel(MANIFEST_PATH))
            say("")
            if not args.yes and sys.stdin.isatty():
                answer = input("将下载 Flutter/JDK/Android SDK 到 .tooling（约 3 GB），继续？[y/N] ")
                if answer.strip().lower() not in ("y", "yes"):
                    say("已取消。")
                    return 0
            return cmd_install(manifest, mirror, args)
    except KeyboardInterrupt:
        say("")
        warn("已中断。已下载的分片会保留，下次继续。")
        return 130
    except RuntimeError as exc:
        bad(str(exc))
        return 1

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
