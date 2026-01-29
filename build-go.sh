#!/bin/bash
# Build Go server for MetalSQLite

cd /Users/darianhickman/Documents/metalsqlite

echo "Building Go server..."

# Create bin directory if it doesn't exist
mkdir -p bin

# Build the server
go build -o bin/metalsqlite-server cmd/server/main.go

if [ $? -eq 0 ]; then
    echo "✓ Go server built successfully: bin/metalsqlite-server"
else
    echo "✗ Go build failed"
    exit 1
fi
