# MetalSQLite

A high-performance SQLite viewer for macOS using Metal rendering and Go backend.

## Architecture

- **Go Backend**: HTTP server using the Banquet URL parser for SQLite queries
- **Swift Frontend**: Native macOS app with Metal-accelerated table rendering
- **Communication**: REST API over localhost with dynamic port allocation

## Quick Start

```bash
# Build and run everything
./rebuild-and-run.sh
```

This will:
1. Stop any existing processes
2. Build the Go server
3. Build the Swift app
4. Start the server on a random high port
5. Launch the macOS app
6. Run automated tests to verify everything works

## Manual Scripts

```bash
# Build Go server only
./build-go.sh

# Build Swift app only
./build.sh

# Run without rebuilding
./run.sh

# Run tests
./test.sh
```

## Components

### Go Server (`cmd/server/main.go`)
- Parses Banquet URLs for SQLite queries
- Handles cross-origin requests
- Uses modernc.org/sqlite (CGO-free)
- Supports dynamic port allocation

### Swift App
- `MetalSQLite/main.swift` - Application entry point
- `MetalSQLite/AppDelegate.swift` - App lifecycle and window management
- `MetalSQLite/TableViewController.swift` - Table view and data management

### Port Discovery
The Go server writes its port to `/tmp/metalsqlite.port` which the Swift app reads to discover the server.

## Default Database

The app loads `/Users/darianhickman/Documents/Index.sqlite` by default, querying the `tb0` table with a limit of 100 rows.

## Troubleshooting

- Check server logs: `tail -f /tmp/metalsqlite-server.log`
- Check app logs: `tail -f /tmp/metalsqlite-app.log`
- Verify processes: `ps aux | grep -E 'metalsqlite|MetalSQLite'`
- Test server: `curl -X POST http://[::1]:<PORT>/query -H "Content-Type: application/json" -d '{"banquet_url":"..."}'`

## Stopping

```bash
pkill -f metalsqlite-server
pkill -f MetalSQLite
```

## Known Issues

- The Banquet parser strips leading slashes from paths - this is handled automatically
- The Banquet parser may include table names in column selections - filtered automatically
