# 养码猿 (Hermes Controller)

远程管控你的 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 的 Android 应用。

通过直连 Hermes 内置 API Server，在手机上查看网关状态、与 AI 对话、浏览会话记录。

## 功能

- **状态面板** — 网关在线状态、版本、活跃 Agent 数、已连接平台数、当前模型/Provider
- **流式对话** — 基于 SSE 实时接收 AI 回复，支持停止任务、查看工具调用过程
- **会话记录** — 浏览历史会话，点击恢复完整对话上下文
- **斜杠命令** — 输入 `/` 自动补全 40+ 条 Hermes 内置命令
- **消息折叠** — 工具输出、错误信息自动折叠，点击展开
- **分页加载** — 长会话自动分页，滚动加载更早消息
- **自动登录** — API Key 加密存储，下次打开自动恢复连接
- **Material 3** — 支持亮色/暗色主题，跟随系统

## 截图

<!-- TODO: 添加截图 -->

## 前置要求

1. 一台运行中的 Hermes Agent 实例（Linux / macOS / WSL）
2. Hermes 已启用 API Server 平台

在 Hermes 服务器上执行：

```bash
hermes config set platforms.api_server.enabled true
hermes config set platforms.api_server.extra.host 0.0.0.0
hermes config set platforms.api_server.extra.port 8642
hermes config set platforms.api_server.extra.key YOUR_KEY
systemctl --user restart hermes-gateway
```

对应的配置文件 `~/.hermes/config.yaml`：

```yaml
platforms:
  api_server:
    enabled: true
    extra:
      host: 0.0.0.0      # 必须设 0.0.0.0，不能是 127.0.0.1
      port: 8642
      key: your_api_key_here
```

## 安装

### 方式一：直接下载 APK

从 [Releases](../../releases) 页面下载最新 APK，传输到手机安装。

### 方式二：自行编译

```bash
git clone https://github.com/mczf/hermes_controller.git
cd hermes_controller

# 需要 Flutter 3.12+ 和 Java 17
export PATH="$HOME/flutter/bin:$PATH"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

flutter pub get
flutter build apk --release

# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 连接方式

App 登录页需要填写服务器地址、端口和 API Key。根据你的网络环境选择对应方式：

### 局域网（手机和 Hermes 在同一 WiFi）

最简单的方式，适合家里或办公室使用。

1. 在 Hermes 服务器上查看局域网 IP：
   ```bash
   ip addr | grep "inet " | grep -v 127.0.0.1
   # 例如得到 192.168.1.100
   ```
2. 确保 API Server 监听 `0.0.0.0`（上一步已设置）
3. 手机连同一个 WiFi，App 里填：
   - 服务器地址：`192.168.1.100`（替换为你的实际 IP）
   - 端口：`8642`
   - API Key：你设置的 key

> 注意：如果 Hermes 服务器开了防火墙，需要放行 8642 端口：
> ```bash
> sudo ufw allow 8642/tcp
> ```

### 公共网络 — 有公网 IP

适合 Hermes Agent 运行在有公网 IP 的电脑上（云服务器、家里电脑、办公电脑等）。

在防火墙中放行 8642 端口（云服务器还需在安全组放行）
App 里填：
    服务器地址：你的公网 IP（如 123.45.67.89）
    端口：8642
    API Key：你设置的 key

> 安全建议：公共网络下 API Key 以明文 HTTP 传输，建议配合 Nginx 反向代理加 HTTPS，或使用下面的 Tailscale 方案。

### 公共网络 — 无公网 IP

适合 Hermes Agent 在没有公网 IP 的电脑上跑，但想在外面用手机控制。

推荐使用 [Tailscale](https://tailscale.com/)，免费版够用，无需公网 IP、无需端口转发。

1. 在 Hermes 服务器上安装 Tailscale：
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   # 记住显示的 IP，例如 100.64.0.3
   ```
2. 在手机上安装 Tailscale（Google Play 或官网下载 APK）
3. 手机和服务器登录**同一个** Tailscale 账号
4. App 里填：
   - 服务器地址：`100.64.0.3`（替换为你的 Tailscale IP）
   - 端口：`8642`
   - API Key：你设置的 key

Tailscale 的流量是端到端加密的，比裸 HTTP 暴露在公网安全得多。

### 其他内网穿透方案

如果你已经用 frp、ngrok、Cloudflare Tunnel 等工具，把穿透后的地址填进去即可。

例如用 frp 映射到 `your-domain.com:8642`，App 里就填：
- 服务器地址：`your-domain.com`
- 端口：`8642`

## 使用

1. 打开 App，按上方「连接方式」填写服务器地址、端口和 API Key
2. 点击「连接」，成功后进入主界面

底部三个标签页：

| 标签 | 功能 |
|------|------|
| 状态 | 网关状态、模型信息、会话统计 |
| 对话 | 与 Hermes 实时对话，支持斜杠命令 |
| 记录 | 浏览历史会话，点击恢复对话 |

## 技术栈

- **Flutter** 3.12+ (Dart)
- **Material 3** 设计语言
- **http** — REST API 调用 + SSE 流式接收
- **shared_preferences** — 登录状态持久化
- **intl** — 时间格式化
- **file_picker** — 附件选择

## 项目结构

```
lib/
├── main.dart                      # App 入口，全局 HermesApi 单例
├── services/
│   ├── hermes_api.dart            # REST API 封装（健康检查、会话、配置）
│   └── socket_service.dart        # SSE 流式对话（/v1/runs + 事件流）
├── pages/
│   ├── login_page.dart            # 连接配置 + 自动登录
│   ├── home_page.dart             # 底部导航 + 双击返回退出
│   ├── dashboard_page.dart        # 状态面板
│   ├── chat_page.dart             # 对话页（核心）
│   ├── sessions_page.dart         # 会话记录列表
│   └── about_page.dart            # 关于页
```

## API Server 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/health` | GET | 健康检查 |
| `/health/detailed` | GET | 网关详细状态 |
| `/v1/capabilities` | GET | 模型/Provider 信息 |
| `/api/sessions` | GET | 会话列表 |
| `/api/sessions/{id}` | GET | 会话元数据 |
| `/api/sessions/{id}/messages` | GET | 会话消息历史 |
| `/v1/runs` | POST | 启动 AI 任务 |
| `/v1/runs/{id}/events` | GET | SSE 事件流 |
| `/v1/runs/{id}/stop` | POST | 停止任务 |

## 开发

```bash
# 代码分析
flutter analyze

# 运行测试
flutter test

# 调试运行
flutter run
```

## 版本历史

- **V1.0.1** — 直连 Hermes API Server，SSE 流式对话，斜杠命令，会话恢复
- **V1.0.0** — 基于 hermes-web-ui 的初始版本

## 许可证

MIT

Copyright (c) 2026 mczf

## 开发者

微信：zymczf
