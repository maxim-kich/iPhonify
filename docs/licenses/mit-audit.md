# Local MIT relicensing audit — 2026-11-05

## Scope and result

No incompatible third-party code or notice was identified in the tracked iPhonify tree. Maxim Kich explicitly authorized MIT licensing of his iPhonify, MagDot, and Drag 2.0 code. The current project license and existing active GPL source headers are changed to MIT; third-party terms remain separate. This does not change older release artifacts, tags, other projects, or dependencies.

The starting working tree was clean. `git shortlog -sne --all` reported 4 Maxim Kich commits and 67 T3 Code checkpoint commits. Source-path history likewise contains only those two author identities. The initial source import is `e3985bf`. Git attribution supports this audit but cannot by itself establish copyright ownership; the owner's explicit authorization supplies that basis.

## Provenance reviewed

- `app/SettingsWindow.swift`, `DockVisibilityController.swift`, permission/onboarding/menu code: MagDot adaptations, with author attribution retained. Updater files explicitly credit the author's DragTwoZero updater. These copies are covered by the owner's authorization, without changing the upstream projects.
- Gesture engine: documented HomeSwipe origin, Maxim Kich. Native touch bridge uses locally declared private macOS interfaces, dynamically resolved system functions, and application-specific callback handling. No additional third-party license header was found there.
- `src/TouchBridge/vendor/event_serialize.c` and `.h`: both byte-identical to [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher/tree/76fd272761d81563f8f747cf7d7ff266ec7ec4e3/Sources/ISS) at tree `76fd272761d81563f8f747cf7d7ff266ec7ec4e3`. SHA-256 respectively `9e9ba9dc332a0c75fa2bc47ab0b1f1ea5372b0397acc448ff1c33b4896a6f03c` and `8b422e8732518d9e3346881d971f245671f104c700cffba963b4e8027150034c`. `SpaceSwipe.c` explicitly credits its DockControl mapping. The jurplel MIT notice remains unchanged.
- Sparkle 2.10.1: fetched separately by `scripts/fetch-sparkle.sh` using a pinned SHA-256. The retained [upstream license](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE) contains MIT, BSD-style, and Ed25519 permissive terms. The repository notice matches the cached archive's LICENSE after whitespace normalization. No dependency is relicensed.
- `Package.swift` has only local TouchBridge and executable targets; Sparkle is integrated by the build script. Apple system frameworks are linked, not relicensed. Hammerspoon, CGSInternal and noswoosh are documented research references; no vendored implementation from them was identified in the tracked tree.
- Artwork/build-tool provenance remains in ACKNOWLEDGEMENTS.md; macOS fonts, symbols, trademarks, and developer tools acquire no MIT grant through this change.

## Distribution consistency

The existing build script copies LICENSE, ACKNOWLEDGEMENTS.md, and both third-party notices into `Contents/Resources/Legal`. About now identifies MIT and opens that local folder so it does not rely on the still-published GPL documentation. README and contributing terms describe MIT. The historical 0.0.1 release notes and git history are untouched.

## Limits

This is a source, notice, dependency configuration, and available git-history audit, not exhaustive similarity detection against every external codebase. Git authorship does not prove absence of unattributed copying. Cached dependencies were inspected; this audit does not certify every binary's source correspondence or Apple's private API distribution policy. No public release, installed app, physical gesture behavior, or native About visual rendering is validated by a local build. Public repository pages and existing distributed binaries retain their prior contents until separately authorized publication.
