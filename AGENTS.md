# Repository Guidelines

## Project Structure & Module Organization
- `BuildNotifier/` holds the SwiftUI app source.
- `BuildNotifier/Models/` contains data models (Build, Project, WorkflowJob, WatchedProject).
- `BuildNotifier/Services/` contains API, polling, notifications, keychain, and login-item logic.
- `BuildNotifier/State/` holds `AppState` and app-wide observable state.
- `BuildNotifier/Views/` is split by feature: `MenuBar/`, `Onboarding/`, and `Settings/`.
- Assets live in `BuildNotifier/Assets.xcassets/` and the app entry point is `BuildNotifier/BuildNotifierApp.swift`.
- Build scripts: `build-app.sh` (app bundle) and `build-dmg.sh` (DMG).

## Build, Test, and Development Commands
- Before making changes, run `git status --short --branch` and sync the current branch if it is behind its remote tracking branch.
- `swift build` builds a debug binary in `.build/debug/`.
- `swift build -c release` builds a release binary in `.build/release/`.
- `swift run` runs the debug build.
- `./build-app.sh` creates a menubar-only `.app` bundle (ad-hoc signed).
- `./build-dmg.sh` creates a distributable DMG.
- `swift package clean` cleans build artifacts.
- Debugging helpers:
  - `defaults delete com.buildnotifier.circleci` resets preferences.
  - `security delete-generic-password -s com.buildnotifier.circleci` clears keychain token.

## Coding Style & Naming Conventions
- Swift 5.9, 4-space indentation, trailing braces on the same line.
- Types use UpperCamelCase; properties/functions use lowerCamelCase.
- Keep SwiftUI views small and grouped by feature folder; prefer `// MARK:` to separate logical sections.
- Use async/await and actors for concurrency (see `CircleCIAPI`).

## Testing Guidelines
- No test targets are defined yet. If adding tests, name files `*Tests.swift` and place them under a new `Tests/` target in `Package.swift`.
- Prefer unit tests for models/services; add lightweight integration tests for API flows where practical.

## Commit & Pull Request Guidelines
- The repository has no commit history yet, so no established message convention exists. Use concise, imperative messages (e.g., "Add build poller backoff").
- PRs should include a short description, relevant screenshots for UI changes, and any new commands or setup steps.

## Security & Configuration Notes
- The CircleCI token is stored in macOS Keychain; avoid logging sensitive values.
- Entitlements are defined in `entitlements.plist`. Update deliberately if app capabilities change.
