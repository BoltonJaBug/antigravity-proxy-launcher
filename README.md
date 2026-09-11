# Antigravity Proxy Launcher

A small macOS launcher that lets Google Antigravity use a local proxy without enabling TUN mode or configuring Chromium to use the proxy.

[简体中文](README.zh-CN.md)

> This is not a proxy client and does not provide proxy nodes or subscriptions. It only applies a proxy environment to Antigravity's `language_server` process.

## Why

Antigravity consists of an Electron UI and a Go-based `language_server`. On some macOS proxy setups, the Electron UI works but the language server cannot reach Google, causing a blank window and `ERR_TIMED_OUT`.

This launcher:

- Detects the current macOS HTTP/HTTPS system proxy automatically.
- Sends only the Antigravity `language_server` through the selected proxy.
- Starts Electron with `--no-proxy-server`, so the local UI remains direct.
- Checks Google connectivity before launch to reduce blank-window failures.
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

4. Always launch Antigravity through `Antigravity Proxy.app`, not the official icon directly.

Releases are ad-hoc signed unless the repository owner configures Apple Developer ID signing and notarization.

## Build from source

```zsh
git clone https://github.com/YOUR_USERNAME/antigravity-proxy-launcher.git
cd antigravity-proxy-launcher
make test
make build
open "build/Antigravity Proxy.app"
```

Install into `~/Applications`:

```zsh
make install
```

## Configuration

### Automatic detection

By default, the launcher runs `scutil --proxy` and uses the active macOS HTTP/HTTPS proxy. This works when the proxy client enables the macOS system proxy.

If detection fails, it falls back to:

```text
http://127.0.0.1:7890
```

### Manual override

Create:

```text
~/.config/antigravity-proxy.conf
```

Example:

```zsh
ANTIGRAVITY_PROXY_URL='http://127.0.0.1:7890'
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
| `ANTIGRAVITY_APP` | Override the official app path. |
| `ANTIGRAVITY_CONFIG_FILE` | Override the config file path. |
| `ANTIGRAVITY_NO_PROXY` | Override the `NO_PROXY` value. |
| `ANTIGRAVITY_NO_AUTO_DETECT=1` | Disable system proxy detection. |

### Diagnostics

Print the detected proxy environment without network access:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --print-config
```

Check the proxy and print the environment without launching Antigravity:

```zsh
"/Applications/Antigravity Proxy.app/Contents/MacOS/AntigravityProxy" --dry-run
```

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

This keeps Electron direct and lets `language_server` inherit the proxy variables. The launcher intentionally does not set `ALL_PROXY`.

Before launch it performs a low-frequency HTTP/1.1 connectivity check against:

```text
https://daily-cloudcode-pa.googleapis.com/
```

If the proxy port is unavailable or Google is unreachable, Antigravity is not launched.

## Troubleshooting

### The launcher says the proxy is unavailable

- Start the proxy client and verify its node works.
- Check that the client uses an HTTP/Mixed or SOCKS5 port.
- If it does not set the macOS system proxy, add `~/.config/antigravity-proxy.conf`.
- Restart the proxy client after changing the port.

### Antigravity is still blank

- Switch to a more stable proxy node.
- Prefer HTTP/Mixed over a SOCKS-only port.
- Fully quit Antigravity, then launch `Antigravity Proxy.app` again.
- Inspect `~/Library/Logs/Antigravity/language_server.log` for proxy timeout or TLS errors.

### An old Antigravity instance is running

The launcher detects an existing instance that does not have the current proxy environment and restarts it automatically. If it cannot quit the old instance, quit Antigravity manually and retry.

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
- Antigravity still handles its own authentication and stores its own credentials normally.

## Limitations

- The proxy service and proxy nodes are not included.
- Automatic PAC evaluation is not supported. Use a manual URL if the proxy client only provides PAC.
- The official app path defaults to `/Applications/Antigravity.app`.
- Release builds are ad-hoc signed unless Developer ID signing is added to the release workflow.
- Proxy instability can still cause Antigravity's backend to time out after launch.

## Disclaimer

This project is not affiliated with Google. Antigravity and Google are trademarks of Google LLC. Use this launcher at your own risk and comply with the terms of service applicable to the software and proxy services you use.

## License

[MIT](LICENSE)
