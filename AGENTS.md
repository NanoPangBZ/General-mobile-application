# 置顶规则

没有用户明确允许，禁止修改本 Markdown 文件（`AGENTS.md`）。

# 开发环境规则

- 本仓库的 Flutter、JDK、Android SDK/NDK 开发环境由仓库本地脚本管理，安装目录为仓库根目录下的 `.tooling/`。
- AI 助手不得扫描、搜索或使用系统中已安装的 Flutter、Dart、JDK、Android SDK/NDK，也不得从系统环境变量、PATH、常见安装目录或用户目录中寻找替代工具链。
- 需要检查或安装环境时，只能调用仓库根目录的 `develop_env_install.bat`（Windows）或 `develop_env_install.sh`（macOS/Linux）；底层实现为 `tooling/dev_env.py`，版本来源为 `tooling/versions.json`。
- 每次开始开发命令前，使用仓库本地生成的激活脚本：PowerShell 执行 `. .\\.tooling\\env.ps1`，bash/zsh 执行 `source .tooling/env.sh`。若脚本或工具链缺失，先用上述仓库脚本安装或生成，不得回退到系统环境。
- 运行命令时确认工作目录为本仓库根目录；不得通过 PATH 或系统目录中的工具绕过本地环境。

# 设备描述表与设备页架构

- `lib/device_description.dart` 中的 `deviceDescriptionJson` 是随应用打包的设备描述表，`DeviceDescriptionCatalog` 负责解析设备列表，`DeviceDescription` 表示单个设备的匹配规则、连接参数、BLE 参数和页面标识。
- 首页根据 `bleName` 匹配扫描到的设备；连接时把对应的 `DeviceDescription` 交给 `BleService.configureFromDeviceDescription`，用于选择设备的 BLE 通信特征。`connection` 中的 Ping 次数、超时和间隔控制连接验证；字段缺省时使用 `DeviceDescription` 中声明的默认值。
- 设备 Ping 验证成功后，首页按描述中的 `page` 标识选择设备页。未提供 `page` 时使用 `default` 并打开通用 `DevicePage`；新增设备页时，应在设备描述中绑定标识，并在 `main.dart` 的 `_buildDevicePage` 中注册对应页面。
- `lib/device_page.dart` 是已连接设备页的基类，统一处理协议 Ping 心跳、返回首页时断开 BLE 连接等生命周期行为。设备专属页面继承 `DevicePage`，通过覆写 `pageTitle` 和 `buildDeviceContent` 提供专属标题与界面，并复用基类连接生命周期。
- 当前电吉他音箱描述绑定 `page: "ega"`，由 `lib/ega_device_page.dart` 中的 `EgaDevicePage` 实现；该页面继承 `DevicePage`。
