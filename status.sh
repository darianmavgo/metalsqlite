#!/bin/bash
# Status report for MetalSQLite

echo "╔════════════════════════════════════════╗"
echo "║     MetalSQLite Status Report          ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Server status
if pgrep -f metalsqlite-server > /dev/null; then
    PORT=$(cat /tmp/metalsqlite.port 2>/dev/null || echo "unknown")
    PID=$(pgrep -f metalsqlite-server)
    echo "✓ Go Server:"
    echo "  - Running: Yes (PID: $PID)"
    echo "  - Port: $PORT"
    echo "  - URL: http://[::1]:$PORT"
else
    echo "✗ Go Server: Not running"
fi

echo ""

# Swift app status
if pgrep -f "MetalSQLite.app" > /dev/null; then
    PID=$(pgrep -f "MetalSQLite.app")
    echo "✓ Swift App:"
    echo "  - Running: Yes (PID: $PID)"
    
    # Check visibility
    if osascript -e 'tell application "System Events" to get name of every process whose visible is true' 2>&1 | grep -q "MetalSQLite"; then
        echo "  - Visible: Yes"
        echo "  - Window: Showing"
    else
        echo "  - Visible: No"
        echo "  - Window: Hidden or minimized"
    fi
else
    echo "✗ Swift App: Not running"
fi

echo ""
echo "Recent server activity:"
tail -5 /tmp/metalsqlite-server.log 2>/dev/null | sed 's/^/  /'

echo ""
echo "─────────────────────────────────────────"
