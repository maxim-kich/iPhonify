# Update restart handoff

Restart still requires explicit confirmation after Sparkle stages the verified update. iPhonify captures the original activation intent once per update attempt, including preparation and termination retries.

Preparation blocks new gestures and activation changes. Existing gestures keep their normal completion, Escape cancellation and restoration paths. The updater waits up to 15 seconds for capture completion, permission requests, overlays, native Space transitions, dismissal and saved app/window ownership to finish. It then disarms the touch listener using the existing synchronous native stop, releases suppression and acknowledges readiness to Sparkle. No helper is registered by iPhonify. A timeout does not force restoration, clear ownership or tear down an active gesture; finish/cancel it and retry Restart, or cancel the staged update.

A bundle-ID/path/target-version-scoped receipt expires after ten minutes and is removed on its first read, including mismatches. An unchanged old version cannot consume it. It stores only ON/OFF intent. On replacement launch, ON uses the existing activation path only when onboarding and both OS approvals are ready; native API failure still leaves the menu OFF. Missing approval never triggers an automatic permission request or a delayed replay. Settings reopens on About, subject to the existing onboarding modal gate. Normal launches still start OFF and remain quiet.

Cancellation or failure clears the receipt and invalidates outstanding preparation completions. Cancellation never automatically reactivates the old process. A termination retry keeps the original intent and existing restart consent; preparation vetoes termination while waiting. A failed retry still permits an ordinary safe Quit under the original consent. Once Sparkle has accepted installation, its termination retry cannot be cancelled as if it were merely staged.

## Validation

- `scripts/test-updater-metadata.sh`: production updater/wait-loop coverage for consent, delayed acknowledgement, stop failure, timeout, cancellation, late completions, initial and termination retries, safe Quit after retry failure, ON/OFF receipt consumption and mismatches, expiry, installation error cleanup.
- Separate-path validation bundle built successfully; nested signing verified, linked SDK guard and inherited gesture/Space/motion self-tests passed. No live candidate was launched.
- Python release/configuration tests (10), native bridge concurrent stop test (no trackpad device opened), permission gates, status menu and repository checks passed.
- `scripts/test-updater-local.sh success` and `success-off`: actual signed disposable Sparkle replacement/relaunch from 9.0.1 to 9.0.2, fake activity acknowledgement before installation, settings retained and ON/OFF receipt consumed once in the replacement process.
- `scripts/test-updater-local.sh preparation-cancel`: actual signed staged update cancelled during fake activity preparation; old version retained, receipt removed and ordinary Quit allowed.

These fixtures use production updater code, disposable bundle identities/domains and temporary feed-signing test keys removed by cleanup. They never launch the gesture engine. They prove updater replacement and receipt delivery, not actual trackpad reacquisition, native Settings presentation, physical Space restoration, or installed-app permission continuity. Installed/hardware validation remains a separate authorized manual gate. No installed/running signed app, permissions or user preferences were changed, and no release was published.
