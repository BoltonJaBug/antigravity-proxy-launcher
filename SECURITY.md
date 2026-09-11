# Security Policy

## Supported versions

Only the latest release is supported.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature instead of opening a public issue.

Do not include proxy credentials, access tokens, refresh tokens, subscription URLs, or personal configuration files in reports.

## Design boundaries

This project intentionally:

- Does not modify system proxy settings.
- Does not enable TUN mode.
- Does not set proxy variables globally.
- Does not bundle proxy nodes or credentials.
- Does not modify the official Antigravity application bundle.
- Passes the proxy environment only to the launched Antigravity process tree.
- Starts Electron with `--no-proxy-server`.
