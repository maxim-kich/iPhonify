# Update signing

`sparkle-public-key.txt` contains iPhonify’s public Ed25519 update-signing key. The corresponding private key stays in macOS Keychain under `com.maximkich.iphonify.updates` and is never included in the repository or application.

The build embeds the public key and iPhonify’s signed release-feed URL. Updates are checked only when the user chooses Check for Updates in About.
