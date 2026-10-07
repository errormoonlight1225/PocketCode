# Pocket Code — iOS 12+ 原生 Codespaces 客户端

[完整源码](pocket-code) · [MIT 许可证](pocket-code/LICENSE) · [编译记录与 IPA](https://github.com/errormoonlight1225/PocketCode/actions/workflows/build-pocket-ios12.yml)

原生 UIKit 文件浏览、编辑器、基础 ANSI 终端和 Git 操作。支持「新版深色底部导航 / 经典浅色列表」切换，GitHub 官方设备授权登录；不会读取你的 GitHub 密码。

## 一键安装连接服务

**在你要编辑的 Codespace 项目根目录终端执行**（不是在 iPhone 上执行）：

```bash
curl -fsSL https://raw.githubusercontent.com/errormoonlight1225/PocketCode/main/install.sh -o /tmp/pocket-code-install.sh && bash /tmp/pocket-code-install.sh
```

脚本会校验服务文件 SHA-256，安装到当前用户目录，后台启动 Pocket Bridge，显示 **App 连接地址** 和 **App 连接密钥**。需要 Linux、Bash、Python 3.10+；Codespaces 默认镜像通常已具备。不使用 sudo，不安装 pip 依赖，不改 shell 启动文件。

1. 在 Codespaces 的 **Ports** 确认 `8765` 已转发且为 **Private**。脚本输出 localhost 地址以触发自动转发，并在可用时调用 GitHub CLI 设置为 Private；若权限不足，会提示你手动检查，不会声称已成功。
2. 打开 iPhone App → 工作区 → 连接 → **使用 GitHub 账号登录**，按提示在官方页面完成授权。
3. 填入脚本显示的地址和密钥，点击 **连接工作区**。

也可填写 `https://工作区名称.github.dev`，App 会转换为默认 8765 端口地址。自定义端口请填写脚本显示的完整地址。

### 服务管理

```bash
~/.local/bin/pocket-code status
~/.local/bin/pocket-code info       # 再次查看地址与密钥
~/.local/bin/pocket-code restart
~/.local/bin/pocket-code stop
~/.local/bin/pocket-code start
```

安装后无需一直开着终端。Codespace 停止/重启会结束服务，重新进入后运行 `~/.local/bin/pocket-code start`。密钥在服务重启和重复安装时保持不变。重新安装会更新磁盘文件，已在运行的进程需 `restart` 才加载新代码；重启会关闭当前 Shell 会话。

自定义工作区或端口：

```bash
bash /tmp/pocket-code-install.sh --root /workspaces/my-project --port 8765
```

运行时切换工作区前先 `pocket-code stop`，避免把 App 的旧草稿保存到另一个项目。

可选自动启动：在**你自己的项目** `.devcontainer/devcontainer.json` 中合并以下设置，保留已有配置和生命周期命令：

```json
{
  "forwardPorts": [8765],
  "portsAttributes": {"8765": {"label": "Pocket Code", "onAutoForward": "notify"}},
  "postStartCommand": "test ! -x ~/.local/bin/pocket-code || ~/.local/bin/pocket-code start"
}
```

此配置不会由安装脚本自动写入；重建容器后若用户目录被清除，需要重新安装。

## 安装 iPhone App

在 [Pocket Code iOS 12 Actions](https://github.com/errormoonlight1225/PocketCode/actions/workflows/build-pocket-ios12.yml) 成功构建的 Artifacts 中下载 IPA。**IPA 未签名，需要自行签名后安装**；上面的一键脚本安装的是 Codespace 服务，不会给 iPhone 签名或绕过安装要求。

最低 iOS 12.0、arm64。新版 UI 在「工作区 → 连接 → 界面风格」切换；经典 UI 从首页右上角「设置」切回。账号、文档和草稿共用。

GitHub OAuth 应用已预配置为本仓库作者的 Pocket Code，Device Flow 只申请 `codespace` scope。你仍需自行确认授权。若旧 Safari 无法打开授权页，可在另一设备访问 https://github.com/login/device，输入 App 显示的同一授权码。

## 从完整源码构建

```bash
git clone https://github.com/errormoonlight1225/PocketCode.git
cd PocketCode/pocket-code
brew install xcodegen
bash scripts/build-unsigned.sh
```

需要 macOS + Xcode 16.x。产物为 `pocket-code/dist/CodeSpacePocket-unsigned.ipa`。`project.yml` 是 XcodeGen 项目定义。

源码目录：

| 目录 | 内容 |
| --- | --- |
| `pocket-code/App` | UIKit 双 UI、编辑器、终端、OAuth 和网络层 |
| `pocket-code/bridge` | Python 标准库连接服务、服务管理器和集成测试 |
| `pocket-code/Tests` | Swift 终端与工作区 URL 边界测试 |
| `pocket-code/scripts` | macOS IPA 编译脚本 |
| `install.sh` | 一键安装脚本及文件校验值 |

本地测试（Linux）：

```bash
bash -n install.sh
python3 pocket-code/bridge/test_installer.py
python3 pocket-code/bridge/test_bridge.py
```

从克隆目录离线安装服务代码：`bash install.sh --source-dir "$PWD" --root /workspaces/my-project`。

## 功能边界

- 真实原生文件编辑和远端 PTY；没有 VS Code 扩展、LSP 补全或原生调试器。
- 终端为基础 ANSI，不支持 SGR 彩色样式、鼠标协议或图像；复杂 vim/tmux 界面未保证完整兼容。
- 编译及自动测试通过；iOS 12 真机、私有端口及完整 OAuth 授权尚未端到端验证。
- Bridge 拥有当前 Codespace 用户的文件及 Shell 权限，只在自己的工作区使用。仅监听 localhost，私有端口还需 GitHub 授权；不要发布连接密钥。密钥保存在 `~/.local/share/pocket-code/connection.key`，权限 0600，不写入服务日志。

## 开源许可

`pocket-code/`、`install.sh` 和本说明按 [MIT](pocket-code/LICENSE) 开源。GitHub 及 Codespaces 的商标归各自权利人所有。

旧仓库文件已按原路径收录于 [`legacy/Ipa-Build/`](legacy/Ipa-Build/)，作为历史版本保留。当前开发、安装和构建以根目录及 `pocket-code/` 为准。

## Bridge 自启动

本仓库的 `.devcontainer/devcontainer.json` 在 Codespace 每次启动后运行本地安装脚本，自动启动 Bridge 并保留现有密钥。8765 端口保持 Private。

已有 Codespace 拉取本次更新后，需要执行一次 **Codespaces: Rebuild Container** 才会应用新配置；请先保存正在进行的工作。之后停止再启动 Codespace，无需手动启动 Bridge。立即启动也可执行 `bash .devcontainer/start-bridge.sh`。自启动输出不会显示连接密钥，使用 `~/.local/bin/pocket-code info` 单独查看。

自启动不会唤醒已停止的 Codespace，也不会阻止其自动休眠。
