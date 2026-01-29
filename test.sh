#!/bin/bash
# Test script to verify MetalSQLite is working

echo "=== MetalSQLite System Test ==="
echo ""

# Check if Go server is running
if pgrep -f metalsqlite-server > /dev/null; then
    PORT=$(cat /tmp/metalsqlite.port 2>/dev/null || echo "unknown")
    echo "✓ Go server is running on port $PORT"
else
    echo "✗ Go server is NOT running"
    exit 1
fi

# Check if Swift app is running
if pgrep -f "MetalSQLite.app" > /dev/null; then
    echo "✓ Swift app is running"
else
    echo "✗ Swift app is NOT running"
    exit 1
fi

# Check if app is visible
if osascript -e 'tell application "System Events" to get name of every process whose visible is true' 2>&1 | grep -q "MetalSQLite"; then
    echo "✓ MetalSQLite is visible (has window)"
else
    echo "✗ MetalSQLite is not visible"
    exit 1
fi

# Test server endpoint
echo ""
echo "Testing server endpoint..."
RESPONSE=$(curl -s -X POST http://[::1]:$PORT/query \
    -H "Content-Type: application/json" \
    -d '{"banquet_url":"/Users/darianhickman/Documents/Index.sqlite/tb0?limit=5"}')

if echo "$RESPONSE" | head -n 1 | jq -e '.error' > /dev/null 2>&1; then
    ERROR=$(echo "$RESPONSE" | head -n 1 | jq -r '.error')
    echo "✗ Server returned error: $ERROR"
    exit 1
fi

# Sum rows across all NDJSON lines
ROW_COUNT=$(echo "$RESPONSE" | jq -r 'select(.rows != null) | .rows | length' | awk '{s+=$1} END {print s+0}')
TOTAL=$(echo "$RESPONSE" | head -n 1 | jq '.total' 2>/dev/null || echo "0")

if [ "$ROW_COUNT" -gt 0 ]; then
    echo "✓ Server query successful (streaming): $ROW_COUNT rows returned (total: $TOTAL)"
else
    echo "✗ Server query returned no data"
    echo "Response: $RESPONSE"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ All tests passed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
