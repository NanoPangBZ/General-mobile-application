# General-mobile-application

面向 iOS / Android 的通用移动端应用（Flutter）。

## 仓库结构

| 路径 | 说明 |
| --- | --- |
| `native/com_host` | 子模块，指向 `com_host` 仓库的 `develop` 分支，提供底层通信能力（C 实现） |

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
