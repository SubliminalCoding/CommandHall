# CommandHall

CommandHall is a native macOS workspace for directing coding agents, terminals,
browser previews, missions, and review evidence from one persistent spatial
surface. It is built with SwiftUI and AppKit; the core workspace has no Electron
or npm runtime dependency.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or a Swift 6 toolchain
- Apple Command Line Tools
- An authenticated Claude Code or Codex CLI for the providers you use

CommandHall does not bundle provider subscriptions, credentials, or model
access.

## Build and test

```sh
swift test
scripts/build-app.sh release
open build/CommandHall.app
```

Local builds use ad-hoc signing by default. See `scripts/build-app.sh` for the
optional signing-identity environment variable.

## Security and privacy

CommandHall is local-first. Provider CLIs and configured model services receive
the context needed for the selected workflow, and agent authority is explicit
per session. Credentials entered in the app are stored in macOS Keychain.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and
[`specs/AGENT-BRIDGE-SECURITY.md`](specs/AGENT-BRIDGE-SECURITY.md) for the local
agent bridge boundary.

## Optional integrations

Remote Linux handoff, HQ/Jarvis, local OpenAI-compatible models, Barehands,
ClawStudio, OBS, and Groq are optional. The core workspace, local terminals,
browser previews, notes, and provider sessions work without them.

Barehands is a separately installed AGPL-3.0 project and is not bundled. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution details.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a change. Please report
security issues through the private process in [SECURITY.md](SECURITY.md), not a
public issue.

## License

CommandHall is available under the Apache License 2.0. See [LICENSE](LICENSE).
