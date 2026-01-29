#!/bin/bash
# Build proper macOS .app bundle for MetalSQLite

cd /Users/darianhickman/Documents/metalsqlite

echo "Building MetalSQLite.app bundle..."

# Create .app bundle structure
APP_DIR="MetalSQLite.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile Swift sources
echo "Compiling Swift sources..."
swiftc -o "$PWD/$APP_DIR/Contents/MacOS/MetalSQLite" \
  -framework Cocoa \
  -framework MetalKit \
  MetalSQLite/main.swift \
  MetalSQLite/AppDelegate.swift \
  MetalSQLite/TableViewController.swift

if [ $? -ne 0 ]; then
    echo "✗ Swift compilation failed"
    exit 1
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MetalSQLite</string>
    <key>CFBundleIdentifier</key>
    <string>com.darianhickman.metalsqlite</string>
    <key>CFBundleName</key>
    <string>MetalSQLite</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "✓ Build successful: $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
