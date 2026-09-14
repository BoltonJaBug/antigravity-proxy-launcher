# Codex 桌面端代理支持实施方案

## 1. 目标

在 Antigravity Proxy（下文简称 AP）中增加 Codex macOS 桌面端代理支持，解决普通 HTTPS 请求可用、Responses WebSocket 持续 `Reconnecting` 的问题。

本功能必须满足以下约束：

- 不修改 macOS 全局代理。
- 不把 `~/.codex/.env` 作为桌面端的代理入口。
- 不持久写入 Codex 的 `config.toml`。
- 不在后台静默退出或重启 Codex。
- 所有测试默认禁止操作真实的 Codex 进程。
- 代理验证失败时，当前正在运行的 Codex 保持原样。
- 用户可以通过正常方式重新启动 Codex，立即恢复到未注入状态。

## 2. 已确认的本机事实

当前安装信息：

```text
应用路径：/Applications/ChatGPT.app
Bundle ID：com.openai.codex
主可执行文件：/Applications/ChatGPT.app/Contents/MacOS/ChatGPT
内置 Codex：/Applications/ChatGPT.app/Contents/Resources/codex
```

当前 Annie Office 同时提供 HTTP/HTTPS/SOCKS 代理，地址为 `127.0.0.1:33210`。端口只能作为本次诊断数据，代码中不得写死。

使用内置 `codex doctor --json` 的验证结果：

- 不注入代理：普通 API 可达，Responses WebSocket 握手超时。
- 只设置 `HTTP_PROXY`、`HTTPS_PROXY` 和 `NO_PROXY`：WebSocket 仍超时。
- `ALL_PROXY=http://...`：WebSocket 可连接，但普通 HTTPS 检查不稳定。
- 下列组合同时通过普通 API 与 WebSocket 检查：

```text
HTTP_PROXY=http://127.0.0.1:33210
HTTPS_PROXY=http://127.0.0.1:33210
ALL_PROXY=socks5h://127.0.0.1:33210
NO_PROXY=localhost,127.0.0.1,::1,.local
```

`WSS_PROXY` 不应作为主要方案；单独设置时诊断未使用它。

## 3. 总体设计

采用“预检、确认、接管、验证”四段式流程：

```text
检测系统代理
    -> 验证本地端口
    -> 在独立 doctor 进程中验证 HTTP + WebSocket
    -> 用户明确确认会中断当前 Codex 任务
    -> 正常退出 Codex
    -> 仅给新 Codex 进程注入代理变量
    -> 验证进程环境
    -> 显示结果
```

最重要的失败隔离边界是：前置诊断完成之前，禁止向 Codex 发送退出请求。

首个版本不实现 Codex 自动接管。即使 AP 收到 `com.openai.codex` 的启动通知，也只刷新状态，不执行 `--codex-auto-recover`。自动接管可在稳定版本中另行评估，并且默认必须关闭。

## 4. 代理模型扩展

### 4.1 当前问题

`src/AntigravityProxy` 当前只从 `scutil --proxy` 读取 HTTP 和 HTTPS，并把 `ALL_PROXY` 回退为 HTTP URL。Codex 的已验证组合需要 SOCKS URL。

### 4.2 新增状态

在 Shell 引擎中增加：

```zsh
SOCKS_PROXY_URL=''
ALL_PROXY_URL=''
CODEX_APP_FROM_ENV="${CODEX_APP:-}"
CODEX_APP="${CODEX_APP:-/Applications/ChatGPT.app}"
```

注意变量初始化不能覆盖调用方传入的 `CODEX_APP`。建议沿用现有 `ANTIGRAVITY_APP_FROM_ENV` 的写法，分别保存 override 和最终值。

### 4.3 系统代理检测

扩展 `detect_system_proxy()`，读取：

```text
SOCKSEnable
SOCKSProxy
SOCKSPort
```

生成规则：

- HTTP/HTTPS 仍使用 `http://host:port`。
- SOCKS 使用 `socks5h://host:port`，确保 DNS 也经代理解析。
- `ALL_PROXY_URL` 优先使用 `SOCKS_PROXY_URL`。
- 未检测到 SOCKS 时，`ALL_PROXY_URL` 回退到 `HTTPS_PROXY_URL`。
- IPv6 host 输出 URL 时必须加方括号。
- 不猜测 7890、1080 或其他常见端口。

为了避免破坏 Antigravity 现有行为，应让 `ALL_PROXY_URL` 成为新增值，不要直接改变 Antigravity 依赖的 `HTTP_PROXY_URL`、`HTTPS_PROXY_URL` 和 `GRPC_PROXY_URL`。

### 4.4 手动配置

在 `config/antigravity-proxy.conf.example` 支持：

```text
CODEX_APP='/Applications/ChatGPT.app'
ANTIGRAVITY_SOCKS_PROXY_URL='socks5h://127.0.0.1:33210'
```

如果用户只设置 `ANTIGRAVITY_PROXY_URL`，则 HTTP/HTTPS 使用该地址；SOCKS 仍可自动检测。若同时设置 `ANTIGRAVITY_SOCKS_PROXY_URL`，以后者为准。

`--print-config` 新增输出：

```text
SOCKS_PROXY=...
ALL_PROXY=...
CODEX_APP=...
```

## 5. Shell 引擎改动

目标文件：`src/AntigravityProxy`

### 5.1 新增命令

```text
--codex-preflight     只做 Codex HTTP/WebSocket 代理诊断，绝不退出或启动 Codex
--codex-launch        预检通过后，安全退出并以代理环境启动 Codex
--codex-status        可选；若不增加独立命令，则继续合并在 --status 中
```

首版不增加 `--codex-auto-recover`。

### 5.2 Codex 进程识别

增加：

```zsh
codex_pid()
codex_has_proxy_env()
wait_for_codex_exit()
resolve_codex_binary()
```

识别顺序：

1. 从 `CODEX_APP` 获取 `Contents/MacOS/ChatGPT`。
2. 使用完整可执行文件路径匹配主进程，避免误匹配 CLI、当前诊断进程或其他 Electron Helper。
3. 环境校验必须同时匹配当前期望值：
   - `HTTP_PROXY`
   - `HTTPS_PROXY`
   - `ALL_PROXY`
   - `NO_PROXY`
4. 可以接受大小写两组都存在，但至少大写组必须匹配，以便状态判断稳定。

不要使用宽泛的 `pgrep -f codex`，它会匹配 AP 启动的 doctor、CLI 和 app-server。

### 5.3 预检实现

新增 `codex_preflight()`：

1. 检查 `CODEX_APP` 目录存在。
2. 检查 `Contents/Resources/codex` 可执行。
3. 分别检查 HTTP/HTTPS 代理端口和 SOCKS 端口；如果地址相同只检查一次。
4. 使用临时进程环境执行：

```zsh
env \
  HTTP_PROXY="$HTTP_PROXY_URL" \
  HTTPS_PROXY="$HTTPS_PROXY_URL" \
  ALL_PROXY="$ALL_PROXY_URL" \
  NO_PROXY="$NO_PROXY_VALUE" \
  http_proxy="$HTTP_PROXY_URL" \
  https_proxy="$HTTPS_PROXY_URL" \
  all_proxy="$ALL_PROXY_URL" \
  no_proxy="$NO_PROXY_VALUE" \
  "$CODEX_BINARY" doctor --json
```

5. 保存原始诊断到：

```text
~/Library/Logs/AntigravityProxy/codex-doctor-latest.json
```

6. 解析诊断结果，必须满足：
   - ChatGPT/Codex inference provider 可达；HTTP 405 属于端点可达，不视为失败。
   - Responses WebSocket 返回 HTTP 101。
7. 桌面静态资源 CDN 可作为 warning，不能单独阻止启动。
8. 输出稳定的键值协议供 Swift 使用：

```text
CODEX_PREFLIGHT_STATUS=success|warning|error
CODEX_HTTP_STATUS=reachable|failed|unknown
CODEX_WEBSOCKET_STATUS=connected|timeout|failed|unknown
CODEX_PREFLIGHT_MESSAGE=...
CODEX_DOCTOR_LOG=...
```

doctor 可能耗时二三十秒，必须设置总超时，例如 40 秒；超时后返回错误，但不得影响当前 Codex。

解析逻辑不要依赖整段英文提示文本，应优先依赖 JSON 中的检查名称、级别、HTTP 状态码和 endpoint 类型。为兼容 Codex 更新，未知 JSON 结构必须返回 `unknown`，不能误判为通过。

### 5.4 安全启动实现

`launch_codex()` 的顺序必须固定：

1. 调用 `codex_preflight()`。
2. 预检失败立即返回，禁止退出 Codex。
3. 查找当前桌面 Codex PID。
4. 若已运行且环境与当前代理完全匹配，只执行 `open -a` 激活窗口。
5. 若已运行但环境不匹配，向菜单栏返回“需要用户确认”，或者仅在 `--codex-launch` 已由确认后的 UI 调用时继续。
6. 使用 AppleScript 按 Bundle ID 正常退出：

```text
tell application id "com.openai.codex" to quit
```

7. 最多等待 15 秒。
8. 首版禁止为了自动接管而 `kill -TERM`。正常退出失败则提示用户手动退出。
9. 使用 `/usr/bin/open --env ... -a "$CODEX_APP"` 启动，注入大小写两组：

```text
HTTP_PROXY / http_proxy
HTTPS_PROXY / https_proxy
ALL_PROXY / all_proxy
NO_PROXY / no_proxy
```

10. 不注入 `WSS_PROXY`，除非以后有新的 Codex 版本实验证明它被支持。
11. 等待主 PID 出现并验证其环境，最多 20 秒。
12. 验证失败时输出明确错误。不要循环重启。

启动后不必立即再次运行完整 doctor；完整 doctor 较慢，菜单可以先显示“代理已注入”，再提供手动 WebSocket 检查。

### 5.5 回滚

本方案没有持久网络改动，因此回滚方式非常简单：

- 正常退出 Codex。
- 从 Finder、Dock 或 Spotlight 正常打开 Codex。

这样新进程不会继承 AP 注入的环境变量。

AP 菜单中可以增加“以系统默认方式重启 Codex”，但它同样必须经过确认。该操作不能删除用户文件，也不能改写 `.env` 或 `config.toml`。

## 6. 菜单栏改动

目标文件：`src/MenuBar/main.swift`

### 6.1 RuntimeStatus

新增字段：

```swift
let codexInstalled: Bool
let codexPID: String
let codexHasProxyEnvironment: Bool
let codexAppPath: String
let codexAllProxyURL: String
```

Shell 的 `--status` 对应新增：

```text
CODEX_INSTALLED=0|1
CODEX_PID=...
CODEX_HAS_PROXY_ENV=0|1
CODEX_APP_PATH=...
ALL_PROXY_URL=...
```

保持键值协议向后兼容：Swift 对新增字段使用默认值，不要求旧引擎一定输出。

### 6.2 状态机

增加独立 `CodexState`：

```text
checking
notInstalled
stopped(proxyReady)
managed
restartRequired
preflighting
launching
failed(message)
```

Codex 使用独立状态机，不与其他应用复用状态。

### 6.3 菜单项

建议增加：

```text
Codex 未运行 / 已使用代理 / 需要安全重启
启动 Codex（代理模式）
安全重启 Codex 以应用代理
检查 Codex WebSocket
以系统默认方式重启 Codex
```

确认框文案必须说明：

```text
重启 Codex 会中断当前正在运行的任务和连接。
AP 已在独立进程中验证代理与 WebSocket；是否继续？
```

用户取消后不得把它记录成错误，也不得反复弹窗。

### 6.4 不自动接管

`handleWorkspaceNotification` 可以识别 `com.openai.codex` 以刷新菜单状态，但不得像 Antigravity 那样因 direct launch 自动调用恢复操作。

这是避免 AP 在开发或当前对话期间把自身宿主重启掉的核心保护。后续若加入实验性自动接管，必须具备以下全部条件：

- 配置项显式开启，默认关闭。
- 只接管刚启动、尚未进入工作状态的新 PID。
- 有抑制窗口，防止重启循环。
- 最多尝试一次。
- 代理预检失败时绝不退出 Codex。

## 7. 避免开发过程中失联

实现与验证应分成两次提交或两个明确阶段。

### 阶段 A：纯代码和隔离测试

- 修改代理解析、状态输出、Codex 命令和 Swift 菜单。
- 所有测试使用临时目录、fixture JSON 和假应用路径。
- 禁止运行真实 `--codex-launch`。
- 禁止安装新构建到 `/Applications`。
- 禁止退出当前 Codex。
- 完成 `make test` 与 `make test-menu`。

阶段 A 完成后，即使代码有错误，当前 Codex 会话仍不会受影响，其他模型可以直接读取本文件、Git diff 和测试输出继续工作。

### 阶段 B：用户手动验收

- 先构建到仓库内的 `build/`，不覆盖已安装版本。
- 只运行 `--codex-preflight`，确认 HTTP 和 WebSocket 均通过。
- 把诊断结果和日志路径发给用户。
- 用户确认当前任务已保存后，再由用户从新构建的 AP 菜单点击“安全重启 Codex”。
- 当前开发会话可能在这一步断开，这是预期行为；代码和日志已经持久保存在仓库中。

任何自动化测试都不得进入阶段 B。

## 8. 测试计划

目标文件：

- `scripts/test.sh`
- `scripts/test-menubar.sh`
- 可新增 `tests/fixtures/codex-doctor/*.json`

### 8.1 Shell 单元测试

至少覆盖：

1. `scutil` 同时返回 HTTP/HTTPS/SOCKS，正确产生 `socks5h://`。
2. SOCKS 与 HTTP 使用不同端口。
3. 没有 SOCKS 时 `ALL_PROXY_URL` 回退为 HTTPS URL。
4. IPv6 代理地址正确加方括号。
5. 手动 SOCKS 配置覆盖自动检测。
6. `codex_has_proxy_env` 只有四个变量全部匹配才返回成功。
7. 旧代理端口残留时返回不匹配。
8. fixture 中 HTTP 405 + WebSocket 101 判定成功。
9. WebSocket timeout 判定失败。
10. CDN timeout + WebSocket 101 判定 warning，但允许启动。
11. JSON 结构未知时判定 unknown/error，不允许启动。
12. preflight 失败时，退出函数从未被调用。

建议将命令路径做成可测试 override，例如：

```text
SCUTIL_BIN
OPEN_BIN
OSASCRIPT_BIN
PS_BIN
PGREP_BIN
CODEX_DOCTOR_BIN
```

生产环境默认仍指向系统绝对路径。测试用 fake scripts 记录调用参数，以证明测试没有操作真实应用。

### 8.2 菜单测试

至少覆盖：

- 解析新增 Codex 状态字段。
- 未安装、未运行、已代理、需重启、预检中、失败等菜单文案。
- 点击启动先触发 preflight。
- 用户取消确认后不调用 launch。
- preflight 失败后不调用 launch。
- AP 收到 Codex 启动通知时只刷新状态，不自动接管。
- Codex operation 与 Antigravity operation 互斥，防止多个引擎同时操作应用。

Swift 当前没有独立测试 target，因此第一版可以延续现有构建验证和 Shell 黑盒测试；随后再把纯状态解析提取到可单测文件。

### 8.3 手动验收

按顺序执行：

```text
make test
make test-menu
make build
新构建中的引擎 --codex-preflight
```

检查预检输出和：

```text
~/Library/Logs/AntigravityProxy/codex-doctor-latest.json
~/Library/Logs/AntigravityProxy/menubar.log
```

在用户明确确认后进行一次真实启动验收：

- Codex 主进程具有预期四组大写代理变量。
- app-server 子进程继承代理环境。
- 菜单显示“Codex 已使用代理”。
- 手动 WebSocket 检查返回 HTTP 101。
- 连续使用一段时间不再反复 `Reconnecting`。
- 更换代理节点或端口后，AP 显示需要重启，但不自动退出 Codex。
- 使用“系统默认方式重启”后，注入环境消失。

## 9. 文档和版本

修改：

- `README.md`
- `README.zh-CN.md`
- `CHANGELOG.md`
- `config/antigravity-proxy.conf.example`

文档应明确区分：

- Antigravity：现有自动接管逻辑。
- Codex：首版仅手动安全接管，不会后台自动重启。

版本号应在功能完成、测试通过后统一提升；不要在方案阶段先改版本。发布前再更新构建产物和 Release。

## 10. 推荐实施顺序

1. 先加入 SOCKS/ALL_PROXY 数据模型及测试。
2. 加入 doctor JSON fixture 与纯解析函数。
3. 实现 `--codex-preflight`，只运行隔离诊断。
4. 扩展 `--status` 和 Codex 进程环境检测。
5. 实现 `--codex-launch`，确保 preflight 在 quit 之前。
6. 加入 Swift 状态、菜单和确认框。
7. 完成自动化测试和文档。
8. 构建到仓库内目录，运行真实 preflight。
9. 停止并向用户报告结果，等待用户决定何时进行真实 Codex 重启验收。

## 11. 故障交接清单

如果实现过程中当前模型失联，后续模型应先执行只读检查：

```zsh
cd /Users/jiabaotong/work/2.code/Projects/mac/antigravity-proxy-launcher
git status --short
git diff -- src/AntigravityProxy src/MenuBar/main.swift scripts/test.sh scripts/test-menubar.sh
tail -n 200 "$HOME/Library/Logs/AntigravityProxy/menubar.log"
```

然后执行隔离测试：

```zsh
make test
make test-menu
```

在确认测试脚本没有调用真实 Codex 退出/启动命令之前，不得运行 `--codex-launch`，不得安装构建产物，也不得重启当前 Codex。

出现真实启动失败时，用户可正常退出 Codex，然后从 Finder/Dock 直接打开 `/Applications/ChatGPT.app`，即可清除进程级代理注入。由于方案不写 `.env`、`config.toml` 或系统代理，不需要删除任何持久配置。

## 12. 完成标准

只有同时满足以下条件才能宣布功能完成：

- 自动化测试全部通过。
- preflight 失败不会退出正在运行的 Codex。
- 不存在 Codex 默认自动接管路径。
- 代理端口完全动态检测，没有 7890/33210 等硬编码。
- HTTP 与 WebSocket 均通过真实诊断。
- 已注入和未注入状态能够准确区分。
- 代理变化时只提示重启，不产生重启循环。
- 回滚到系统默认启动经过验证。
- README 和 CHANGELOG 已更新。
