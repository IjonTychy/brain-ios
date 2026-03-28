# brain-ios

What it should do (but doesn't, unless someone better than me makes it work): A native iOS runtime engine that turns Markdown skill definitions into fully functional native apps — no app update required.

## What is this?

brain-ios is a personal AI assistant that lives entirely on your device. Instead of hardcoded modules, it uses a **runtime engine** that interprets JSON-based skill definitions and renders them as native SwiftUI interfaces.

The metaphor: Markdown is DNA, the AI is the ribosome, JSON is the protein, the app is the cell.

## Architecture

```
.brainskill.md  →  AI (Ribosome)  →  skill.json  →  Runtime Engine  →  Native UI + Actions
   (DNA)                              (Protein)       (Cell)
```

- **~90 UI Primitives** — precompiled SwiftUI components, composed via JSON
- **~60 Action Primitives** — precompiled Swift handlers, invoked via JSON
- **~15 Logic Primitives** — conditions, loops, variables, templates
- **Multi-LLM Router** — Anthropic, OpenAI, Gemini, on-device, custom endpoints
- **23 iOS Bridges** — Contacts, EventKit, Mail, Camera, Health, HomeKit, NFC, Speech, ...
- **Proactive Intelligence** — pattern detection, knowledge extraction, self-improvement proposals

## Key Features

- **Offline-first** — everything works without internet
- **Skills as first-class citizens** — installed skills appear in navigation like native modules
- **Bootstrap skills** — Dashboard, Inbox, Calendar ship as JSON skills (not hardcoded)
- **On-device LLM** — privacy-first routing, local models for sensitive data
- **iPhone + iPad + Vision Pro** — one codebase via SwiftUI

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI, SF Symbols, BrainTheme design system |
| Database | GRDB + SQLite (shared App Group container) |
| LLM | Multi-provider router (Anthropic, OpenAI, Gemini, on-device) |
| Search | FTS5 full-text + embedding-based semantic search |
| Auth | Face ID / Touch ID |
| Secrets | iOS Keychain |
| Background | BGAppRefreshTask + App Intents |
| Widgets | WidgetKit (Quick Capture, Tasks, Brain Pulse) |
| Shortcuts | 12 App Intents with Siri phrases |

## Project Status

This project was actively developed from March 2026 with 500+ commits, 579 tests, and a working TestFlight build. Development has been paused. The codebase is functional but has known issues documented in `SESSION-LOG.md` and `REVIEW-NOTES.md`.

## Building

Requires macOS with Xcode 16+ and Swift 6.

```bash
# SPM tests (also works on Linux)
swift test

# Full iOS build
xcodebuild test -scheme brain-ios -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Note:** You need to replace placeholder values before building:
- `com.example.brain-ios` → your bundle identifier
- `TEAM_ID_HERE` → your Apple Developer Team ID
- `YOUR_GOOGLE_CLIENT_ID` → your Google OAuth client ID (for Gemini)
- API keys are entered by the user at runtime and stored in iOS Keychain

## Documentation

- `ARCHITECTURE.md` — full technical architecture and vision
- `SESSION-LOG.md` — development journal with decisions and rationale
- `REVIEW-NOTES.md` — code review findings and status
- `Skills/` — bundled .brainskill.md skill definitions

## License

This project is released into the **public domain** under the Unlicense. See `UNLICENSE` for details.
