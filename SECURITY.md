# Security policy

## Supported versions

Security fixes are applied to the latest published CommandHall release. Pre-release builds and historical snapshots may not receive fixes.

## Report a vulnerability

Use [GitHub's private vulnerability reporting](https://github.com/SubliminalCoding/CommandHall/security/advisories/new). Do not open a public issue for a suspected vulnerability and do not include credentials, private prompts, workspace data, or crash reports in a public post.

Include:

- the affected version and macOS version;
- the authority profile and integration involved;
- the smallest reliable reproduction;
- the security boundary that was crossed or could be crossed;
- sanitized logs or screenshots, if needed.

You should receive an acknowledgment within seven days. A fix timeline depends on severity and reproducibility. Please allow time for a patched, signed, and notarized release before public disclosure.

## Security boundaries

CommandHall launches local tools with the folders and authority selected by the user. macOS privacy controls, provider permissions, workspace boundaries, and the app's scoped local bridge are separate enforcement layers. Unrestricted agent sessions intentionally disable provider sandbox and approval safeguards; only use that profile for trusted work.

CommandHall does not automatically upload prompts, workspace memory, run history, artifacts, or crash reports. Third-party CLIs and configured model endpoints have their own data-handling policies.
