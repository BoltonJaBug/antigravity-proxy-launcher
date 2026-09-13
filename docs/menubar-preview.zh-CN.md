# 常驻菜单栏版验证说明

常驻菜单栏实现现在就是正式的 `Antigravity Proxy.app`，原来的一次性手动启动器已经由它替代。

## 构建与打开

```zsh
make test
make build
open "build/Antigravity Proxy.app"
```

如果要验证登录项，建议先安装到 `~/Applications`：

```zsh
make install
open "$HOME/Applications/Antigravity Proxy.app"
```

构建完成后也可以直接打开：

```text
<仓库目录>/build/Antigravity Proxy.app
```

## 预期行为

- 应用只显示菜单栏图标，不显示 Dock 图标；状态栏使用与 App 图标相同的抽象“A”标志。
- 应用常驻后不会自行启动 Antigravity；只有点击菜单里的“启动 / 重启 Antigravity”时才会主动拉起。
- 空闲时以 20 秒的低频间隔刷新状态，打开菜单时也会立即刷新，以便发现代理端口或配置变化。
- 官方 Antigravity 启动时，菜单栏从 macOS 应用通知开始一次启动检查，直到明确成功或失败。
- 如果菜单栏已经运行，之后直接启动的官方 Antigravity 没有继承代理环境，程序会短暂确认状态，然后自动接管并重启一次。
- 如果打开菜单栏程序时 Antigravity 已经在运行，程序会先提示保存内容；只有用户确认后才请求正常退出，而且不会强制终止未能正常退出的实例。
- 启动器会检查代理端口、Google 连通性、节点地区以及 Antigravity 日志中的初始化结果。主进程仍存在且日志显示界面/服务初始化成功后进入“已使用代理”状态，随后只保留低频状态刷新。
- 启动失败后不会再自动重试，也不会进入冷却循环。菜单栏会保存失败原因、弹一次提示，并显示“查看失败详情”。
- 失败后处理代理或切换节点，再点击“重新尝试启动 Antigravity”才会开始新一轮检查。也可以完全退出后直接重新启动官方 Antigravity，这同样会触发新一轮检查。
- 菜单中的“登录时启动”使用 macOS 的登录项机制。默认构建为 ad-hoc 签名，系统可能要求审批，或者注册失败；这不影响菜单栏主流程。
- 菜单中的“IP 信息”会通过当前代理查询出口 IP；一级菜单摘要直接显示 IP、位置和网络类型，子菜单包含服务商、ASN 线路和数据来源等详情。成功结果每 5 分钟最多自动刷新一次，也可以手动点击“刷新 IP 信息”。
- 网络类型根据第三方数据库返回的 `mobile`、`proxy`、`hosting` 标记分类：移动网络、代理/VPN、数据中心/机房，或普通宽带（住宅或企业）。最后一项不能确定就是家庭宽带。

## 建议验证顺序

1. 先打开代理客户端，确认原来的 HTTP/Mixed 端口可用。
2. 打开 `Antigravity Proxy.app`，确认菜单栏出现图标，Dock 中没有该应用。
3. 从菜单点击“检查代理和 Google 连通性”。
4. 从菜单点击“启动 / 重启 Antigravity”，确认 Antigravity 正常启动并登录后，菜单栏状态停在“Antigravity 已使用代理”。
5. 完全退出 Antigravity，然后直接点击官方 Antigravity 图标。观察新启动的未代理实例被自动退出并通过启动器重新拉起。
6. 切换到一个不可用节点，完全退出后直接启动 Antigravity。确认启动失败后会停止检查、显示原因，不会反复重启。
7. 切回可用节点，点击“重新尝试启动 Antigravity”。确认新一轮检查可以恢复为成功状态。
8. 也可以再次直接启动官方 Antigravity，确认新的官方启动事件会清除上次失败状态并重新检查。
9. 打开“IP 信息”子菜单，确认 IP 地址、位置、服务商、线路和网络类型均已显示；切换节点并重启 Antigravity 后，等待状态成功或手动刷新，确认 IP 信息随之更新。

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

菜单中的“编辑代理配置”会打开当前实际使用的配置文件，并在文件不存在时创建一个基础模板。

IP 信息查询默认使用：

```text
http://ip-api.com/json/
```

可以通过配置项覆盖：

```zsh
ANTIGRAVITY_IP_INFO_URL='http://ip-api.com/json/'
ANTIGRAVITY_IP_INFO_TIMEOUT='6'
```

## 当前限制

- 自动接管需要官方 Antigravity 正在运行且进程环境可以被读取；macOS 不支持给已运行进程补充环境变量，因此只能重启接管。
- “启动成功”是指主进程仍存在，并且 Antigravity 日志已经出现界面/服务初始化成功的证据。它不等同于后续所有业务请求永远可用。
- 菜单栏状态中的“代理端口正常”只代表端口可连接，不代表 Google 一定可达；Google 连通性可以使用菜单里的检查功能。
- 如果失败原因是代理客户端或节点，修复它们不会自动触发检查；需要点击“重新尝试启动 Antigravity”，或让官方 Antigravity 产生一次新的启动事件。
- 常驻菜单栏版使用正式应用名称和 Bundle ID；旧菜单栏预览版不应与它同时运行。
- IP 位置、服务商和网络类型来自第三方数据库，可能因节点、数据库更新或 API 限流而误判；`普通宽带`只表示未标记为移动网络、代理或机房，不保证是住宅家宽。
- IP 信息查询失败时菜单会显示失败原因，不会影响 Antigravity 启动和代理接管。
