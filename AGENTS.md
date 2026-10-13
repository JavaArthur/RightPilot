# RightPilot

- Native macOS 13+ host (AppKit/SwiftUI) and FinderSync extension. Build with Command Line Tools; no external dependencies.
- Sources/RightPilotCore contains Foundation-only configuration, menu policy, action URL protocol and safe file creation. Never import proprietary code or resources from the parent analysis directory.
- Host owns operations and preferences; the sandboxed extension snapshots Finder context and opens a typed URL to the host. Configuration notifications contain no commands. Validate every inbound payload.
- No shell execution, deletion, overwrite, privileged helper or accessibility permission in this product. File creation must use exclusive creation and reject path traversal.
- Preserve damaged or future-version preferences and surface an error; do not silently overwrite them.
- Run scripts/check.sh and scripts/build-app.sh. Distinguish core/native checks from Finder-hosted runtime evidence.
- Commit source, scripts, tests and documentation only; exclude builds, local verification, user preferences and reverse-engineering evidence.
