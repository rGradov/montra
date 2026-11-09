#!/bin/bash
set -euo pipefail

mcp_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$mcp_dir/.venv/bin/python" ]]; then
    echo "Set up the Montra MCP first. See $mcp_dir/README.md." >&2
    exit 1
fi
exec "$mcp_dir/.venv/bin/python" "$mcp_dir/server.py"
