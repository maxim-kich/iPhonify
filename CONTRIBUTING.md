# Contributing

Contributions are welcome! Keep changes focused and explain the behavior they improve.

Build with `scripts/build-app.sh` and run `make test`. Ordinary tests must not grant permissions, activate gestures, or switch Spaces. Keep simulated checks and physical trackpad testing clearly distinguished.

Preserve desktop window state, reject uncertain fullscreen contexts, and keep cancellation reversible. Check fast releases, reversals, timeouts, and multiple displays when changing transitions. Run one gesture utility at a time during manual tests.

## Known issue

A brief desktop blink may occur during fullscreen transitions.

Do not include signing keys, Keychain exports, credentials, local logs, or private screenshots. Contributions are under MIT; retain third-party notices.
