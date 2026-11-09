#!/bin/bash
set -euo pipefail
mcp_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir="$(dirname -- "$mcp_dir")"
build_dir="$mcp_dir/.build"
mkdir -p "$build_dir/module-cache"

# Apple's macro plugin server nests sandbox-exec, which the DSH workspace
# sandbox blocks ("sandbox_apply: Operation not permitted"). SwiftData's macro
# is Apple's own; disabling its extra sandbox is safe here and keeps the fixture
# buildable from the agent. Set MONTRA_DISABLE_MACRO_SANDBOX=0 to turn it off.
swift_flags=()
if [[ "${MONTRA_DISABLE_MACRO_SANDBOX:-1}" == "1" ]]; then
    swift_flags+=("-disable-sandbox")
fi

xcrun --sdk macosx swiftc \
    "${swift_flags[@]}" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -target "$(/usr/bin/arch)-apple-macos15.0" -module-name Montra -swift-version 5 \
    -module-cache-path "$build_dir/module-cache" \
    "$project_dir/Montra/Models/"*.swift "$project_dir/Montra/Design/Theme.swift" \
    "$project_dir/Montra/Store/"{Repositories,PlanRepository,Finance,ExchangeRates}.swift \
    "$project_dir/Montra/Integration/"{LedgerAPI,LocalHTTPServer,LocalIntegration}.swift \
    "$mcp_dir/tests/Fixture.swift" -o "$build_dir/montra-http-fixture"
