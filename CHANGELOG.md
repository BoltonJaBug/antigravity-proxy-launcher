# Changelog

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
