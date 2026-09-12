# Changelog

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
