# 菜单栏常驻版验证说明

这是下一阶段的独立预览版，不会替换现有的 `Antigravity Proxy.app`，也不改变已发布版本。

## 构建与打开

```zsh
make test-menu
make build-menu
open "build-menu/Antigravity Proxy Menu.app"
```

如果要验证登录项，建议先安装到 `~/Applications`：

```zsh
make install-menu
open "$HOME/Applications/Antigravity Proxy Menu.app"
```

构建完成后也可以直接打开：

```text
<仓库目录>/build-menu/Antigravity Proxy Menu.app
```

## 预期行为

- 应用只显示菜单栏图标，不显示 Dock 图标；状态栏使用与 App 图标相同的抽象“A”标志。
- 应用常驻后不会自行启动 Antigravity；只有点击菜单里的“启动 / 重启 Antigravity”时才会主动拉起。
- 空闲时完全不轮询。Antigravity 已正常连接后，不会继续运行后台状态检查。
- 官方 Antigravity 启动时，菜单栏从 macOS 应用通知开始一次启动检查，直到明确成功或失败。
- 检测到官方实例没有继承代理环境时，会短暂确认状态，然后自动退出该实例并通过 `--auto-recover` 重新启动一次。
- 启动器会检查代理端口、Google 连通性、节点地区以及 Antigravity 日志中的初始化结果。只有主进程仍存在且日志显示界面/服务初始化成功，才进入“已使用代理”状态并停止检查。
- 启动失败后不会再自动重试，也不会进入冷却循环。菜单栏会保存失败原因、弹一次提示，并显示“查看失败详情”。
- 失败后处理代理或切换节点，再点击“重新尝试启动 Antigravity”才会开始新一轮检查。也可以完全退出后直接重新启动官方 Antigravity，这同样会触发新一轮检查。
- 菜单中的“登录时启动”使用 macOS 的登录项机制。预览构建为 ad-hoc 签名，系统可能要求审批，或者注册失败；这不影响菜单栏主流程验证。

## 建议验证顺序

1. 先打开代理客户端，确认原来的 HTTP/Mixed 端口可用。
2. 打开 `Antigravity Proxy Menu.app`，确认菜单栏出现图标，Dock 中没有该应用。
3. 从菜单点击“检查代理和 Google 连通性”。
4. 从菜单点击“启动 / 重启 Antigravity”，确认 Antigravity 正常启动并登录后，菜单栏状态停在“Antigravity 已使用代理”。
5. 完全退出 Antigravity，然后直接点击官方 Antigravity 图标。观察未代理实例被自动退出并通过启动器重新拉起，成功后菜单栏停止跳动。
6. 切换到一个不可用节点，完全退出后直接启动 Antigravity。确认启动失败后会停止检查、显示原因，不会反复重启。
7. 切回可用节点，点击“重新尝试启动 Antigravity”。确认新一轮检查可以恢复为成功状态。
8. 也可以再次直接启动官方 Antigravity，确认新的官方启动事件会清除上次失败状态并重新检查。

## 日志和配置

菜单栏应用日志：

```text
~/Library/Logs/AntigravityProxy/menubar.log
```

Antigravity 原始日志：

```text
~/Library/Logs/Antigravity/
```

代理配置文件：

```text
~/.config/antigravity-proxy.conf
```

菜单中的“编辑代理配置”会在文件不存在时创建一个基础模板。

## 当前限制

- 自动接管需要官方 Antigravity 正在运行且进程环境可以被读取；macOS 不支持给已运行进程补充环境变量，因此只能重启接管。
- “启动成功”是指主进程仍存在，并且 Antigravity 日志已经出现界面/服务初始化成功的证据。它不等同于后续所有业务请求永远可用。
- 菜单栏状态中的“代理端口正常”只代表端口可连接，不代表 Google 一定可达；Google 连通性可以使用菜单里的检查功能。
- 如果失败原因是代理客户端或节点，修复它们不会自动触发检查；需要点击“重新尝试启动 Antigravity”，或让官方 Antigravity 产生一次新的启动事件。
- 预览版没有修改线上发布流程，可以独立安装和退出，不会替换稳定版启动器。
