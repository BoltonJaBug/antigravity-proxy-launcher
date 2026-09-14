# Antigravity Proxy Launcher

A small macOS launcher that lets Google Antigravity use a local proxy without enabling TUN mode.

[简体中文](README.zh-CN.md)

> This is not a proxy client and does not provide proxy nodes or subscriptions. It applies process-scoped proxy settings to Antigravity.

## Why

Antigravity consists of an Electron UI and a Go-based `language_server`. On some macOS proxy setups, the Electron UI works but the language server cannot reach Google, causing a blank window and `ERR_TIMED_OUT`.

This launcher:

- Detects the current macOS HTTP/HTTPS system proxy automatically.
- Detects the macOS SOCKS endpoint for Codex and injects the WebSocket `ALL_PROXY` only after a safe preflight.
- Sends only the Antigravity `language_server` through the selected proxy.
- Starts Electron with `--no-proxy-server`, so the local UI remains direct.
- Checks Google connectivity and the proxy exit region before launch to reduce blank-window failures.
- Monitors startup logs and shows actionable alerts for unsupported regions, proxy timeouts, and UI load failures.
- Works without TUN mode.
- Does not modify the system proxy or the official Antigravity application.

## Requirements

- macOS 13 or newer.
- Official Antigravity installed at `/Applications/Antigravity.app`.
- A working proxy client with a local HTTP/Mixed port, or a SOCKS5 port.
- No TUN mode required.

## Install a release

1. Download and unzip `AntigravityProxy-<version>.zip`.
2. Move `Antigravity Proxy.app` to `~/Applications` or `/Applications`.
3. Open it once. If Gatekeeper blocks an unsigned build, use **System Settings > Privacy & Security > Open Anyway**, or run:

```zsh
xattr -dr com.apple.quarantine "/Applications/Antigravity Proxy.app"
```

4. Enable **Launch at Login** from the menu. While it is running, opening the official Antigravity icon directly is supported and will be taken over automatically.

Releases are ad-hoc signed unless the repository owner configures Apple Developer ID signing and notarization.

## Build from source

```zsh
git clone https://github.com/BoltonJaBug/antigravity-proxy-launcher.git
cd antigravity-proxy-launcher
make test
make build
open "build/Antigravity Proxy.app"
```

Install into `~/Applications`:

```zsh
make install
```

### Persistent menu bar app

`Antigravity Proxy.app` is a persistent menu bar app that can take over Antigravity when the official icon is opened directly:

Codex desktop supports an explicit proxy-mode launch. AP runs Codex's own doctor in an isolated process first and only requests a normal Codex quit after both the API and Responses WebSocket checks pass. Codex is never taken over automatically, so active tasks are not silently interrupted.

```zsh
make test
make build
open "build/Antigravity Proxy.app"
```

`make install` installs it as `~/Applications/Antigravity Proxy.app`. Its **Launch at Login** command uses the macOS login-item mechanism.

The legacy `make test-menu`, `make build-menu`, and `make install-menu` commands remain as compatibility aliases for the same stable app. See the [menu bar validation guide](docs/menubar-preview.zh-CN.md) for the validation flow (Chinese).

The menu bar app includes an **IP Info** submenu. Its top-level summary shows the proxy exit IP, location, and network type; the submenu contains ISP/organization, ASN route, and data-source details. The network type is a third-party database heuristic:

```text
mobile=true                 -> Mobile network
proxy=true                  -> Proxy / VPN
hosting=true                -> Data center / hosting
all false                   -> General broadband (residential or business)
```

`General broadband` does not prove that the connection is a residential home line; free IP databases cannot reliably distinguish residential from business access.

## Configuration

### Automatic detection

By default, the launcher runs `scutil --proxy` and uses the active macOS HTTP/HTTPS and SOCKS proxies. Codex prefers the detected `socks5h://` endpoint for `ALL_PROXY`, so WebSocket DNS resolution also traverses the proxy.

The launcher does not assume that the proxy uses port `7890`. If no system proxy is detected, it asks the user to enable the proxy client's system-proxy integration or configure the actual port manually.

### Manual override

Create:

```text
~/.config/antigravity-proxy.conf
```

For example, when the proxy client reports HTTP/Mixed port `33210`:

```zsh
ANTIGRAVITY_PROXY_URL='http://127.0.0.1:33210'
ANTIGRAVITY_SOCKS_PROXY_URL='socks5h://127.0.0.1:33210'
```

A complete example is available at [config/antigravity-proxy.conf.example](config/antigravity-proxy.conf.example).

Manual configuration is recommended when the proxy client does not set the macOS system proxy, or when the client uses PAC mode.

Supported URL schemes:

```text
http://
https://
socks5://
socks5h://
```

An HTTP/Mixed port is usually the most compatible choice.

### Environment overrides

| Variable | Purpose |
| --- | --- |
| `ANTIGRAVITY_PROXY_URL` | Override the proxy URL. |
| `ANTIGRAVITY_SOCKS_PROXY_URL` | Override the SOCKS URL used for Codex `ALL_PROXY`. |
| `ANTIGRAVITY_APP` | Override the official app path. |
| `CODEX_APP` | Override the Codex desktop app path. Default: `/Applications/ChatGPT.app`. |
| `ANTIGRAVITY_CONFIG_FILE` | Override the config file path. |
| `ANTIGRAVITY_NO_PROXY` | Override the `NO_PROXY` value. |
| `ANTIGRAVITY_NO_AUTO_DETECT=1` | Disable system proxy detection. |
| `ANTIGRAVITY_REGION_CHECK=0` | Disable the pre-launch proxy exit-region check. |
| `ANTIGRAVITY_UNSUPPORTED_REGIONS` | Override the comma-separated unsupported-region list. |
| `ANTIGRAVITY_REGION_CHECK_TIMEOUT` | Region-check timeout in seconds. Default: `8`. |
| `ANTIGRAVITY_STARTUP_CHECK_SECONDS` | Log-monitoring window after launch. Default: `35`. |
| `ANTIGRAVITY_IP_INFO_URL` | IP info endpoint. Defaults to `http://ip-api.com/`. |
| `ANTIGRAVITY_IP_INFO_TIMEOUT` | IP info request timeout in seconds. Default: `6`. |

### Diagnostics

Print the detected proxy environment without network access:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --print-config
```

Check the proxy and print the environment without launching Antigravity:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --dry-run
```

Check the proxy exit country or region:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --check-region
```

For example, `PROXY_COUNTRY=US` means the proxy exits in the United States. Exit code `0` means the region check passed; exit code `2` means a known unsupported region was detected.

Show the current proxy exit IP information:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --ip-info
```

The structured output includes `IP_ADDRESS`, `IP_LOCATION`, `IP_PROVIDER`, `IP_ASN`, `IP_NETWORK_TYPE`, and `IP_INFO_SOURCE`. This command contacts a third-party IP information service and exits with code `1` when the lookup fails.

Check Codex API and WebSocket connectivity without quitting or restarting Codex:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --codex-preflight
```

A passing result includes `CODEX_WEBSOCKET_STATUS=connected`. The latest redacted report is stored at `~/Library/Logs/AntigravityProxy/codex-doctor-latest.json`.

## How it works

The launcher starts the official app using:

```text
open --env HTTP_PROXY=... \
     --env HTTPS_PROXY=... \
     --env GRPC_PROXY=... \
     --env NO_PROXY=... \
     -a /Applications/Antigravity.app \
     --args --no-proxy-server
```

This keeps Electron direct and lets `language_server` inherit the proxy variables. The Antigravity launch path intentionally does not set `ALL_PROXY`.

Codex uses a separate launch policy: HTTP/HTTPS use the detected HTTP/Mixed proxy, while `ALL_PROXY` prefers the detected `socks5h://` endpoint. AP does not write `~/.codex/.env`, `config.toml`, or global environment settings. Quit Codex and open it normally from Finder, Dock, or Spotlight to return to the default network environment.

Before launch it performs a low-frequency HTTP/1.1 connectivity check against:

```text
https://daily-cloudcode-pa.googleapis.com/
```

If the proxy port is unavailable or Google is unreachable, Antigravity is not launched.

After the Google check, the launcher makes one proxy exit-region request. If the result is a known unsupported region, such as mainland China, Hong Kong, or Russia, it shows a warning and lets the user cancel or continue. This check is only a risk warning: nodes in regions such as Hong Kong can still work, so the actual Antigravity API requests and startup logs are authoritative.

After Antigravity starts, the launcher watches `main.log` and `language_server.log` for up to 35 seconds. Unsupported-region errors, `ERR_TIMED_OUT`, `i/o timeout`, and UI load failures produce an actionable dialog instead of a silent blank window.

## Troubleshooting

### The launcher says the proxy is unavailable

- Start the proxy client and verify its node works.
- Check that the client uses an HTTP/Mixed or SOCKS5 port.
- If it does not set the macOS system proxy, add `~/.config/antigravity-proxy.conf`.
- Restart the proxy client after changing the port.

### The launcher reports `User location is not supported`

- The current proxy exit region is not supported by the Antigravity API. Hong Kong nodes can also trigger this error.
- Switch to a supported region such as the United States, Japan, or Singapore, then launch `Antigravity Proxy.app` again.
- Region detection is based on the proxy exit IP and cannot guarantee account eligibility or node quality.

### Antigravity is still blank

- Follow the specific message in the launcher dialog instead of repeatedly restarting.
- If it reports an unsupported region, switch to a United States, Japan, or Singapore node.
- If it reports a Google connection failure, switch to a more stable node and confirm the proxy client is still running.
- Prefer HTTP/Mixed over a SOCKS-only port.
- Fully quit Antigravity, then launch `Antigravity Proxy.app` again.
- Inspect `~/Library/Logs/Antigravity/language_server.log` for proxy timeout or TLS errors.

### An old Antigravity instance is running

When the menu bar app is already running, it automatically takes over a newly launched, unproxied Antigravity instance. If Antigravity was already running when the menu bar app starts, the user is prompted to save their work first. A confirmed restart requests a normal application quit and never force-terminates an instance that does not exit.

### macOS says the app cannot be verified

The project is not notarized by default. Use **Open Anyway** in System Settings, right-click the app and choose **Open**, or remove the quarantine attribute:

```zsh
xattr -dr com.apple.quarantine "/Applications/Antigravity Proxy.app"
```

## Security and privacy

- The launcher contains no proxy credentials, subscriptions, or node information.
- It does not edit system proxy settings.
- It does not enable TUN mode.
- It does not set proxy variables globally.
- It performs one small health-check request, retried at most three times at launch.
- It performs at most one proxy exit-region request before launch.
- The menu bar app refreshes the proxy exit IP at most once every 5 minutes; selecting the manual refresh action performs an immediate lookup.
- Antigravity still handles its own authentication and stores its own credentials normally.

## Limitations

- The proxy service and proxy nodes are not included.
- Automatic PAC evaluation is not supported. Use a manual URL if the proxy client only provides PAC.
- The official app path defaults to `/Applications/Antigravity.app`.
- Release builds are ad-hoc signed unless Developer ID signing is added to the release workflow.
- Proxy instability can still cause Antigravity's backend to time out after launch.
- Region checks depend on third-party IP geolocation and cannot cover every restriction Google may add or change.
- IP information and network classification depend on third-party databases such as `ip-api.com`; locations, providers, and mobile/hosting flags can be inaccurate, and `General broadband` does not guarantee a residential home connection.

## Disclaimer

This project is not affiliated with Google or OpenAI. Antigravity, Google, Codex, and OpenAI are trademarks of their respective owners. Use this launcher at your own risk and comply with the terms of service applicable to the software and proxy services you use.

## License

[MIT](LICENSE)
