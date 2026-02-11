# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run debug build
swift run

# Create .app bundle (menubar-only, ad-hoc signed)
./build-app.sh

# Create distributable DMG
./build-dmg.sh

# Clean
swift package clean
rm -rf "CircleCI Notifier.app" *.dmg
```

## Debugging

```bash
# Run from terminal to see console output
.build/debug/BuildNotifier

# Reset all data
defaults delete com.buildnotifier.circleci
security delete-generic-password -s com.buildnotifier.circleci
```

## Architecture

**Swift Package Manager project** targeting macOS 14+ with Swift 5.9. No external dependencies.

### Core Patterns

- **Actor-based API client**: `CircleCIAPI` is an actor ensuring thread-safe token management and network requests
- **@Observable state**: `AppState` uses Swift's modern @Observable macro, @MainActor isolated
- **MenuBarExtra**: Native macOS 14+ menubar API, runs as `LSUIElement` (no dock icon)
- **Swift Concurrency**: async/await throughout, TaskGroup for parallel project fetching

### Key Components

| File | Purpose |
|------|---------|
| `AppState.swift` | Central @Observable state container. Manages screen navigation, preferences, build data, polling lifecycle |
| `CircleCIAPI.swift` | Actor-based API client for v1.1 (builds, projects) and v2 (workflow approvals) endpoints |
| `BuildPoller.swift` | Timer-based polling with TaskGroup parallel fetches. Detects status changes and triggers notifications |
| `KeychainService.swift` | Token storage via Security framework with UserDefaults fallback for dev builds |

### Data Flow

1. `AppState.initialize()` checks Keychain for token → validates via API → navigates to appropriate screen
2. `BuildPoller.startPolling()` runs on interval, fetches builds for all `WatchedProject`s in parallel
3. Status changes detected by comparing build numbers/statuses → `NotificationManager` sends macOS notifications
4. Pending approvals checked by fetching workflow jobs for running/on_hold builds

### CircleCI API Usage

Uses both API versions:
- **v1.1**: `/me`, `/projects`, `/project/:vcs/:org/:repo` (builds), retry/cancel
- **v2**: `/workflow/:id/job` (approval checks), `/workflow/:id/approve/:job_id`

Auth via `Circle-Token` header.

### Preferences

Stored in UserDefaults (`com.buildnotifier.circleci`):
- `watchedProjects`: array of `WatchedProject` with per-project follow mode (all/mine)
- Polling interval, notification toggles
