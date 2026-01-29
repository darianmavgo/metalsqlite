#!/bin/bash
# Full rebuild and run script

set -e  # Exit on error

cd /Users/darianhickman/Documents/metalsqlite

echo "=== Stopping existing processes ==="
pkill -f metalsqlite-server || true
pkill -f MetalSQLite || true
sleep 1

echo ""
echo "=== Building Go server ==="
./build-go.sh

echo ""
echo "=== Building Swift app ==="
./build.sh

echo ""
echo "=== Starting server ==="
./bin/metalsqlite-server > /tmp/metalsqlite-server.log 2>&1 &
SERVER_PID=$!
echo "✓ Server started (PID: $SERVER_PID)"

# Wait for server to start and write port file
sleep 2

if [ -f /tmp/metalsqlite.port ]; then
    PORT=$(cat /tmp/metalsqlite.port)
    echo "✓ Server running on port $PORT"
else
    echo "✗ Server failed to start"
    cat /tmp/metalsqlite-server.log
    exit 1
fi

echo ""
echo "=== Launching Swift application ==="
open MetalSQLite.app

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 Application launched"
echo "     Server: http://[::1]:$PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run tests
echo "Running system tests..."
sleep 2
./test.sh

echo ""
echo "View logs:"
echo "  tail -f /tmp/metalsqlite-server.log"
echo "  tail -f /tmp/metalsqlite-app.log"
echo ""
echo "To stop:"
echo "  pkill -f metalsqlite-server"
echo "  pkill -f MetalSQLite"
