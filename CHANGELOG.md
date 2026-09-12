# Changelog

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
