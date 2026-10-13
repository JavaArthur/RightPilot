# RightPilot

一个自用的原生 macOS 右键工具。Finder 文件或空白处右键 → **RightPilot**，也支持 Finder 工具栏入口和菜单栏“选择目录进行操作”。macOS 13+，Swift / AppKit / SwiftUI / FinderSync，无外部依赖。

## 功能

- 新建 TXT、Markdown、JSON、YAML、Python、Shell、RTF、CSV、HTML、XML 文件，输入名称后创建；JSON 生成有效的 `{}`，脚本不会自动执行。
- 新建文件夹；重名时建议编号，创建过程始终拒绝覆盖现有文件或符号链接。
- 复制路径、Shell 安全引用路径、`file://` 链接、文件名；支持多选（最多 100 项，过长请求需分批）。
- 在 Terminal 或已安装的 iTerm2 中打开当前目录；使用 NSWorkspace 和目录 URL，不拼接 shell 命令。
- 添加、改名、排序和移除常用目录；移除只改菜单，不删除磁盘目录。
- 开关菜单项和文件类型，选择新建后是否在 Finder 选中，设置登录启动。
- 原创应用图标、Finder 根菜单图标和彩色功能图标；常用操作直接显示，其余按“更多复制 / 文件操作 / 图片转换”分组。
- 隐藏／取消隐藏所选项目，或当前目录的直接子项：先确认范围，不递归、不重命名、不删除；跳过符号链接及点号文件。恢复入口在“文件操作 → 取消隐藏当前目录中的项目”。
- 复制到指定目录：原件不变，不覆盖同名目标，批量操作逐项报告成功和失败。失败的复制可能留下未完成副本，请按报告检查。
- 图片转 PNG/JPEG：保留原图、同名自动编号、应用 EXIF 方向，JPEG 透明区铺白。限制 100 MB / 4000 万像素，只处理单帧，动画或多页图片拒绝转换。
- 复制文件 SHA-256：后台分块计算，只读取普通文件；文件中途变化会报错。批量结果附带路径。

在单个文件夹上右键，目录操作针对该文件夹；在文件上右键，目录操作针对其所在目录；在空白处右键，针对当前 Finder 目录。打开多个跨目录选项且无法确定目录时，禁用目录操作。

## 构建、测试与安装

需要 macOS Command Line Tools（`xcode-select --install`），不依赖完整 Xcode。

```sh
bash scripts/check.sh
bash scripts/build-app.sh
bash scripts/install.sh
open "$HOME/Applications/RightPilot.app"
```

构建产物为 `dist/RightPilot.app`，安装脚本默认安装到 `~/Applications/RightPilot.app`，仅更新同 Bundle ID 的已有应用，注册并启用自己的 Finder 扩展。系统如未加载，请在 RightPilot 设置页点击“打开扩展设置”检查开关，再新开 Finder 窗口。脚本不会关闭 Finder 或改动其他扩展。升级会先停止自己的主程序和扩展，之后需重新打开主程序。

默认使用本机 ad-hoc 签名；可用 `SIGNING_IDENTITY='证书名称' bash scripts/build-app.sh` 选择已有证书。不是公证发布包。`ARCH=x86_64` 可用于交叉构建，但 Intel 运行未验证。

`check.sh` 包含 Foundation 核心测试和 AppKit 原生适配测试；使用独立断言运行器，无需 XCTest。CI 在 macOS 上运行相同检查并构建、验签；CI 不验证 Finder 宿主菜单和真实终端窗口。

## 使用与数据

配置保存在 `~/Library/Application Support/RightPilot/config.json`。配置损坏或版本未知时保留原文件并暂停保存，界面显示错误。请修复文件后重启；不会悄悄用默认设置覆盖。可用 `--config /absolute/path.json` 指定隔离测试配置。

主程序为普通本机应用，文件访问仍受系统权限与 TCC 限制；扩展启用 App Sandbox，仅负责读取 Finder 上下文并生成菜单。不申请辅助功能、输入监听、网络或管理员权限。终端与 Finder 由系统 API 打开，不运行文件内容。

主程序保持运行时，菜单设置立即同步到扩展；扩展保留上次配置快照。主程序退出后，点击操作会唤起它，新启动的扩展要等主程序运行后才能收到最新常用目录。首次启用请打开主程序检查同步回执。设置通知是本机同一登录会话的协调机制，不是秘密传输通道：只发送菜单设置和常用目录路径，不广播文件内容或命令。

1.1 会把配置版本 1 升为版本 2，保留旧功能开关、常用目录及默认终端，只加入新增功能和模板。第一次保存设置才写回磁盘；受损配置继续保留原文件。

## 与超级右键专业版的功能差异

以下以本次研究的 2.2.6 安装包为参照，不代表该产品最新版本。

| 功能 | RightPilot 1.1 的处理 |
|---|---|
| 菜单图标、新建文件、复制路径/名称、常用目录、终端 | 已实现；图标为原创矢量标记和系统符号 |
| 隐藏／取消隐藏、复制到目录、PNG/JPEG 转换 | 本次补齐；不覆盖、不递归隐藏、不动原图 |
| 文件哈希 | 实现 SHA-256，未重复提供 MD5/SHA-1 等算法 |
| 文档模板 | 10 种自建文本/富文本模板；没有复制商业软件的 Office/WPS/iWork/PSD/AI 模板 |
| 剪切/粘贴、移动、彻底删除、授写权限 | 暂不做，避免数据丢失和权限修改；保留 Finder 自带操作 |
| 压缩/解压、截图/贴图 | 不接入 FastZip/iShot，不重写相关引擎；可用系统压缩及独立工具 |
| 全局手势、独立弹出菜单 | 不做，需要额外事件监听和权限维护 |
| 多种编辑器快捷入口、AirDrop、桌面替身、自定义文件图标 | 暂不重复 Finder 自带“打开方式”、共享、制作替身和简介能力 |
| 图标集生成、WebP 编码、文本翻译/二维码 Services | 暂不做，使用频率低于本轮补齐项，增加格式/服务维护范围 |

本轮目标是日常 Finder 操作完整可用，不追求逐项复制商业软件的全部功能。

## 实现结构

| 路径 | 职责 |
|---|---|
| `Sources/RightPilotCore` | 配置、请求协议、菜单策略、独占文件创建 |
| `Sources/RightPilot` | 菜单栏、设置窗口、动作队列与系统适配 |
| `Sources/RightPilotFinder` | FinderSync 扩展、上下文快照、设置同步 |
| `Shared` | NSMenu 渲染、跨进程 tag 映射、剪贴板与终端适配 |
| `Tests` | 文件、路径、协议、配置、菜单和原生适配回归检查 |

扩展通过带 UUID 的 `rightpilot://action` 请求将每次操作送到固定的主应用路径，主程序校验协议、大小、路径和动作参数，排队并去重。Finder 会跨进程重建菜单项，因此以 tag 映射不可变操作快照，不依赖自定义 representedObject。常用目录请求只传 ID，由主程序解析自己的配置。

本项目根据公开系统 API 与行为研究重新实现；未复制商业程序的源码、反编译伪代码、图标、模板或二进制。原研究证据不在此仓库。

## 验证

本机验证结果与未覆盖范围见 [VERIFICATION.md](VERIFICATION.md)。接口依据：[Apple Finder Sync 指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)、[分布式通知说明](https://developer.apple.com/documentation/foundation/distributednotificationcenter/post(name:object:userinfo:))。
