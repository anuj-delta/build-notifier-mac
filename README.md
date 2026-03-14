# CircleCI Build Notifier

A native macOS menubar app that monitors your CircleCI builds and sends notifications for build successes, failures, and pending approvals.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Menubar-Only App**: Lives entirely in your menubar with no Dock icon
- **Launch at Login**: Optionally start automatically when you log in
- **Real-time Build Monitoring**: Auto-polls CircleCI for build status updates
- **Native Notifications**: macOS notifications with optional sound for build events
- **Pending Approval Support**: View and approve deployment gates directly from the app
- **Build Actions**: Retry failed builds or cancel running builds with confirmation dialogs
- **Per-Project Settings**: Follow all builds or only your own commits per project
- **Secure Storage**: API token stored in macOS Keychain (with fallback for dev builds)
- **GitHub & Bitbucket**: Supports both VCS providers

> **Note:** Only **followed projects** are shown. The CircleCI API only returns projects you actively follow. To monitor a project, first follow it on the [CircleCI dashboard](https://app.circleci.com/projects/).

## Screenshots

```
┌────────────────────────────────────────────────┐
│  CircleCI Builds               🔄  ⚙️          │
│  ────────────────────────────────────────────  │
│  ▼ myorg/frontend                              │
│    │ main      ✅ #1234   "Fix login"  2m ago  │
│    │ feature/x ❌ #1233   "Add feature" 15m ago│
│  ▼ myorg/backend                               │
│    │ main      🟡 #891    "Deploy v2"  1h ago  │
│  ────────────────────────────────────────────  │
│  Updated: just now                      [Quit] │
└────────────────────────────────────────────────┘
```

## Requirements

- macOS 14.0 (Sonoma) or later
- CircleCI account with Personal API Token

## Installation

### Option 1: Download DMG (Recommended)

1. Download `CircleCI-Notifier-1.0.0.dmg` from Releases
2. Open the DMG file
3. Drag "CircleCI Notifier" to Applications
4. Launch from Applications folder

> **Gatekeeper Note:** This project is currently distributed as an ad-hoc signed, non-notarized app. Without an Apple Developer account, the DMG cannot be Developer ID signed or notarized. Teammates may need to open the app once, then go to **System Settings > Privacy & Security** and click **Open Anyway**.

### Option 2: Build from Source

```bash
# Clone the repository
git clone <repo-url>
cd build-notifier

# Build the .app bundle
./build-app.sh

# Or build a distributable DMG
./build-dmg.sh

# Install to Applications
cp -r "CircleCI Notifier.app" /Applications/
```

By default, `./build-app.sh` uses ad-hoc signing. If teammates want to build and sign locally with a signing identity already present in their keychain, they can run:

```bash
# List available code signing identities
security find-identity -v -p codesigning

# Build using a local signing identity
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build-app.sh
```

This is mainly useful when each teammate builds on their own Mac. It does not replace Developer ID notarization for redistributing one shared DMG to everyone else.

### Option 3: Development Build

```bash
# Quick build for development
swift build

# Run directly
.build/debug/BuildNotifier

# Or build release version
swift build -c release
.build/release/BuildNotifier
```

## Setup

1. **Launch the app** - A circle icon appears in your menubar
2. **Click the icon** - Follow the setup prompts
3. **Enter API Token** - Get one from [circleci.com/account/api](https://circleci.com/account/api)
4. **Select Projects** - Choose which projects to monitor
5. **Configure Notifications** - Customize in Settings (gear icon)

## Usage

### Menubar Icon Status

| Icon | Color | Meaning |
|------|-------|---------|
| ✓ | Green | All builds passing |
| ✓ | Red | At least one build failing |
| ✓ | Yellow | Build in progress |
| ✓ | Orange | Pending approval waiting |
| ✓ | Gray | No data / loading |

### Build Row Actions

- **Click row**: Opens build in browser
- **Hover**: Shows action buttons
- **Retry** (↻): Retries failed build (with confirmation)
- **Cancel** (✕): Cancels running build (with confirmation)

### Pending Approvals

When a workflow is waiting for manual approval:
1. Orange badge appears in menubar
2. "Pending Approvals" section shows at top
3. Click **Approve** to approve directly (with confirmation)
4. Click **→** to open in browser

### Settings

Click the gear icon (⚙️) in the menubar popover to open the Settings window:

| Section | Setting | Options |
|---------|---------|---------|
| **General** | Launch at login | On/Off |
| | Refresh interval | 30s, 60s, 2min, 5min |
| **Notifications** | Enable notifications | On/Off (master toggle) |
| | Play sound | On/Off |
| | Build success | On/Off |
| | Build failure | On/Off |
| | Pending approval | On/Off |
| | Build started | On/Off |
| **Projects** | Per-project follow mode | All builds / My builds only |
| | Test notification | Button to verify notifications work |

### "My Builds Only" Mode

When enabled for a project, only shows builds where:
- Committer email matches your CircleCI account email
- Committer name matches your CircleCI name or login

## Project Structure

```
build-notifier/
├── Package.swift              # Swift Package manifest
├── build-app.sh               # Creates signed .app bundle
├── build-dmg.sh               # Creates distributable DMG
├── entitlements.plist         # App entitlements
├── README.md
│
└── BuildNotifier/
    ├── BuildNotifierApp.swift # App entry point, MenuBarExtra
    │
    ├── Models/
    │   ├── Build.swift        # Build data model + status enum
    │   ├── Project.swift      # Project + User models
    │   ├── WorkflowJob.swift  # Workflow jobs for approvals
    │   └── WatchedProject.swift # Watchlist + preferences
    │
    ├── Services/
    │   ├── CircleCIAPI.swift  # Async API client (v1.1 + v2)
    │   ├── KeychainService.swift # Secure token storage + fallback
    │   ├── NotificationManager.swift # macOS notifications
    │   ├── LaunchAtLoginService.swift # Login item management
    │   └── BuildPoller.swift  # Background polling logic
    │
    ├── State/
    │   └── AppState.swift     # @Observable app state
    │
    └── Views/
        ├── Onboarding/
        │   ├── OnboardingView.swift      # Token input
        │   └── ProjectSelectorView.swift # Project picker
        ├── MenuBar/
        │   ├── MenuBarContentView.swift  # Main popover
        │   └── ProjectSection.swift      # Build rows
        └── Settings/
            └── SettingsView.swift        # Preferences
```

## CircleCI API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1.1/me` | GET | Validate token, get user info |
| `/api/v1.1/projects` | GET | List followed projects |
| `/api/v1.1/project/:vcs/:org/:repo` | GET | Get recent builds |
| `/api/v1.1/project/.../retry` | POST | Retry failed build |
| `/api/v1.1/project/.../cancel` | POST | Cancel running build |
| `/api/v2/workflow/:id/job` | GET | Get workflow jobs |
| `/api/v2/workflow/:id/approve/:job_id` | POST | Approve pending job |

## Development

### Prerequisites

- Xcode 15+ or Swift 5.9+
- macOS 14.0+

### Build Commands

```bash
# Debug build
swift build

# Release build
swift build -c release

# Create .app bundle (menubar-only, no Dock icon)
./build-app.sh

# Create DMG for distribution
./build-dmg.sh

# Clean build artifacts
swift package clean
rm -rf "CircleCI Notifier.app" *.dmg
```

### Running in Development

```bash
# Run debug build directly
swift run

# Or build and run
swift build && .build/debug/BuildNotifier
```

### Debugging Tips

1. **Token Issues**: Delete from Keychain and re-enter
   - Open Keychain Access
   - Search for "com.buildnotifier.circleci"
   - Delete the entry

2. **No Projects Showing**: Ensure you follow projects on CircleCI web UI first

3. **Notifications Not Working**: Check System Settings > Notifications

4. **Build Logs**: Run from terminal to see console output:
   ```bash
   .build/debug/BuildNotifier
   ```

5. **Reset All Data**:
   ```bash
   # Clear preferences
   defaults delete com.buildnotifier.circleci
   
   # Clear keychain entry
   security delete-generic-password -s com.buildnotifier.circleci
   ```

### Architecture Notes

- **SwiftUI + MenuBarExtra**: Native macOS 14+ menubar API
- **Swift Concurrency**: async/await throughout
- **Actor Isolation**: `CircleCIAPI` is an actor for thread safety
- **@Observable**: Modern observation for state management
- **Keychain Services**: Secure token storage via Security framework
- **ServiceManagement**: Native launch-at-login via SMAppService
- **Ad-hoc Signing**: App is code-signed for notification support

## Troubleshooting

| Issue | Solution |
|-------|----------|
| App doesn't appear in menubar | Check if already running (Activity Monitor) |
| macOS says the app is from an unidentified developer | Open it once, then go to System Settings > Privacy & Security and click Open Anyway |
| Local build should use my own signing identity | Run `security find-identity -v -p codesigning`, then build with `SIGN_IDENTITY="..." ./build-app.sh` |
| "Invalid API token" | Regenerate token at circleci.com/account/api |
| No notifications | Enable in System Settings > Notifications |
| Builds not updating | Check polling interval in Settings |
| High API usage | Increase polling interval, reduce watched projects |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on macOS 14+
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with SwiftUI and Swift Concurrency
- Uses CircleCI API v1.1 and v2
- Inspired by the need for a lightweight build monitor
