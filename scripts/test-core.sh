#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -module-cache-path .build/module-cache MobileGhost/Core/Journey.swift Tests/JourneyChecks.swift -o .build/journey-checks
.build/journey-checks
