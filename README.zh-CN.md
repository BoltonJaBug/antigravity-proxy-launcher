# Antigravity Proxy Launcher

一个 macOS 小工具，让 Google Antigravity 在不开启 TUN 模式、也不让 Chromium 全局走代理的情况下正常连接网络。

[English](README.md)

> 这不是代理客户端，不提供节点或订阅。它只给 Antigravity 的后台 `language_server` 注入代理环境变量。

## 解决的问题

Antigravity 由 Electron 界面进程和 Go 编写的 `language_server` 组成。某些 macOS 代理环境下，Electron 本身正常，但 `language_server` 无法访问 Google，最终表现为空白窗口和 `ERR_TIMED_OUT`。

启动器会：

- 自动读取 macOS 当前的 HTTP/HTTPS 系统代理。
- 只让 Antigravity 的 `language_server` 使用代理。
- 使用 `--no-proxy-server` 启动 Electron，保证本地界面直连。
- 启动前检查代理出口地区和 Google 连通性，减少空白窗口。
- 启动后监测日志；地区不支持、代理超时或界面加载失败时显示明确弹窗。
- 不需要 TUN。
- 不修改系统代理，也不修改官方 Antigravity 应用。

## 使用要求

- macOS 13 或更高版本。
- 官方 Antigravity 安装在 `/Applications/Antigravity.app`。
- 代理客户端提供一个可用的本地 HTTP/Mixed 端口，或 SOCKS5 端口。
- 不需要启用 TUN。

## 安装发布版

1. 下载并解压 `AntigravityProxy-<version>.zip`。
2. 把 `Antigravity Proxy.app` 移动到 `~/Applications` 或 `/Applications`。
3. 首次打开。如果没有经过 Apple 公证，Gatekeeper 可能拦截，可在“系统设置 > 隐私与安全性”中选择“仍要打开”，或执行：

```zsh
xattr -dr com.apple.quarantine "/Applications/Antigravity Proxy.app"
```

4. 以后始终通过 `Antigravity Proxy.app` 启动，不要直接点击官方 Antigravity 图标。

## 从源码构建

```zsh
git clone https://github.com/BoltonJaBug/antigravity-proxy-launcher.git
cd antigravity-proxy-launcher
make test
make build
open "build/Antigravity Proxy.app"
```

安装到 `~/Applications`：

```zsh
make install
```

### 菜单栏常驻版预览

仓库中已经包含一版独立的菜单栏常驻原型，用于验证“后台接管直接启动的官方 Antigravity”：

```zsh
make test-menu
make build-menu
open "build-menu/Antigravity Proxy Menu.app"
```

需要验证登录项时可执行 `make install-menu`，安装位置为 `~/Applications/Antigravity Proxy Menu.app`。

该预览版不会覆盖现有的 `Antigravity Proxy.app`。验证步骤、行为和已知限制见 [docs/menubar-preview.zh-CN.md](docs/menubar-preview.zh-CN.md)。

## 配置

### 自动检测

默认执行 `scutil --proxy`，读取 macOS 当前的 HTTP/HTTPS 系统代理。只要代理客户端开启了系统代理，不同端口也能自动适配。

如果没有检测到系统代理，则回退到：

```text
http://127.0.0.1:7890
```

### 手动指定

创建配置文件：

```text
~/.config/antigravity-proxy.conf
```

例如：

```zsh
ANTIGRAVITY_PROXY_URL='http://127.0.0.1:7890'
```

完整示例见 [config/antigravity-proxy.conf.example](config/antigravity-proxy.conf.example)。

代理客户端不设置系统代理，或者只使用 PAC 模式时，建议手动指定。

支持的代理协议：

```text
http://
https://
socks5://
socks5h://
```

优先使用 HTTP/Mixed 混合端口，兼容性通常最好。

### 环境变量

| 变量 | 作用 |
| --- | --- |
| `ANTIGRAVITY_PROXY_URL` | 手动指定代理地址。 |
| `ANTIGRAVITY_APP` | 指定官方 Antigravity 路径。 |
| `ANTIGRAVITY_CONFIG_FILE` | 指定配置文件路径。 |
| `ANTIGRAVITY_NO_PROXY` | 覆盖 `NO_PROXY`。 |
| `ANTIGRAVITY_NO_AUTO_DETECT=1` | 禁用系统代理自动检测。 |
| `ANTIGRAVITY_REGION_CHECK=0` | 禁用启动前代理出口地区检查。 |
| `ANTIGRAVITY_UNSUPPORTED_REGIONS` | 覆盖已知不支持地区列表，逗号分隔。 |
| `ANTIGRAVITY_REGION_CHECK_TIMEOUT` | 地区检查超时秒数，默认 `8`。 |
| `ANTIGRAVITY_STARTUP_CHECK_SECONDS` | 启动后日志监测时长，默认 `35` 秒。 |

### 诊断

不联网，只打印检测到的配置：

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --print-config
```

检查代理但不启动 Antigravity：

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --dry-run
```

检查当前代理出口国家或地区：

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --check-region
```

输出 `PROXY_COUNTRY=US` 表示出口为美国。退出码 `0` 表示地区检查通过；退出码 `2` 表示检测到已知不支持的地区。

## 工作原理

启动器通过以下方式启动官方应用：

```text
open --env HTTP_PROXY=... \
     --env HTTPS_PROXY=... \
     --env GRPC_PROXY=... \
     --env NO_PROXY=... \
     -a /Applications/Antigravity.app \
     --args --no-proxy-server
```

Electron 保持本地直连，`language_server` 继承代理环境变量。启动器刻意不设置 `ALL_PROXY`。

启动前会用 HTTP/1.1 低频检查：

```text
https://daily-cloudcode-pa.googleapis.com/
```

如果端口不可用或 Google 不可达，启动器不会启动 Antigravity。

通过 Google 检查后，启动器会查询一次代理出口的国家或地区。如果检测到中国大陆、中国香港、俄罗斯等已知不支持的地区，会先显示警告，允许取消启动或仍然继续。这个地区检查只是风险提示；香港等地区的节点有时仍可成功，最终以 Antigravity 实际 API 请求和启动日志为准。

Antigravity 启动后，启动器会在后台监测 `main.log` 和 `language_server.log` 最多 35 秒。发现地区不支持、`ERR_TIMED_OUT`、`i/o timeout` 或界面加载失败时，会弹出中文提示，说明应检查节点还是代理连接。

## 常见问题

### 提示代理不可用

- 确认代理客户端已运行且节点可用。
- 确认客户端提供 HTTP/Mixed 或 SOCKS5 端口。
- 如果客户端没有设置 macOS 系统代理，请创建 `~/.config/antigravity-proxy.conf`。
- 修改端口后重新打开 Antigravity Proxy。

### 提示“User location is not supported”

- 当前代理出口地区不受 Antigravity API 支持，香港节点也可能出现此提示。
- 切换到美国、日本或新加坡等支持地区的节点，然后重新打开 `Antigravity Proxy.app`。
- 地区判断基于代理出口 IP，实际账号资格和节点质量仍取决于代理服务。

### Antigravity 仍然白屏

- 先按启动器弹窗中的提示处理，不要只反复重启。
- 如果提示地区不支持，切换到美国、日本或新加坡节点。
- 如果提示 Google 连接失败，切换到更稳定的节点，并确认代理客户端仍在运行。
- 优先使用 HTTP/Mixed 端口。
- 完全退出 Antigravity，再打开 `Antigravity Proxy.app`。
- 查看 `~/Library/Logs/Antigravity/language_server.log` 中的代理超时或 TLS 错误。

### 已经有旧的 Antigravity 进程

如果旧实例没有当前代理环境，启动器会自动退出并重启它；如果无法自动退出，请手动退出 Antigravity 后重试。

### macOS 提示无法验证应用

项目默认没有 Apple 公证。可以在“系统设置”中选择“仍要打开”，右键应用选择“打开”，或者执行：

```zsh
xattr -dr com.apple.quarantine "/Applications/Antigravity Proxy.app"
```

## 安全与隐私

- 不包含代理账号、订阅或节点信息。
- 不修改系统代理设置。
- 不启用 TUN。
- 不设置全局环境变量。
- 启动时最多进行 3 次小型 Google 健康检查请求。
- 启动前最多进行一次代理出口地区检查请求。
- Antigravity 仍按原有方式处理认证和保存凭据。

## 限制

- 不包含代理服务和节点。
- 不支持自动解析 PAC，只提供 PAC 的客户端需要手动配置代理地址。
- 官方应用默认路径为 `/Applications/Antigravity.app`。
- 发布包默认仅做 ad-hoc 签名，除非在发布流程中加入 Apple Developer ID。
- 代理本身不稳定时，Antigravity 后台仍可能超时。
- 地区检查依赖第三方 IP 地理位置结果，无法覆盖 Google 后续增加或调整的所有地区限制。

## 免责声明

本项目与 Google 无隶属关系。Antigravity 和 Google 是 Google LLC 的商标。请自行承担使用风险，并遵守相关软件及代理服务的使用条款。

## 许可证

[MIT](LICENSE)
