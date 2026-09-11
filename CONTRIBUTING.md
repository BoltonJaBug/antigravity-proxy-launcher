# Contributing

Thanks for helping improve Antigravity Proxy Launcher.

## Development

Requirements:

- macOS 13 or newer
- Git
- zsh
- Xcode Command Line Tools (`plutil`, `codesign`)

Run the checks:

```zsh
make test
```

Build the application bundle:

```zsh
make build
```

## Pull requests

- Keep changes limited to one logical topic.
- Explain the proxy client, Antigravity version, and macOS version used for testing.
- Do not add proxy credentials, subscriptions, node URLs, personal paths, or copied proprietary assets.
- Update both README files when behavior or configuration changes.
- Keep the launcher scoped to Antigravity. Do not add global proxy or TUN changes.

## Reporting bugs

Include:

- macOS version
- Antigravity version
- Proxy client name
- Proxy type and port
- Output of `--print-config` after removing any sensitive values
- Relevant lines from `~/Library/Logs/Antigravity/main.log`
- Relevant lines from `~/Library/Logs/Antigravity/language_server.log`

Never post access tokens, refresh tokens, cookies, subscription URLs, or proxy credentials.
