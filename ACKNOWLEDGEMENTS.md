# Licenses & Acknowledgements

iPhonify uses the following open-source components, macOS technologies, and research references.

## iPhonify

iPhonify’s own source code is licensed under [MIT](LICENSE). Third-party components retain the terms and notices below. Previously published GPL-3.0-only releases remain available under their original terms; this change applies to the current source tree. The gesture engine originated in Maxim Kich’s HomeSwipe project.

## MagDot — interface and updater

The Settings layout, onboarding structure, menu controls, and update driver adapt code from [MagDot](https://github.com/maxim-kich/MagDot), by Maxim Kich. These author-owned adaptations are used in iPhonify under MIT with his authorization; this does not change MagDot’s own license. MagDot’s LED controller, privileged helper, and T3 Code integration are not included.

The updater also adapts Maxim Kich’s Drag 2.0 (DragTwoZero) code under the same owner authorization. The gesture engine’s HomeSwipe origin is retained above.

## InstantSpaceSwitcher — Space gestures

The native bridge uses DockControl event mapping and serialization from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), under the MIT license. Read the [complete MIT notice](docs/licenses/InstantSpaceSwitcher-MIT.txt). A copy is included in the app at `Contents/Resources/Legal/InstantSpaceSwitcher-MIT.txt`.

## Sparkle — in-app updates

iPhonify bundles [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/tree/2.10.1) and its helper tools to check, download, verify, and install updates. The bundled binaries target Apple Silicon.

Sparkle and its included components retain their copyright and license notices. Read the [complete Sparkle license and third-party notices](docs/licenses/Sparkle-LICENSE.txt). A copy is included in the app at `Contents/Resources/Legal/Sparkle-LICENSE.txt`.

## macOS technologies

iPhonify uses Swift and system frameworks including AppKit, Foundation, ApplicationServices, CoreGraphics, CoreImage, QuartzCore, ScreenCaptureKit, ServiceManagement, and the private MultitouchSupport and SkyLight interfaces. These system components are not bundled as separate copies.

System fonts and SF Symbols are provided by macOS. Their rights and terms remain with their respective owners.

## Research references

[Hammerspoon](https://github.com/Hammerspoon/hammerspoon), [CGSInternal declarations](https://github.com/asmagill/hs._asm.undocumented.spaces), and [noswoosh](https://github.com/mmathys/noswoosh) informed research into macOS windows and Spaces. These are research acknowledgements, not bundled applications.

## Artwork and build tools

The app icon was created with OpenAI image generation and prepared for macOS distribution. The menu-bar glyph is drawn by iPhonify’s own code. Apple’s logo and an SF Symbols font are not bundled.

Build tools include Apple’s developer tools, Python, and [dmgbuild](https://github.com/dmgbuild/dmgbuild). These tools are not included in the installed app.

Product names and trademarks belong to their respective owners. These acknowledgements do not imply endorsement or affiliation.
