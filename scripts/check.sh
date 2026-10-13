#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run CoreChecks
mkdir -p .build/checks
xcrun swiftc -swift-version 5 Sources/RightPilotCore/*.swift Shared/*.swift Tests/NativeChecks/main.swift -o .build/checks/NativeChecks
.build/checks/NativeChecks
