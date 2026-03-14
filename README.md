# Delta Build Notifer

Delta Build Notifer is a native macOS menu bar app for tracking CircleCI builds and Vercel deployments without keeping dashboards open.

## What It Does

- Watches CircleCI projects for passing, failing, running, and approval-required workflows
- Watches Vercel projects for deployment ready and deployment error states
- Sends native macOS notifications with optional sound
- Supports launch at login and per-project watch preferences
- Stores API tokens in persistent local app storage for smooth internal builds

## Requirements

- macOS 14+
- Swift 5.9+ or Xcode 15+ to build locally
- CircleCI and/or Vercel access tokens

## Install

### DMG

1. Download the latest `.dmg`
2. Drag `Delta Build Notifer.app` to `Applications`
3. Launch the app

This repository currently builds an ad-hoc signed, non-notarized app. On some Macs, first launch may be blocked until the user goes to `System Settings > Privacy & Security` and clicks `Open Anyway`.

### Build Locally

```bash
git clone <repo-url>
cd build-notifier
./build-app.sh
open "Delta Build Notifer.app"
```

To build with a local signing identity already installed in Keychain:

```bash
security find-identity -v -p codesigning
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build-app.sh
```

This helps when each teammate builds on their own Mac. It does not replace Developer ID signing or notarization for shared distribution.

## Development

```bash
swift build
swift run
./build-app.sh
./build-dmg.sh
```

Important paths:

- `BuildNotifier/Views/` for SwiftUI screens
- `BuildNotifier/Services/` for CircleCI, Vercel, notifications, and polling
- `BuildNotifier/State/AppState.swift` for app-wide state
- `build-app.sh` and `build-dmg.sh` for packaging

## Notes

- CircleCI only returns projects the user follows.
- Vercel support is project-based and tracks deployments from watched projects.
- The app icon is bundled during `./build-app.sh` from `BuildNotifier/Assets/AppIcon.icns`.
