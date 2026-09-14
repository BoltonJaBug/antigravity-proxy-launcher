# Changelog

## 1.3.0

- Add opt-in Codex desktop proxy launch and WebSocket diagnostics.
- Detect the active macOS SOCKS endpoint and use `socks5h://` for Codex `ALL_PROXY` traffic.
- Require a successful API and Responses WebSocket preflight before restarting Codex.
- Keep Codex takeover manual so AP never silently interrupts active tasks.
- Store the latest redacted Codex doctor report under `~/Library/Logs/AntigravityProxy/`.
- Keep the IP information submenu open while a manual refresh runs and updates in place.

## 1.1.0

- Promote the persistent menu bar app to the stable `Antigravity Proxy.app`.
- Automatically take over Antigravity instances launched after the menu app.
- Prompt before safely restarting an instance that was already running.
- Add low-frequency status refresh, proxy exit IP/location details, and login-item support.
- Keep the previous menu-specific build and install commands as compatibility aliases.

## 1.0.5

- Restore the launcher's Dock icon while Antigravity is starting.
- Stop startup monitoring and the Dock animation immediately once Antigravity's
  UI is ready, instead of waiting for the full diagnostic timeout.

## 1.0.4

- Run the launcher as a background UI element so macOS no longer keeps its
  Dock icon bouncing while proxy and startup diagnostics are running.

## 1.0.3

- Added a dedicated app icon inspired by Antigravity's visual language while
  keeping the distributed launcher artwork distinct from Google's official
  application icon.

## 1.0.2

- Fixed a false "Antigravity did not finish starting" dialog when
  `language_server.log` had been replaced and its new line count was still
  below the previous launch's line count.
- Added a regression test for the rotated log scenario.

## 1.0.1

- Added a proxy exit-region check before launch.
- Added a visible warning when the selected node is in a known unsupported region.
- Added post-launch log monitoring for region errors, proxy timeouts, and Electron load failures.
- Replaced silent startup failures with actionable macOS dialogs.
- Documented the new region and startup-check settings.

## 1.0.0

- Initial public release.
- Automatic macOS system proxy detection.
- Manual proxy configuration.
- App-scoped `language_server` proxy environment.
- Google connectivity health check.
- Automatic recovery from an old unproxied or blank Antigravity instance.
