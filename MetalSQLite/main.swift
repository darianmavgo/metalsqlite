import Cocoa
import Darwin

// Redirect stdout and stderr to a log file
let logPath = "/tmp/metalsqlite-app.log"
freopen(logPath, "a+", stdout)
freopen(logPath, "a+", stderr)

// Set buffering
setvbuf(stdout, nil, _IOLBF, 0) // Line buffered
setvbuf(stderr, nil, _IONBF, 0) // Unbuffered

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
