# Pocket Code 2.1 — iOS 12 原生版

最低 iOS 12.0，arm64。UIKit 原生界面，无 WKWebView 网页 IDE 套壳。

- Codespaces 列表、启动和停止。
- 原生文件浏览、创建、多文档、本地草稿、UTF-8 编辑、基础高亮、查找替换、跳转行、远端保存冲突保护。
- 原生 PTY 终端，Ctrl / Esc / Tab / 方向键，基础 ANSI 屏幕和有限回滚。
- Git 状态、diff、提交、推送和本地分支切换。
- GitHub 官方设备授权登录及 Token 备用方式；凭据保存在本机 Keychain。

## 新旧 UI 切换

在「工作区 → 连接 → 界面风格」选择：
- **新版 UI**：深色主题、底部五个功能标签。
- **经典 UI**：浅色主题、分组列表工作台；右上角「设置」可切回新版。

两个模式都支持 iOS 12，账号、工作区、文档和草稿共用，选择会自动记住。切换的是原生导航和主题，不会切回网页套壳。

## GitHub 账号登录

GitHub API 不接受账号密码。客户端使用官方 Device Flow；账号密码及双重验证只在 GitHub 官方授权页输入，应用不会接收密码。

本仓库构建已预配置由 errormoonlight1225 拥有的 **Pocket Code** OAuth 应用。直接在「工作区 → 连接」点击「使用 GitHub 账号登录」即可开始授权，不用手动创建 Token 或填写 Client ID。首次仍须在 GitHub 官方页面确认本机授权。

如需改用自己注册的 OAuth 应用：
1. 在 https://github.com/settings/developers 新建自己的 OAuth App，名称 Pocket Code，主页填写本仓库，回调地址可填写 `pocketcode://oauth`（Device Flow 不使用回调）。
2. 勾选 **Enable Device Flow**。可保留 **Expire user access tokens**，客户端支持自动刷新。
3. 将该应用的 **Client ID** 填到 app「工作区 → 连接 → OAuth Client ID」。Client ID 是公开标识，不是 Client Secret；不要生成或填写 Client Secret。
4. 点「使用 GitHub 账号登录」，复制显示的授权码，进入 GitHub 官方页面，用自己的账号登录并确认授权。
5. 官方授权只申请 `codespace` scope。应用到 `/user` 验证账号后才显示登录成功。组织可能额外限制 OAuth 应用或要求 SSO。

也可以在「使用已有 Token」填写拥有 `codespace` 权限的个人访问令牌。Token、密码和 Bridge 密钥不要发到聊天或提交进仓库。

## 连接原生工作区

首次在 Codespace 的项目根目录终端运行：

```bash
curl -fL https://raw.githubusercontent.com/errormoonlight1225/Ipa-Build/main/CodeSpacePocket-xtool-source.zip -o /tmp/pocket-native.zip
unzip -o /tmp/pocket-native.zip -d /tmp/pocket-native
python3 /tmp/pocket-native/CodeSpacePocket/bridge/pocket_bridge.py --root "$PWD"
```

服务使用 Python 3.10+ 标准库，只监听 `127.0.0.1:8765`。在 Codespaces Ports 中转发 **8765** 并保持 **Private**。

app「连接」页填服务显示的 HTTPS 地址和随机连接密钥，然后连接。也支持输入 `https://工作区名称.github.dev`，自动转换为 `https://工作区名称-8765.app.github.dev`。

`.github.dev` 地址用来定位工作区，不是原生客户端的登录凭据。GitHub 官网登录后仍须启动 Bridge。Bridge 每次重启都会换密钥，需要更新客户端。

## iOS 12 版的限制

- 终端支持基础 ANSI 控制、光标、擦除、滚动区、备用屏幕；暂不支持 SGR 彩色样式、鼠标协议、终端图像。复杂 TUI（vim/tmux 等）未保证完整兼容。
- 保留原生界面；不提供 VS Code 扩展、LSP 自动补全或调试器。
- GitHub 官方网页的旧 Safari 兼容性由 GitHub 决定。若设备上授权页打不开，可在另一台设备的 https://github.com/login/device 输入 app 显示的同一授权码，回到 app 等待登录完成。
- iOS 12 真机与账号授权完整流程尚未验证。必须先签名 IPA，再在自己的设备上安装。

## 编译

GitHub Actions 使用 macOS 15 + Xcode 16.x。需要 XcodeGen：

```bash
brew install xcodegen
bash scripts/build-unsigned.sh
```

输出 `dist/CodeSpacePocket-unsigned.ipa`，未签名。项目使用 UIKit 和 URLSession completion handler，避免 SwiftUI、Combine 和 Swift 并发运行时的 iOS 13+ 依赖。
