#!/bin/bash
# Run script for MetalSQLite application

cd /Users/darianhickman/Documents/metalsqlite

# Check if server is already running
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "✓ Server already running on port 8080"
    PORT=8080
else
    echo "Starting Go HTTP server..."
    ./bin/metalsqlite-server >> /tmp/metalsqlite-server.log 2>&1 &
    SERVER_PID=$!
    echo "✓ Server started (PID: $SERVER_PID)"
    echo "  Logs: /tmp/metalsqlite-server.log"
    
    # Wait for server to write port file
    sleep 1
    
    # Read the port from file
    if [ -f /tmp/metalsqlite.port ]; then
        PORT=$(cat /tmp/metalsqlite.port)
    else
        echo "✗ Server failed to start. Check logs at /tmp/metalsqlite-server.log"
        exit 1
    fi
    
    # Verify server is listening
    if ! lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo "✗ Server failed to start. Check logs at /tmp/metalsqlite-server.log"
        exit 1
    fi
fi

# Display full server URL
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🚀 Server running at:"
echo "     http://[::1]:$PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Launching Swift application..."
open MetalSQLite.app

sleep 1
echo ""
echo "✓ Application launched!"
echo ""
echo "To stop the server:"
echo "  pkill -f metalsqlite-server"
